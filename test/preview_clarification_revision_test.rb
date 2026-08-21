# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"
require_relative "../scripts/preview_clarification_revision"

class PreviewClarificationRevisionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-gap-scan.yaml")
  RECEIPT_FIXTURE = File.join(ROOT, "test/fixtures/clarification-answer-receipt-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/clarification-revision-proposal-valid.yaml")
  READY_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-ready.yaml")

  def test_gap_scan_can_preview_ready_to_compile
    copy = assert_preview(source_session, answer_receipt, revision_proposal)

    assert_includes copy, "具备 Prompt Package 编译条件"
    assert_equal "ready_to_compile", previewer_candidate_status(source_session, answer_receipt, revision_proposal)
  end

  def test_gap_scan_can_preview_clarifying
    proposal = gap_proposal("clarifying")
    preview = previewer

    assert preview.preview(source_session, answer_receipt, proposal), preview.errors.join("\n")
    assert_equal "clarifying", preview.candidate_session["status"]
    assert_equal ["QUESTION-002"], preview.candidate_session.dig("compile_gate", "next_question_ids")
  end

  def test_gap_scan_can_preview_blocked
    proposal = gap_proposal("blocked")
    preview = previewer

    assert preview.preview(source_session, answer_receipt, proposal), preview.errors.join("\n")
    assert_equal "blocked", preview.candidate_session["status"]
  end

  def test_clarifying_can_preview_ready_to_compile
    session, receipt = clarifying_inputs
    proposal = clarifying_proposal(session, receipt, "ready_to_compile")

    assert_equal "ready_to_compile", previewer_candidate_status(session, receipt, proposal)
  end

  def test_clarifying_can_preview_clarifying
    session, receipt = clarifying_inputs
    proposal = clarifying_proposal(session, receipt, "clarifying")

    assert_equal "clarifying", previewer_candidate_status(session, receipt, proposal)
  end

  def test_clarifying_can_preview_blocked
    session, receipt = clarifying_inputs
    proposal = clarifying_proposal(session, receipt, "blocked")

    assert_equal "blocked", previewer_candidate_status(session, receipt, proposal)
  end

  def test_ready_source_state_is_rejected
    session = load_yaml(READY_FIXTURE)
    receipt = answer_receipt
    receipt["session_id"] = session["session_id"]
    receipt["session_raw_intent_sha256"] = session.dig("intake", "raw_intent_sha256")

    assert_invalid(session, receipt, revision_proposal, "requires a gap_scan or clarifying Session")
  end

  def test_target_cannot_return_to_gap_scan
    proposal = revision_proposal
    proposal["patch"]["status_after"] = "gap_scan"

    assert_invalid(source_session, answer_receipt, proposal, "outside enum")
  end

  def test_target_cannot_return_to_intake
    proposal = revision_proposal
    proposal["patch"]["status_after"] = "intake"

    assert_invalid(source_session, answer_receipt, proposal, "outside enum")
  end

  def test_all_source_bindings_must_match
    mutations = {
      "session_id" => "session-20260821-999",
      "session_raw_intent_sha256" => "0" * 64,
      "source_session_status" => "clarifying",
      "receipt_id" => "receipt-20260821-999",
      "round_number" => 2
    }

    mutations.each do |field, value|
      proposal = revision_proposal
      proposal[field] = value
      assert_invalid(source_session, answer_receipt, proposal, "#{field} does not match its source")
    end
  end

  def test_proposal_cannot_predate_receipt
    proposal = revision_proposal
    proposal["created_at"] = "2026-08-21T11:04:00+08:00"
    proposal.dig("patch", "append_round")["completed_at"] = proposal["created_at"]

    assert_invalid(source_session, answer_receipt, proposal, "cannot predate its Answer Receipt")
  end

  def test_question_updates_must_match_receipt_order
    proposal = revision_proposal
    proposal.dig("patch", "question_updates", 0)["question_id"] = "QUESTION-999"

    assert_invalid(source_session, answer_receipt, proposal, "question_updates must exactly match")
  end

  def test_normalization_must_bind_the_source_answer_digest
    proposal = revision_proposal
    proposal.dig("patch", "append_round", "answers", 0)["source_user_answer_sha256"] = "0" * 64

    assert_invalid(source_session, answer_receipt, proposal, "normalization source answer digest does not match")
  end

  def test_proposal_cannot_supply_or_replace_raw_answer
    proposal = revision_proposal
    proposal.dig("patch", "append_round", "answers", 0)["user_answer"] = "伪造回答"

    assert_invalid(source_session, answer_receipt, proposal, "unexpected field user_answer")
  end

  def test_response_kind_limits_normalized_outcome
    receipt = answer_receipt
    receipt.dig("responses", 0)["response_kind"] = "refused"

    assert_invalid(source_session, receipt, revision_proposal, "refused response cannot become resolved")
  end

  def test_affected_fields_must_match_question_contract
    proposal = revision_proposal
    proposal.dig("patch", "append_round", "answers", 0)["affected_fields"] = ["scope.in_scope"]

    assert_invalid(source_session, answer_receipt, proposal, "normalized affected_fields must match")
  end

  def test_normalized_conclusion_has_a_data_minimization_limit
    proposal = revision_proposal
    proposal.dig("patch", "append_round", "answers", 0)["normalized_conclusion"] = "a" * 2001

    assert_invalid(source_session, answer_receipt, proposal, "exceeds 2000 characters")
  end

  def test_user_visible_effect_has_a_data_minimization_limit
    proposal = revision_proposal
    proposal.dig("patch", "append_round", "answers", 0)["user_visible_effect"] = "a" * 501

    assert_invalid(source_session, answer_receipt, proposal, "exceeds 500 characters")
  end

  def test_gap_update_must_match_question_dimension
    proposal = revision_proposal
    proposal.dig("patch", "gap_updates", 0)["dimension"] = "scope"

    assert_invalid(source_session, answer_receipt, proposal, "gap_updates must exactly match")
  end

  def test_gap_update_must_cite_its_question
    proposal = revision_proposal
    proposal.dig("patch", "gap_updates", 0)["source_question_ids"] = ["QUESTION-999"]

    assert_invalid(source_session, answer_receipt, proposal, "must cite its current question only")
  end

  def test_gap_status_must_match_normalized_outcome
    proposal = revision_proposal
    proposal.dig("patch", "gap_updates", 0)["status"] = "assumed"

    assert_invalid(source_session, answer_receipt, proposal, "status must match its normalized outcome")
  end

  def test_unrelated_knowledge_cannot_be_removed
    proposal = revision_proposal
    proposal.dig("patch", "unknown_ids_to_remove") << "UNKNOWN-001"

    assert_invalid(source_session, answer_receipt, proposal, "cannot remove unrelated knowledge UNKNOWN-001")
  end

  def test_assumption_addition_can_support_an_assumed_gap
    proposal = assumption_proposal
    copy = assert_preview(source_session, answer_receipt, proposal)

    assert_includes copy, "## 新增假设"
    assert_includes copy, "导出角色定义在首版保持稳定"
  end

  def test_unknown_addition_can_keep_a_critical_gap_blocked
    receipt = answer_receipt
    receipt.dig("responses", 0)["response_kind"] = "unknown"
    proposal = unknown_proposal
    copy = assert_preview(source_session, receipt, proposal)

    assert_includes copy, "哪些角色被授权导出？（阻塞）"
    assert_includes copy, "保持阻塞"
  end

  def test_decision_addition_is_visible_without_decision_maker_ref
    proposal = revision_proposal
    proposal.dig("patch", "decisions_to_add") << {
      "decision_id" => "DECISION-002",
      "selected_option" => "使用 export_users 权限控制导出",
      "decision_maker_ref" => "user-test",
      "rationale" => "用户明确限定可导出角色。",
      "alternatives" => ["允许所有管理员导出"],
      "decided_at" => "2026-08-21"
    }
    copy = assert_preview(source_session, answer_receipt, proposal)

    assert_includes copy, "## 新增决策"
    assert_includes copy, "使用 export\\_users 权限控制导出"
    refute_includes copy, "user-test"
  end

  def test_existing_high_risk_action_cannot_be_removed
    proposal = revision_proposal
    proposal.dig("patch", "compile_gate_after", "high_risk_actions").clear

    assert_invalid(source_session, answer_receipt, proposal, "existing high-risk action external_service_write must be preserved")
  end

  def test_existing_high_risk_action_cannot_be_reworded
    proposal = revision_proposal
    proposal.dig("patch", "compile_gate_after", "high_risk_actions", 0)["description"] = "被弱化的动作"

    assert_invalid(source_session, answer_receipt, proposal, "must be preserved exactly")
  end

  def test_candidate_validator_rejects_orphaned_blocking_unknown
    proposal = revision_proposal
    proposal.dig("patch", "unknown_ids_to_remove").clear

    assert_invalid(source_session, answer_receipt, proposal, "blocking unknown remains")
  end

  def test_candidate_round_uses_exact_receipt_answer_and_source_remains_unchanged
    session = source_session
    before = deep_copy(session)
    receipt = answer_receipt
    preview = previewer

    assert preview.preview(session, receipt, revision_proposal), preview.errors.join("\n")
    assert_equal receipt.dig("responses", 0, "user_answer"), preview.candidate_session.dig("rounds", 0, "answers", 0, "user_answer")
    assert_equal before, session
  end

  def test_confirmation_copy_hides_raw_answer_digests_ids_and_field_paths
    proposal = revision_proposal
    copy = assert_preview(source_session, answer_receipt, proposal)
    forbidden = [
      answer_receipt.dig("responses", 0, "user_answer"),
      answer_receipt.dig("responses", 0, "user_answer_sha256"),
      proposal["session_raw_intent_sha256"],
      "QUESTION-001",
      "UNKNOWN-002",
      "constraints.product",
      "risk_authority",
      "source_question_ids"
    ]
    forbidden.each { |value| refute_includes copy, value }
  end

  def test_dynamic_confirmation_content_is_markdown_safe
    proposal = revision_proposal
    answer = proposal.dig("patch", "append_round", "answers", 0)
    answer["normalized_conclusion"] = "<script>结论</script>\n# 标题"
    answer["user_visible_effect"] = "*影响* [链接](https://invalid.test)"
    copy = assert_preview(source_session, answer_receipt, proposal)

    assert_includes copy, "&lt;script&gt;结论&lt;/script&gt; \\# 标题"
    assert_includes copy, "\\*影响\\* \\[链接\\](https://invalid.test)"
    refute_includes copy, "<script>"
  end

  def test_cli_is_read_only_across_all_three_inputs
    before = [SESSION_FIXTURE, RECEIPT_FIXTURE, PROPOSAL_FIXTURE].to_h do |path|
      [path, File.binread(path)]
    end
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_revision.rb"),
      SESSION_FIXTURE,
      RECEIPT_FIXTURE,
      PROPOSAL_FIXTURE,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "# 请确认我对本轮回答的理解"
    refute_includes stdout, answer_receipt.dig("responses", 0, "user_answer")
    assert_equal "", stderr
    before.each { |path, content| assert_equal content, File.binread(path) }
  end

  def test_cli_requires_exactly_three_paths
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_revision.rb"),
      SESSION_FIXTURE,
      RECEIPT_FIXTURE,
      chdir: ROOT
    )

    refute status.success?
    assert_equal "", stdout
    assert_includes stderr, "Usage:"
  end

  def test_missing_file_is_reported_without_copy
    preview = previewer

    assert_nil preview.preview_files(SESSION_FIXTURE, RECEIPT_FIXTURE, File.join(ROOT, "missing-proposal.yaml"))
    assert preview.errors.any? { |error| error.include?("cannot load YAML") }
  end

  private

  def assert_preview(session, receipt, proposal)
    preview = previewer
    copy = preview.preview(session, receipt, proposal)
    assert copy, preview.errors.join("\n")
    copy
  end

  def assert_invalid(session, receipt, proposal, expected_error)
    preview = previewer
    assert_nil preview.preview(session, receipt, proposal)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
    raw_answer = receipt.dig("responses", 0, "user_answer")
    refute_includes preview.errors.join("\n"), raw_answer if raw_answer
  end

  def previewer_candidate_status(session, receipt, proposal)
    preview = previewer
    assert preview.preview(session, receipt, proposal), preview.errors.join("\n")
    preview.candidate_session["status"]
  end

  def previewer
    PMind::ClarificationRevisionPreview.new(ROOT)
  end

  def source_session
    load_yaml(SESSION_FIXTURE)
  end

  def answer_receipt
    load_yaml(RECEIPT_FIXTURE)
  end

  def revision_proposal
    load_yaml(PROPOSAL_FIXTURE)
  end

  def gap_proposal(target)
    proposal = revision_proposal
    patch = proposal["patch"]
    case target
    when "clarifying"
      patch["status_after"] = "clarifying"
      patch["questions_to_add"] = [pending_question("QUESTION-002", "evidence", "需要补充哪一项可验证事实？", 4)]
      patch["compile_gate_after"]["ready"] = false
      patch["compile_gate_after"]["next_question_ids"] = ["QUESTION-002"]
      patch["compile_gate_after"]["stop_reason"] = "not_stopped"
    when "blocked"
      answer = patch.dig("append_round", "answers", 0)
      answer["outcome_status"] = "unknown"
      answer["normalized_conclusion"] = "导出权限仍未确定。"
      answer["user_visible_effect"] = "在权限边界确认前暂停生成可执行交接。"
      gap = patch.dig("gap_updates", 0)
      gap["status"] = "unknown"
      gap["blocking"] = true
      gap["summary"] = "导出权限仍未确定。"
      gap["knowledge_ref"] = "UNKNOWN-002"
      patch["unknown_ids_to_remove"] = []
      patch["status_after"] = "blocked"
      patch["compile_gate_after"]["ready"] = false
      patch["compile_gate_after"]["blocking_reasons"] = ["导出权限无法安全默认。"]
      patch["compile_gate_after"]["stop_reason"] = "blocked"
    end
    proposal
  end

  def assumption_proposal
    proposal = revision_proposal
    patch = proposal["patch"]
    answer = patch.dig("append_round", "answers", 0)
    answer["outcome_status"] = "assumed"
    answer["normalized_conclusion"] = "暂按 export_users 权限定义保持稳定处理。"
    gap = patch.dig("gap_updates", 0)
    gap["status"] = "assumed"
    gap["knowledge_ref"] = "ASSUMP-002"
    gap["summary"] = "暂按 export_users 权限定义保持稳定处理。"
    patch["assumptions_to_add"] = [{
      "assumption_id" => "ASSUMP-002",
      "statement" => "导出角色定义在首版保持稳定。",
      "invalidation_impact" => "需要重新设计权限映射。",
      "verification_method" => "由权限负责人确认角色矩阵。"
    }]
    proposal
  end

  def unknown_proposal
    proposal = gap_proposal("blocked")
    patch = proposal["patch"]
    gap = patch.dig("gap_updates", 0)
    gap["knowledge_ref"] = "UNKNOWN-003"
    patch["unknown_ids_to_remove"] = ["UNKNOWN-002"]
    patch["unknowns_to_add"] = [{
      "unknown_id" => "UNKNOWN-003",
      "question" => "哪些角色被授权导出？",
      "blocking" => true
    }]
    proposal
  end

  def clarifying_inputs
    session = source_session
    session["status"] = "clarifying"
    first_question = session["questions"].first
    first_question["status"] = "asked"
    first_question["round_number"] = 1
    session["rounds"] = [{
      "round_number" => 1,
      "completed_at" => "2026-08-21T11:06:00+08:00",
      "answers" => [{
        "question_id" => "QUESTION-001",
        "user_answer" => "只有具有 export_users 权限的角色。",
        "outcome_status" => "resolved",
        "normalized_conclusion" => "导出入口和服务端接口都必须检查 export_users 权限。",
        "affected_fields" => ["constraints.product", "risks"]
      }]
    }]
    risk_gap = session["gaps"].find { |gap| gap["dimension"] == "risk_authority" }
    risk_gap["status"] = "resolved"
    risk_gap["blocking"] = false
    risk_gap["summary"] = "只有具有 export_users 权限的角色可以导出。"
    risk_gap["source_refs"] = ["QUESTION-001"]
    risk_gap.delete("knowledge_ref")
    session["unknowns"].delete_if { |unknown| unknown["unknown_id"] == "UNKNOWN-002" }
    session["questions"] << pending_question("QUESTION-002", "evidence", "需要补充哪一项可验证事实？", 4)
    session["compile_gate"]["next_question_ids"] = ["QUESTION-002"]

    receipt = answer_receipt
    receipt["receipt_id"] = "receipt-20260821-002"
    receipt["session_status"] = "clarifying"
    receipt["round_number"] = 2
    receipt["captured_at"] = "2026-08-21T11:10:00+08:00"
    receipt["responses"] = [response_for(session["questions"].last, "官方文档位于已审查的仓库路径。", "answered")]
    [session, receipt]
  end

  def clarifying_proposal(session, receipt, target)
    proposal = revision_proposal
    proposal["proposal_id"] = "proposal-20260821-002"
    proposal["created_at"] = "2026-08-21T11:11:00+08:00"
    proposal["source_session_status"] = "clarifying"
    proposal["receipt_id"] = receipt["receipt_id"]
    proposal["round_number"] = 2
    patch = proposal["patch"]
    patch["status_after"] = target
    patch["question_updates"] = [{"question_id" => "QUESTION-002", "status" => "asked", "round_number" => 2}]
    patch["append_round"] = {
      "round_number" => 2,
      "completed_at" => proposal["created_at"],
      "answers" => [{
        "question_id" => "QUESTION-002",
        "source_user_answer_sha256" => receipt.dig("responses", 0, "user_answer_sha256"),
        "outcome_status" => "resolved",
        "normalized_conclusion" => "所需事实已有可核验的仓库来源。",
        "affected_fields" => ["knowledge.unknowns"],
        "user_visible_effect" => "实现可以引用已审查的仓库资料。"
      }]
    }
    patch["gap_updates"] = [{
      "dimension" => "evidence",
      "source_question_ids" => ["QUESTION-002"],
      "status" => "resolved",
      "blocking" => false,
      "summary" => "所需事实已有可核验的仓库来源。"
    }]
    patch["unknown_ids_to_remove"] = ["UNKNOWN-001"]
    patch["questions_to_add"] = []
    gate = patch["compile_gate_after"]
    gate["blocking_reasons"] = []
    gate["material_conflicts"] = []
    gate["next_question_ids"] = []
    case target
    when "ready_to_compile"
      gate["ready"] = true
      gate["stop_reason"] = "sufficient_information"
    when "clarifying"
      patch["questions_to_add"] = [pending_question("QUESTION-003", "current_state", "现有导出链路还有哪些限制？", 4)]
      gate["ready"] = false
      gate["next_question_ids"] = ["QUESTION-003"]
      gate["stop_reason"] = "not_stopped"
    when "blocked"
      answer = patch.dig("append_round", "answers", 0)
      answer["outcome_status"] = "unknown"
      answer["normalized_conclusion"] = "可核验来源仍不明确。"
      patch["gap_updates"].first["status"] = "unknown"
      patch["gap_updates"].first["summary"] = "可核验来源仍不明确。"
      patch["gap_updates"].first["knowledge_ref"] = "UNKNOWN-001"
      patch["unknown_ids_to_remove"] = []
      gate["ready"] = false
      gate["blocking_reasons"] = ["证据冲突需要人工确认。"]
      gate["stop_reason"] = "blocked"
    end
    proposal
  end

  def pending_question(question_id, dimension, question, score)
    {
      "question_id" => question_id,
      "gap_dimension" => dimension,
      "question" => question,
      "why_now" => "答案可能改变方案或验收。",
      "affected_fields" => ["knowledge.unknowns"],
      "safe_default_or_stop" => "未回答时保留为 unknown。",
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

  def response_for(question, answer, kind)
    {
      "question_id" => question["question_id"],
      "question_sha256" => Digest::SHA256.hexdigest(question["question"]),
      "response_kind" => kind,
      "user_answer" => answer,
      "user_answer_sha256" => Digest::SHA256.hexdigest(answer)
    }
  end

  def load_yaml(path)
    YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
