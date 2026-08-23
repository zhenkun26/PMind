# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/render_calibration_role_briefing"

class RenderCalibrationRoleBriefingTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    @parent = Dir.mktmpdir("pmind-role-briefing")
    @workspace = File.join(@parent, "calibration-001")
    PMind::CalibrationWorkspacePreparer.new(ROOT).prepare(
      output: @workspace,
      prepared_at: "2026-08-23T12:00:00Z"
    )
  end

  def teardown
    FileUtils.remove_entry(@parent) if @parent && File.exist?(@parent)
  end

  def test_facilitator_receives_order_and_both_paths_but_no_role_refs
    copy = renderer.render(workspace_set: @workspace, role: "facilitator")

    assert_includes copy, "主持人 Briefing"
    assert_includes copy, "seed\-001 第 1 个 arm：基线组"
    assert_includes copy, "seed\-006 第 1 个 arm：PMind 组"
    assert_includes copy, safe_workspace_path("cases/seed-001/baseline")
    assert_includes copy, safe_workspace_path("cases/seed-001/pmind")
    assert_includes copy, "arm\-only 隔离尚未形成端到端证明"
    assert_includes copy, "不得仅凭工作目录、提示词或 `workspace\-write` 启动"
    refute_includes copy, "role-b605d9fa"
    refute_includes copy, "codex exec"
  end

  def test_operator_receives_sanitized_intake_and_only_pmind_paths
    copy = renderer.render(workspace_set: @workspace, role: "pmind_operator")

    assert_includes copy, "PMind 操作者 Briefing"
    assert_includes copy, "给后台用户列表加一个 CSV 导出按钮"
    assert_includes copy, safe_workspace_path("cases/seed-001/pmind")
    refute_includes copy, safe_workspace_path("cases/seed-001/baseline")
    refute_includes copy, "十万行"
    refute_includes copy, "user_export"
    refute_includes copy, "AC\-01"
    refute_includes copy, "role-b605d9fa"
    refute_includes copy, "role-878c0789"
  end

  def test_each_reviewer_receives_only_own_ref_and_no_arm_metadata
    reviewer_1 = renderer.render(workspace_set: @workspace, role: "reviewer_1")
    reviewer_2 = renderer.render(workspace_set: @workspace, role: "reviewer_2")

    assert_includes reviewer_1, "role\-c963a6b1\-57f1\-4556\-890f\-49f431b9a697"
    refute_includes reviewer_1, "role\-879f2684\-7141\-478b\-b2a8\-7a40beac8129"
    assert_includes reviewer_2, "role\-879f2684\-7141\-478b\-b2a8\-7a40beac8129"
    refute_includes reviewer_2, "role\-c963a6b1\-57f1\-4556\-890f\-49f431b9a697"
    [reviewer_1, reviewer_2].each do |copy|
      assert_includes copy, "去标签结果"
      assert_includes copy, "evals/fixtures/seed\-001/oracle"
      refute_includes copy, @workspace
      refute_includes copy, "基线组"
      refute_includes copy, "PMind 组"
      refute_includes copy, "给后台用户列表"
    end
  end

  def test_rendering_is_read_only_for_the_workspace_set
    preparer = PMind::CalibrationWorkspacePreparer.new(ROOT)

    PMind::CalibrationRoleBriefingRenderer::ROLES.each do |role|
      renderer.render(workspace_set: @workspace, role: role)
    end

    assert preparer.verify(@workspace)
  end

  def test_missing_workspace_and_unknown_role_fail_closed
    error = assert_raises(PMind::CalibrationRoleBriefingRenderer::BriefingError) do
      renderer.render(workspace_set: nil, role: "facilitator")
    end
    assert_includes error.message, "workspace set is required"

    error = assert_raises(PMind::CalibrationRoleBriefingRenderer::BriefingError) do
      renderer.render(workspace_set: @workspace, role: "executor")
    end
    assert_includes error.message, "role must be one of"
  end

  def test_invalid_workspace_fails_without_echoing_the_submitted_path
    submitted = "/private/invalid/pmind-calibration-role-briefing"

    error = assert_raises(PMind::CalibrationRoleBriefingRenderer::BriefingError) do
      renderer.render(workspace_set: submitted, role: "facilitator")
    end

    assert_includes error.message, "startup gates are not ready"
    refute_includes error.message, submitted
  end

  def test_started_wave_is_rejected_and_intake_markdown_is_escaped
    documents = case_documents
    documents.fetch("seed-001").fetch("intent")["raw_intent"] = "**unsafe** [label](https://example.com)"
    safe_renderer = PMind::CalibrationRoleBriefingRenderer.new(ROOT, case_documents: documents)
    copy = safe_renderer.render(workspace_set: @workspace, role: "pmind_operator")

    assert_includes copy, "\\*\\*unsafe\\*\\*"
    assert_includes copy, "\\[label\\](https://example.com)"
    refute_includes copy, "**unsafe**"
    refute_includes copy, "[label](https://example.com)"

    documents.fetch("seed-001")["run_records"] << { "run_id" => "already-started" }
    error = assert_raises(PMind::CalibrationRoleBriefingRenderer::BriefingError) do
      safe_renderer.render(workspace_set: @workspace, role: "facilitator")
    end
    assert_includes error.message, "only valid before the first Wave run record"
  end

  def test_cli_renders_one_role_without_writing_a_packet
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/render_calibration_role_briefing.rb"),
      "--workspace-set",
      @workspace,
      "--role",
      "pmind_operator",
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "PMind 操作者 Briefing"
    assert_equal "", stderr
    assert PMind::CalibrationWorkspacePreparer.new(ROOT).verify(@workspace)
  end

  def test_cli_rejects_unknown_role_without_echoing_workspace_path
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/render_calibration_role_briefing.rb"),
      "--workspace-set",
      @workspace,
      "--role",
      "executor",
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "PMIND_CALIBRATION_ROLE_BRIEFING_ERROR"
    assert_includes stderr, "Usage:"
    refute_includes stderr, @workspace
  end

  private

  def renderer
    PMind::CalibrationRoleBriefingRenderer.new(ROOT)
  end

  def safe_workspace_path(relative)
    PMind::MarkdownSafety.inline(File.join(File.realpath(@workspace), relative))
  end

  def case_documents
    validator = PMind::EvalValidator.new(ROOT)
    %w[seed-001 seed-006 seed-009].to_h do |case_id|
      path = Dir[File.join(ROOT, "evals/cases/seed/#{case_id}-*.yaml")].fetch(0)
      relative = path.delete_prefix("#{ROOT}/")
      [case_id, Marshal.load(Marshal.dump(validator.load_yaml(relative)))]
    end
  end
end
