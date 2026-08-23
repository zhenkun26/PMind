# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/render_calibration_readiness_copy"

class RenderCalibrationReadinessCopyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_current_blocked_wave_renders_three_safe_input_groups
    copy = renderer.render

    assert_includes copy, "校准尚未就绪"
    assert_includes copy, "3/6 个启动门禁通过"
    assert_includes copy, "保持 blocked 是正确结果"
    assert_equal 3, copy.scan(/^\d+\. /).length
    assert_includes copy, "四个互异的本地 opaque ID"
    assert_includes copy, "执行器版本、模型版本、推理设置"
    assert_includes copy, "仓库外准备并验证六个"
    assert_includes copy, "再同步 Wave manifest 与重新计算的 gate"
    assert_includes copy, "不要启动校准、写入 run_records"
    refute_includes copy, "facilitator, pmind_operator"
    refute_includes copy, File.join(ROOT, "evals")
  end

  def test_verified_workspace_set_removes_only_the_workspace_action
    Dir.mktmpdir("pmind-readiness-copy") do |parent|
      output = File.join(parent, "calibration-001")
      PMind::CalibrationWorkspacePreparer.new(ROOT).prepare(
        output: output,
        prepared_at: "2026-08-23T12:00:00Z"
      )

      copy = renderer.render(workspace_set: output)
      assert_includes copy, "4/6 个启动门禁通过"
      assert_equal 2, copy.scan(/^\d+\. /).length
      refute_includes copy, "仓库外准备并验证六个"
      refute_includes copy, output
    end
  end

  def test_invalid_workspace_is_actionable_without_leaking_submitted_path
    submitted = "/private/invalid/calibration-workspaces"
    copy = renderer.render(workspace_set: submitted)

    assert_includes copy, "3/6 个启动门禁通过"
    assert_includes copy, "仓库外准备并验证六个"
    refute_includes copy, submitted
    refute_includes copy, "workspace set is invalid"
  end

  def test_ready_result_renders_start_review_without_claiming_effect
    gates = PMind::CalibrationPreflight::Result.new(
      status: "ready",
      gates: PMind::CalibrationPreflight.new(ROOT).run.gates.transform_values { true },
      blockers: []
    )
    fake_preflight = Struct.new(:result) do
      def run(workspace_set: nil)
        result
      end
    end.new(gates)
    copy = PMind::CalibrationReadinessCopyRenderer.new(ROOT, preflight: fake_preflight).render

    assert_includes copy, "校准启动门禁已通过"
    assert_includes copy, "6/6 个门禁"
    assert_includes copy, "可以按冻结的 arm order"
    assert_includes copy, "不表示任何案例、产品效果或商业化目标已经通过"
    refute_includes copy, "请按顺序补齐"
  end

  def test_cli_renders_blocked_state_as_a_valid_product_result
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/render_calibration_readiness_copy.rb"),
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "校准尚未就绪"
    assert_includes stdout, "3/6 个启动门禁通过"
    assert_equal "", stderr
  end

  def test_cli_rejects_unknown_options
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/render_calibration_readiness_copy.rb"),
      "--unknown",
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "PMIND_CALIBRATION_READINESS_COPY_ERROR"
    assert_includes stderr, "Usage:"
  end

  private

  def renderer
    PMind::CalibrationReadinessCopyRenderer.new(ROOT)
  end
end
