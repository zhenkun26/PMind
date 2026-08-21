# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"
require_relative "../scripts/validate_clarification_session"

class ValidateClarificationSessionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")

  def test_ready_to_compile_state_is_valid
    assert_valid(session)
  end

  def test_intake_state_is_valid_before_gap_scan
    assert_valid(intake_session)
  end

  def test_gap_scan_state_is_valid_with_prioritized_pending_questions
    assert_valid(gap_scan_session)
  end

  def test_clarifying_state_is_valid_with_completed_and_pending_questions
    assert_valid(clarifying_session)
  end

  def test_blocked_state_is_valid_when_the_reason_is_preserved
    assert_valid(blocked_session)
  end

  def test_intake_state_rejects_a_populated_gap_map
    document = session
    document["status"] = "intake"
    document["compile_gate"]["ready"] = false
    document["compile_gate"]["stop_reason"] = "not_stopped"

    assert_invalid(document, "intake state allows only immutable Intake data")
  end

  def test_gap_scan_state_rejects_completed_rounds
    document = session
    document["status"] = "gap_scan"
    document["compile_gate"]["ready"] = false
    document["compile_gate"]["next_question_ids"] = ["QUESTION-001"]
    document["compile_gate"]["stop_reason"] = "not_stopped"

    assert_invalid(document, "gap_scan state requires a complete Gap Map")
  end

  def test_clarifying_state_requires_next_questions
    document = clarifying_session
    document["compile_gate"]["next_question_ids"] = []

    assert_invalid(document, "clarifying state requires completed rounds")
  end

  def test_ready_state_rejects_a_blocking_gap
    document = blocked_session
    document["status"] = "ready_to_compile"
    gate = document["compile_gate"]
    gate["ready"] = true
    gate["blocking_reasons"] = []
    gate["stop_reason"] = "sufficient_information"

    assert_invalid(document, "compile gate cannot be ready while a blocking Gap remains")
  end

  def test_blocked_state_requires_a_recorded_reason_or_conflict
    document = blocked_session
    document["compile_gate"]["blocking_reasons"] = []

    assert_invalid(document, "blocked state requires a recorded blocker")
  end

  def test_raw_intent_digest_is_immutable
    document = session
    document.dig("intake", "raw_intent") << "追加内容"

    assert_invalid(document, "raw_intent_sha256 does not match")
  end

  def test_personal_data_cannot_be_labeled_public
    document = session
    document["intake"]["contains_personal_data"] = true

    assert_invalid(document, "personal data cannot use public classification")
  end

  def test_non_intake_state_requires_all_nine_gap_dimensions
    document = session
    document["gaps"].delete_if { |gap| gap["dimension"] == "handoff" }

    assert_invalid(document, "missing Gap dimension handoff")
  end

  def test_gap_dimensions_cannot_be_duplicated
    document = session
    duplicate = deep_copy(document["gaps"].first)
    duplicate["summary"] = "重复维度不允许覆盖原结论。"
    document["gaps"] << duplicate

    assert_invalid(document, "duplicate Gap dimension outcome")
  end

  def test_critical_unknown_gap_must_remain_blocking
    document = blocked_session
    risk_gap = gap(document, "risk_authority")
    risk_gap["blocking"] = false
    unknown(document, "UNKNOWN-002")["blocking"] = false

    assert_invalid(document, "critical unknown Gap risk_authority must remain blocking")
  end

  def test_assumed_gap_requires_a_matching_assumption
    document = session
    gap(document, "constraints")["knowledge_ref"] = "ASSUMP-999"

    assert_invalid(document, "requires a matching ASSUMP knowledge_ref")
  end

  def test_gap_cannot_claim_an_unanswered_question_as_source
    document = gap_scan_session
    risk_gap = gap(document, "risk_authority")
    risk_gap["status"] = "resolved"
    risk_gap["blocking"] = false
    risk_gap["source_refs"] = ["QUESTION-001"]
    risk_gap.delete("knowledge_ref")

    assert_invalid(document, "cannot use unanswered question QUESTION-001")
  end

  def test_gap_status_cannot_contradict_its_answer_outcome
    document = session
    document.dig("rounds", 0, "answers", 0)["outcome_status"] = "unknown"

    assert_invalid(document, "Gap risk_authority status contradicts answer outcome")
  end

  def test_question_priority_score_is_derived
    document = session
    document["questions"].first["priority"]["score"] = 0

    assert_invalid(document, "priority score must equal 7")
  end

  def test_next_questions_must_use_the_highest_priority_pending_prefix
    document = gap_scan_session
    document["questions"] << pending_question("QUESTION-002", "evidence", 4)
    document["compile_gate"]["next_question_ids"] = ["QUESTION-002"]

    assert_invalid(document, "next_question_ids must be the highest-priority pending prefix")
  end

  def test_asked_question_requires_exactly_one_answer
    document = session
    document["rounds"].first["answers"] = []

    assert_invalid(document, "asked question QUESTION-001 requires exactly one answer")
  end

  def test_answered_question_must_be_marked_asked_in_the_same_round
    document = session
    document["questions"].first["status"] = "pending"
    document["questions"].first.delete("round_number")

    assert_invalid(document, "answered question QUESTION-001 must be marked asked")
  end

  def test_more_than_three_rounds_require_explicit_user_extension
    document = session
    (2..4).each { |number| add_answer_round(document, number) }

    assert_invalid(document, "more than three rounds require user authorization")
  end

  def test_more_than_three_rounds_are_valid_with_explicit_user_extension
    document = session
    (2..4).each { |number| add_answer_round(document, number) }
    document["round_policy"]["extension_authorized_by_user"] = true
    document["round_policy"]["extension_reason"] = "用户确认第四轮会解决仍可能改变验收的证据问题。"

    assert_valid(document)
  end

  def test_authorized_round_extension_requires_a_reason
    document = session
    document["round_policy"]["extension_authorized_by_user"] = true

    assert_invalid(document, "authorized round extension requires extension_reason")
  end

  def test_ready_session_and_prompt_package_have_valid_lineage
    assert_pair_valid(session, prompt_package)
  end

  def test_lineage_rejects_raw_intent_drift
    package = prompt_package
    package.dig("intent", "raw_intent") << "被改写"

    assert_pair_invalid(session, package, "raw_intent must exactly match")
  end

  def test_lineage_rejects_task_type_drift
    package = prompt_package
    package["intent"]["task_type"] = "feature_definition"

    assert_pair_invalid(session, package, "task_type must match")
  end

  def test_lineage_rejects_changed_user_answer
    package = prompt_package
    package["clarifications"].first["user_answer"] = "所有管理员都可以。"

    assert_pair_invalid(session, package, "changed user_answer")
  end

  def test_lineage_rejects_invented_clarification
    package = prompt_package
    invented = deep_copy(package["clarifications"].first)
    invented["question_id"] = "QUESTION-999"
    package["clarifications"] << invented

    assert_pair_invalid(session, package, "Clarifications must exactly match")
  end

  def test_lineage_rejects_changed_assumption
    package = prompt_package
    package.dig("knowledge", "assumptions").first["statement"] = "改写后的假设"

    assert_pair_invalid(session, package, "assumptions ASSUMP-001 must preserve")
  end

  def test_lineage_rejects_changed_unknown
    package = prompt_package
    package.dig("knowledge", "unknowns").first["blocking"] = true
    package["handoff"]["ready"] = false

    assert_pair_invalid(session, package, "unknowns UNKNOWN-001 must preserve")
  end

  def test_lineage_rejects_changed_decision
    package = prompt_package
    package.dig("knowledge", "decisions").first["selected_option"] = "改用外部服务"

    assert_pair_invalid(session, package, "decisions DECISION-001 must preserve")
  end

  def test_lineage_requires_approval_point_for_every_identified_high_risk_action
    document = session
    document.dig("compile_gate", "high_risk_actions") << {
      "action" => "production_data_access",
      "description" => "读取真实生产数据",
      "approval_point_required" => true
    }

    assert_pair_invalid(document, prompt_package, "high-risk action production_data_access requires")
  end

  def test_lineage_rejects_package_that_predates_session
    package = prompt_package
    package["created_at"] = "2026-08-21T09:00:00+08:00"

    assert_pair_invalid(session, package, "cannot predate its Clarification Session")
  end

  def test_lineage_requires_ready_to_compile_session
    assert_pair_invalid(blocked_session, prompt_package, "requires a ready_to_compile Clarification Session")
  end

  def test_malformed_intake_is_rejected_without_crashing
    document = session
    document["intake"] = "invalid"

    assert_invalid(document, "expected object")
  end

  def test_cli_cross_checks_lineage_without_writing_inputs
    before_session = File.binread(SESSION_FIXTURE)
    before_package = File.binread(PACKAGE_FIXTURE)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/validate_clarification_session.rb"),
      SESSION_FIXTURE,
      "--prompt-package",
      PACKAGE_FIXTURE,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "PMIND_CLARIFICATION_SESSION_VALIDATION_PASS"
    assert_includes stdout, "lineage=true"
    assert_equal "", stderr
    assert_equal before_session, File.binread(SESSION_FIXTURE)
    assert_equal before_package, File.binread(PACKAGE_FIXTURE)
  end

  private

  def assert_valid(document)
    validator = PMind::ClarificationSessionValidator.new(ROOT)
    assert validator.validate(document), validator.errors.join("\n")
  end

  def assert_invalid(document, expected_error)
    validator = PMind::ClarificationSessionValidator.new(ROOT)
    refute validator.validate(document)
    assert validator.errors.any? { |error| error.include?(expected_error) }, validator.errors.join("\n")
  end

  def assert_pair_valid(session_document, package_document)
    validator = PMind::ClarificationSessionValidator.new(ROOT)
    assert validator.validate_pair(session_document, package_document), validator.errors.join("\n")
  end

  def assert_pair_invalid(session_document, package_document, expected_error)
    validator = PMind::ClarificationSessionValidator.new(ROOT)
    refute validator.validate_pair(session_document, package_document)
    assert validator.errors.any? { |error| error.include?(expected_error) }, validator.errors.join("\n")
  end

  def session
    load_yaml(SESSION_FIXTURE)
  end

  def prompt_package
    load_yaml(PACKAGE_FIXTURE)
  end

  def intake_session
    document = session
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

  def gap_scan_session
    document = session
    document["status"] = "gap_scan"
    document["rounds"] = []
    question = document["questions"].first
    question["status"] = "pending"
    question.delete("round_number")
    make_risk_gap_unknown(document)
    gate = document["compile_gate"]
    gate["ready"] = false
    gate["blocking_reasons"] = []
    gate["next_question_ids"] = ["QUESTION-001"]
    gate["stop_reason"] = "not_stopped"
    document
  end

  def clarifying_session
    document = session
    document["status"] = "clarifying"
    document["questions"] << pending_question("QUESTION-002", "evidence", 4)
    gate = document["compile_gate"]
    gate["ready"] = false
    gate["next_question_ids"] = ["QUESTION-002"]
    gate["stop_reason"] = "not_stopped"
    document
  end

  def blocked_session
    document = session
    document["status"] = "blocked"
    make_risk_gap_unknown(document)
    gate = document["compile_gate"]
    gate["ready"] = false
    gate["blocking_reasons"] = ["用户拒绝确认不可安全默认的导出权限。"]
    gate["next_question_ids"] = []
    gate["stop_reason"] = "blocked"
    document
  end

  def make_risk_gap_unknown(document)
    document["unknowns"] << {
      "unknown_id" => "UNKNOWN-002",
      "question" => "哪些角色被授权导出？",
      "blocking" => true
    }
    risk_gap = gap(document, "risk_authority")
    risk_gap["status"] = "unknown"
    risk_gap["blocking"] = true
    risk_gap["summary"] = "导出权限尚未获得用户确认。"
    risk_gap["source_refs"] = []
    risk_gap["knowledge_ref"] = "UNKNOWN-002"
  end

  def pending_question(question_id, dimension, score)
    {
      "question_id" => question_id,
      "gap_dimension" => dimension,
      "question" => "需要补充哪一项可验证事实？",
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

  def add_answer_round(document, number)
    question_id = format("QUESTION-%03d", number)
    question = pending_question(question_id, "evidence", 4)
    question["status"] = "asked"
    question["round_number"] = number
    document["questions"] << question
    document["rounds"] << {
      "round_number" => number,
      "completed_at" => format("2026-08-21T10:%02d:00+08:00", number + 5),
      "answers" => [{
        "question_id" => question_id,
        "user_answer" => "合成测试回答",
        "outcome_status" => "resolved",
        "normalized_conclusion" => "合成测试结论",
        "affected_fields" => ["knowledge.unknowns"]
      }]
    }
  end

  def gap(document, dimension)
    document["gaps"].find { |entry| entry["dimension"] == dimension }
  end

  def unknown(document, unknown_id)
    document["unknowns"].find { |entry| entry["unknown_id"] == unknown_id }
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
