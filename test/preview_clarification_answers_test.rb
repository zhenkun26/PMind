# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"
require_relative "../scripts/preview_clarification_answers"

class PreviewClarificationAnswersTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-gap-scan.yaml")
  RECEIPT_FIXTURE = File.join(ROOT, "test/fixtures/clarification-answer-receipt-valid.yaml")
  READY_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-ready.yaml")

  def test_gap_scan_can_preview_the_first_round
    copy = assert_preview(gap_session, receipt)

    assert_includes copy, "# 回答已收到，尚未应用"
    assert_includes copy, "预演第 1 轮记录"
    assert_includes copy, "哪些角色可以导出？"
  end

  def test_clarifying_can_preview_the_next_consecutive_round
    document = clarifying_session
    copy = assert_preview(document, receipt_for(document))

    assert_includes copy, "预演第 2 轮记录"
    assert_includes copy, "需要补充哪一项可验证事实？"
  end

  def test_intake_state_is_rejected
    document = intake_session

    assert_invalid(document, receipt, "requires a gap_scan or clarifying Session")
  end

  def test_ready_to_compile_state_is_rejected
    document = load_yaml(READY_FIXTURE)
    candidate = receipt
    candidate["session_id"] = document["session_id"]
    candidate["session_raw_intent_sha256"] = document.dig("intake", "raw_intent_sha256")

    assert_invalid(document, candidate, "requires a gap_scan or clarifying Session")
  end

  def test_blocked_state_is_rejected
    document = blocked_session

    assert_invalid(document, receipt, "requires a gap_scan or clarifying Session")
  end

  def test_receipt_must_target_the_current_session
    candidate = receipt
    candidate["session_id"] = "session-20260821-999"

    assert_invalid(gap_session, candidate, "session_id does not match")
  end

  def test_receipt_must_preserve_the_raw_intent_digest
    candidate = receipt
    candidate["session_raw_intent_sha256"] = "0" * 64

    assert_invalid(gap_session, candidate, "raw Intent digest does not match")
  end

  def test_receipt_must_match_the_current_session_status
    candidate = receipt
    candidate["session_status"] = "clarifying"

    assert_invalid(gap_session, candidate, "captured session_status does not match")
  end

  def test_receipt_must_use_the_next_round_number
    candidate = receipt
    candidate["round_number"] = 2

    assert_invalid(gap_session, candidate, "next consecutive round 1")
  end

  def test_responses_must_match_next_questions_in_order
    document = gap_session
    second = pending_question("QUESTION-002", "需要补充哪一项可验证事实？", 4)
    document["questions"] << second
    document["compile_gate"]["next_question_ids"] = ["QUESTION-001", "QUESTION-002"]
    candidate = receipt
    candidate["responses"] << response_for(second, "不知道", "unknown")
    candidate["responses"].reverse!

    assert_invalid(document, candidate, "responses must exactly match next_question_ids in order")
  end

  def test_duplicate_question_responses_are_rejected
    candidate = receipt
    candidate["responses"] << deep_copy(candidate["responses"].first)

    assert_invalid(gap_session, candidate, "duplicate response for QUESTION-001")
  end

  def test_question_digest_rejects_stale_question_copy
    candidate = receipt
    candidate["responses"].first["question_sha256"] = "0" * 64

    assert_invalid(gap_session, candidate, "question digest does not match QUESTION-001")
  end

  def test_user_answer_digest_rejects_answer_drift
    candidate = receipt
    candidate["responses"].first["user_answer"] = "被修改的回答"

    assert_invalid(gap_session, candidate, "user answer digest does not match QUESTION-001")
  end

  def test_user_answer_cannot_exceed_the_data_minimization_limit
    candidate = receipt
    candidate["responses"].first["user_answer"] = "a" * 4001
    refresh_answer_digest(candidate["responses"].first)

    assert_invalid(gap_session, candidate, "exceeds 4000 characters")
  end

  def test_capture_time_cannot_predate_the_session
    candidate = receipt
    candidate["captured_at"] = "2026-08-21T10:59:59+08:00"

    assert_invalid(gap_session, candidate, "captured_at cannot predate")
  end

  def test_capture_time_cannot_predate_the_latest_completed_round
    document = clarifying_session
    candidate = receipt_for(document)
    candidate["captured_at"] = "2026-08-21T11:04:59+08:00"

    assert_invalid(document, candidate, "captured_at cannot predate")
  end

  def test_receipt_data_classification_cannot_downgrade_session
    document = gap_session
    document["intake"]["data_classification"] = "confidential"

    assert_invalid(document, receipt, "data classification cannot downgrade")
  end

  def test_personal_data_cannot_be_marked_public
    candidate = receipt
    candidate["contains_personal_data"] = true

    assert_invalid(gap_session, candidate, "personal data cannot use public classification")
  end

  def test_receipt_cannot_claim_to_contain_secrets
    candidate = receipt
    candidate["contains_secrets"] = true

    assert_invalid(gap_session, candidate, "expected constant false")
  end

  def test_each_response_kind_has_explicit_non_committal_copy
    expected = {
      "answered" => "等待归一化与复核",
      "skipped" => "按安全默认或停止条件处理",
      "unknown" => "将重新判断是否阻塞",
      "refused" => "不会推断或补写"
    }

    expected.each do |kind, message|
      candidate = receipt
      candidate["responses"].first["response_kind"] = kind
      copy = assert_preview(gap_session, candidate)
      assert_includes copy, message
    end
  end

  def test_confirmation_copy_never_echoes_raw_answers_or_internal_fields
    candidate = receipt
    copy = assert_preview(gap_session, candidate)

    forbidden = [
      candidate.dig("responses", 0, "user_answer"),
      candidate.dig("responses", 0, "user_answer_sha256"),
      candidate.dig("responses", 0, "question_sha256"),
      candidate["session_raw_intent_sha256"],
      "QUESTION-001",
      "gap_scan",
      "risk_authority",
      "priority"
    ]
    forbidden.each { |value| refute_includes copy, value }
  end

  def test_dynamic_question_is_single_line_and_markdown_safe_while_answer_stays_hidden
    document = gap_session
    question = document["questions"].first
    question["question"] = "<script>alert(1)</script>\n# 标题 *强调*"
    candidate = receipt_for(document)
    candidate["responses"].first["user_answer"] = "<private>不要回显</private>"
    refresh_answer_digest(candidate["responses"].first)
    copy = assert_preview(document, candidate)

    assert_includes copy, "&lt;script&gt;alert(1)&lt;/script&gt; \\# 标题 \\*强调\\*"
    refute_includes copy, "<script>"
    refute_includes copy, "<private>"
    refute_includes copy, "不要回显"
  end

  def test_sensitive_receipt_adds_no_echo_privacy_notice
    candidate = receipt
    candidate["data_classification"] = "confidential"
    candidate["contains_personal_data"] = true
    copy = assert_preview(gap_session, candidate)

    assert_includes copy, "确认文案不会回显原答"
    assert_includes copy, "不要加入密钥或 token"
  end

  def test_missing_file_is_reported_without_copy
    preview = previewer

    assert_nil preview.preview_files(File.join(ROOT, "missing-session.yaml"), RECEIPT_FIXTURE)
    assert preview.errors.any? { |error| error.include?("cannot load YAML") }
  end

  def test_cli_is_read_only_and_does_not_echo_the_answer
    before_session = File.binread(SESSION_FIXTURE)
    before_receipt = File.binread(RECEIPT_FIXTURE)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_answers.rb"),
      SESSION_FIXTURE,
      RECEIPT_FIXTURE,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "# 回答已收到，尚未应用"
    refute_includes stdout, receipt.dig("responses", 0, "user_answer")
    assert_equal "", stderr
    assert_equal before_session, File.binread(SESSION_FIXTURE)
    assert_equal before_receipt, File.binread(RECEIPT_FIXTURE)
  end

  def test_cli_requires_exactly_two_paths
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_answers.rb"),
      SESSION_FIXTURE,
      chdir: ROOT
    )

    refute status.success?
    assert_equal "", stdout
    assert_includes stderr, "Usage:"
  end

  private

  def assert_preview(session_document, receipt_document)
    preview = previewer
    copy = preview.preview(session_document, receipt_document)
    assert copy, preview.errors.join("\n")
    copy
  end

  def assert_invalid(session_document, receipt_document, expected_error)
    preview = previewer
    assert_nil preview.preview(session_document, receipt_document)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
    raw_answer = receipt_document.dig("responses", 0, "user_answer")
    refute_includes preview.errors.join("\n"), raw_answer if raw_answer
  end

  def previewer
    PMind::ClarificationAnswerPreview.new(ROOT)
  end

  def gap_session
    load_yaml(SESSION_FIXTURE)
  end

  def receipt
    load_yaml(RECEIPT_FIXTURE)
  end

  def intake_session
    document = gap_session
    document["status"] = "intake"
    %w[gaps questions rounds assumptions unknowns decisions].each { |field| document[field] = [] }
    document["compile_gate"] = {
      "ready" => false,
      "blocking_reasons" => [],
      "material_conflicts" => [],
      "high_risk_actions" => [],
      "next_question_ids" => [],
      "stop_reason" => "not_stopped"
    }
    document
  end

  def blocked_session
    document = gap_session
    document["status"] = "blocked"
    gate = document["compile_gate"]
    gate["blocking_reasons"] = ["用户拒绝确认不可安全默认的导出权限。"]
    gate["next_question_ids"] = []
    gate["stop_reason"] = "blocked"
    document
  end

  def clarifying_session
    document = gap_session
    document["status"] = "clarifying"
    first_question = document["questions"].first
    first_question["status"] = "asked"
    first_question["round_number"] = 1
    document["rounds"] = [{
      "round_number" => 1,
      "completed_at" => "2026-08-21T11:05:00+08:00",
      "answers" => [{
        "question_id" => "QUESTION-001",
        "user_answer" => "只有具有 export_users 权限的角色。",
        "outcome_status" => "resolved",
        "normalized_conclusion" => "导出入口和服务端接口都必须检查 export_users 权限。",
        "affected_fields" => ["constraints.product", "risks"]
      }]
    }]
    risk_gap = document["gaps"].find { |gap| gap["dimension"] == "risk_authority" }
    risk_gap["status"] = "resolved"
    risk_gap["blocking"] = false
    risk_gap["summary"] = "只有具有 export_users 权限的角色可以导出。"
    risk_gap["source_refs"] = ["QUESTION-001"]
    risk_gap.delete("knowledge_ref")
    document["unknowns"].delete_if { |unknown| unknown["unknown_id"] == "UNKNOWN-002" }
    document["questions"] << pending_question("QUESTION-002", "需要补充哪一项可验证事实？", 4)
    document["compile_gate"]["next_question_ids"] = ["QUESTION-002"]
    document
  end

  def receipt_for(document)
    candidate = receipt
    candidate["session_id"] = document["session_id"]
    candidate["session_raw_intent_sha256"] = document.dig("intake", "raw_intent_sha256")
    candidate["session_status"] = document["status"] if %w[gap_scan clarifying].include?(document["status"])
    candidate["round_number"] = document["rounds"].length + 1
    candidate["captured_at"] = "2026-08-21T11:10:00+08:00"
    question_id = document.dig("compile_gate", "next_question_ids", 0)
    question = document["questions"].find { |entry| entry["question_id"] == question_id }
    candidate["responses"].first["question_id"] = question_id
    candidate["responses"].first["question_sha256"] = Digest::SHA256.hexdigest(question["question"])
    candidate
  end

  def pending_question(question_id, question, score)
    {
      "question_id" => question_id,
      "gap_dimension" => "evidence",
      "question" => question,
      "why_now" => "答案可能改变方案或验收。",
      "affected_fields" => ["knowledge.unknowns"],
      "safe_default_or_stop" => "未回答时保留为非阻塞 unknown。",
      "priority" => {
        "materiality" => 2,
        "uncertainty" => 2,
        "answerability" => 1,
        "friction" => 1,
        "score" => score
      },
      "status" => "pending"
    }
  end

  def response_for(question, user_answer, kind)
    response = {
      "question_id" => question["question_id"],
      "question_sha256" => Digest::SHA256.hexdigest(question["question"]),
      "response_kind" => kind,
      "user_answer" => user_answer,
      "user_answer_sha256" => ""
    }
    refresh_answer_digest(response)
    response
  end

  def refresh_answer_digest(response)
    response["user_answer_sha256"] = Digest::SHA256.hexdigest(response["user_answer"])
  end

  def load_yaml(path)
    YAML.safe_load(
      File.read(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
