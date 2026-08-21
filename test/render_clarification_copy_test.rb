# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"
require_relative "../scripts/render_clarification_copy"

class RenderClarificationCopyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-ready.yaml")

  def test_intake_state_explains_the_next_step_without_repeating_raw_intent
    copy = assert_render(intake_session)

    assert_includes copy, "# 需求已记录"
    assert_includes copy, "下一步会识别"
    refute_includes copy, session.dig("intake", "raw_intent")
  end

  def test_gap_scan_state_renders_only_the_selected_first_round_questions
    document = gap_scan_session
    document["questions"] << pending_question("QUESTION-002", "evidence", 4, "不要展示的第二个问题")
    copy = assert_render(document)

    assert_includes copy, "# 继续前需要确认"
    assert_includes copy, "哪些角色可以导出？"
    assert_includes copy, "为什么需要：权限边界会改变实现和安全验收。"
    assert_includes copy, "若暂时跳过：未回答时停止生成可执行 Handoff。"
    refute_includes copy, "不要展示的第二个问题"
  end

  def test_clarifying_state_reports_completed_rounds_and_next_question
    copy = assert_render(clarifying_session)

    assert_includes copy, "# 还需要确认少量信息"
    assert_includes copy, "已完成 1 轮澄清"
    assert_includes copy, "需要补充哪一项可验证事实？"
  end

  def test_ready_state_discloses_assumptions_unknowns_and_approval_boundaries
    copy = assert_render(session)

    assert_includes copy, "# 已具备编译条件"
    assert_includes copy, "这不表示 Package 或下游交付已经完成"
    assert_includes copy, "首版数据量可由同步流式响应处理。"
    assert_includes copy, "最终按钮文案是否需要本地化？"
    assert_includes copy, "任何仓库外服务修改（仍需单独授权）"
  end

  def test_blocked_state_preserves_blockers_and_conflicts_without_handoff_claim
    document = blocked_session
    document["compile_gate"]["material_conflicts"] = ["目标与数据最小化要求冲突。"]
    copy = assert_render(document)

    assert_includes copy, "# 当前无法安全继续"
    assert_includes copy, "用户拒绝确认不可安全默认的导出权限。"
    assert_includes copy, "目标与数据最小化要求冲突。"
    assert_includes copy, "不会生成可执行 Handoff"
  end

  def test_invalid_state_is_rejected_without_partial_copy
    document = session
    document["compile_gate"]["ready"] = false
    renderer = renderer()

    assert_nil renderer.render(document)
    assert renderer.errors.any? { |error| error.include?("ready_to_compile state") }, renderer.errors.join("\n")
  end

  def test_ready_copy_rejects_an_orphaned_blocking_unknown
    document = session
    document["unknowns"].first["blocking"] = true
    renderer = renderer()

    assert_nil renderer.render(document)
    assert renderer.errors.any? { |error| error.include?("blocking unknown remains") }, renderer.errors.join("\n")
  end

  def test_sensitive_session_adds_data_minimization_notice
    document = session
    document["intake"]["contains_personal_data"] = true
    document["intake"]["data_classification"] = "confidential"
    copy = assert_render(document)

    assert_includes copy, "请只提供本轮所需的最少信息"
    assert_includes copy, "不要发送密钥或 token"
  end

  def test_dynamic_markdown_and_html_are_rendered_as_plain_single_line_text
    document = gap_scan_session
    document["questions"].first["question"] = "<script>alert(1)</script>\n# 标题 *强调* [链接](https://invalid.test)"
    copy = assert_render(document)

    assert_includes copy, "&lt;script&gt;alert(1)&lt;/script&gt; \\# 标题 \\*强调\\* \\[链接\\](https://invalid.test)"
    refute_includes copy, "<script>"
    refute_includes copy, "\n# 标题"
  end

  def test_internal_fields_and_saved_answers_are_not_rendered
    document = session
    copy = assert_render(document)

    forbidden = [
      document.dig("intake", "raw_intent"),
      document.dig("rounds", 0, "answers", 0, "user_answer"),
      document.dig("decisions", 0, "decision_maker_ref"),
      "QUESTION-001",
      "risk_authority",
      "raw_intent_sha256",
      "priority"
    ]
    forbidden.each { |value| refute_includes copy, value }
  end

  def test_missing_file_is_reported_without_copy
    renderer = renderer()

    assert_nil renderer.render_file(File.join(ROOT, "test/fixtures/missing-session.yaml"))
    assert renderer.errors.any? { |error| error.include?("cannot load YAML") }
  end

  def test_cli_writes_only_copy_to_stdout_and_does_not_modify_session
    before = File.binread(SESSION_FIXTURE)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/render_clarification_copy.rb"),
      SESSION_FIXTURE,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "# 已具备编译条件"
    assert_equal "", stderr
    assert_equal before, File.binread(SESSION_FIXTURE)
  end

  def test_cli_requires_exactly_one_session_path
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/render_clarification_copy.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_equal "", stdout
    assert_includes stderr, "Usage:"
  end

  private

  def assert_render(document)
    renderer = renderer()
    copy = renderer.render(document)
    assert copy, renderer.errors.join("\n")
    copy
  end

  def renderer
    PMind::ClarificationCopyRenderer.new(ROOT)
  end

  def session
    YAML.safe_load(
      File.read(SESSION_FIXTURE),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
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
    document["questions"] << pending_question("QUESTION-002", "evidence", 4, "需要补充哪一项可验证事实？")
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
    risk_gap = document["gaps"].find { |gap| gap["dimension"] == "risk_authority" }
    risk_gap["status"] = "unknown"
    risk_gap["blocking"] = true
    risk_gap["summary"] = "导出权限尚未获得用户确认。"
    risk_gap["source_refs"] = []
    risk_gap["knowledge_ref"] = "UNKNOWN-002"
  end

  def pending_question(question_id, dimension, score, question)
    {
      "question_id" => question_id,
      "gap_dimension" => dimension,
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
end
