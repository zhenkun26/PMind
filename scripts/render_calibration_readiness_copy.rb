#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "calibration_preflight"

module PMind
  class CalibrationReadinessCopyRenderer
    GATE_LABELS = {
      "contracts_valid" => "契约校验",
      "rubric_frozen" => "评分规则冻结",
      "roles_assigned" => "四角色分配",
      "fixtures_ready" => "校准 Fixture",
      "executor_frozen" => "Executor Profile 冻结",
      "isolated_workspaces_ready" => "隔离工作区"
    }.freeze

    def initialize(root, preflight: nil)
      @preflight = preflight || CalibrationPreflight.new(root)
    end

    def render(workspace_set: nil)
      result = @preflight.run(workspace_set: workspace_set)
      result.status == "ready" ? render_ready(result) : render_blocked(result)
    end

    private

    def render_blocked(result)
      passed = result.gates.values.count(true)
      lines = [
        "# 校准尚未就绪",
        "",
        "当前有 #{passed}/#{result.gates.length} 个启动门禁通过。保持 blocked 是正确结果；现在不能创建运行记录或把 Fixture 当作产品效果。",
        "",
        "## 已通过",
        ""
      ]
      passed_labels = result.gates.select { |_gate, value| value }.keys.map { |gate| GATE_LABELS.fetch(gate) }
      passed_labels.each { |label| lines << "- #{label}" }
      actions = missing_actions(result.gates)
      if actions.empty?
        actions << "根据已验证证据对齐 Wave 的 start_gates、status、can_start 和 blocked_reasons；不得为了通过 preflight 预先置绿。"
      end
      lines.concat(["", "## 请按顺序补齐", ""])
      actions.each_with_index { |action, index| lines << "#{index + 1}. #{action}" }
      lines.concat([
                     "",
                     "真实输入形成后，再同步 Wave manifest 与重新计算的 gate；不得在证据出现前改成 ready。",
                     "",
                     "## 停止条件",
                     "",
                     "只要任一门禁仍未通过，就不要启动校准、写入 run_records、安排盲评或报告 First-pass Delivery Success。补齐真实输入后重新运行 preflight。"
                   ])
      lines.join("\n")
    end

    def render_ready(result)
      [
        "# 校准启动门禁已通过",
        "",
        "全部 #{result.gates.length}/#{result.gates.length} 个门禁已有可验证证据。可以按冻结的 arm order 和 Runbook 进入三案例校准。",
        "",
        "## 启动前复核",
        "",
        "- 四个角色继续保持互异，评审不得读取另一位评审结果",
        "- 两个实验臂继续使用同一冻结 Executor Profile 和各自隔离工作区",
        "- 不读取 oracle，不改变 Rubric，不执行外部写入，不接触生产数据或秘密",
        "- 只有真实运行和双评审结果可以写入 run_records 与 Acceptance Result",
        "",
        "本状态只表示校准可以开始，不表示任何案例、产品效果或商业化目标已经通过。"
      ].join("\n")
    end

    def missing_actions(gates)
      actions = []
      unless gates.fetch("roles_assigned")
        actions << "分配 facilitator、PMind operator、reviewer 1、reviewer 2 四个互异的本地 opaque ID；不要在仓库中写姓名、邮箱或其他非必要个人信息。"
      end
      unless gates.fetch("executor_frozen")
        actions << "确定并冻结执行器版本、模型版本、推理设置、工具/网络策略、单臂时限和最多尝试次数；baseline 与 PMind 必须完全相同。"
      end
      unless gates.fetch("isolated_workspaces_ready")
        actions << "在 Profile 冻结后，于仓库外准备并验证六个 baseline/PMind 工作区副本；每个执行器只能访问自己的 arm，且不得包含 oracle。"
      end
      actions
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |config|
    config.banner = "Usage: ruby scripts/render_calibration_readiness_copy.rb [--workspace-set ABSOLUTE_PATH]"
    config.on("--workspace-set PATH", "Verify a prepared external workspace set") do |path|
      options[:workspace_set] = path
    end
  end

  begin
    parser.parse!
    project_root = File.expand_path("..", __dir__)
    renderer = PMind::CalibrationReadinessCopyRenderer.new(project_root)
    puts renderer.render(workspace_set: options[:workspace_set])
    exit 0
  rescue OptionParser::ParseError, PMind::CalibrationPreflight::PreflightError => e
    warn "PMIND_CALIBRATION_READINESS_COPY_ERROR #{e.message}"
    warn parser
    exit 1
  end
end
