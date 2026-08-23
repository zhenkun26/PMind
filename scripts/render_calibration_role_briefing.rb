#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"
require_relative "calibration_preflight"
require_relative "markdown_safety"

module PMind
  class CalibrationRoleBriefingRenderer
    ROLES = %w[facilitator pmind_operator reviewer_1 reviewer_2].freeze
    WAVE_MANIFEST = "evals/calibration/wave-01.yaml"
    RUBRIC_PATH = "evals/rubrics/first-pass-success-v0.md"

    class BriefingError < StandardError; end

    def initialize(root, preflight: nil, case_documents: nil)
      @root = File.realpath(root)
      @preflight = preflight || CalibrationPreflight.new(@root)
      @case_documents = case_documents
    end

    def render(workspace_set:, role:)
      validate_role!(role)
      raise BriefingError, "verified workspace set is required" if workspace_set.nil?

      result = @preflight.run(workspace_set: workspace_set)
      unless result.status == "ready"
        raise BriefingError, "calibration startup gates are not ready"
      end

      validator = EvalValidator.new(@root)
      wave = validator.load_yaml(WAVE_MANIFEST)
      workspace = load_workspace_set(workspace_set)
      cases = load_cases(validator, wave)
      reject_started_wave!(cases)

      case role
      when "facilitator"
        render_facilitator(wave, workspace_set, workspace, cases)
      when "pmind_operator"
        render_operator(workspace_set, workspace, cases)
      else
        render_reviewer(wave, role, cases)
      end
    rescue CalibrationPreflight::PreflightError => e
      raise BriefingError, "calibration evidence is invalid: #{e.message.lines.first.to_s.strip}"
    end

    private

    def validate_role!(role)
      return if ROLES.include?(role)

      raise BriefingError, "role must be one of: #{ROLES.join(", ")}"
    end

    def load_workspace_set(path)
      absolute = File.realpath(path)
      YAML.safe_load(
        File.read(File.join(absolute, CalibrationWorkspacePreparer::MANIFEST_NAME)),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception
      raise BriefingError, "verified workspace set could not be read"
    end

    def load_cases(validator, wave)
      wave.fetch("cases").map do |entry|
        case_id = entry.fetch("case_id")
        if @case_documents
          document = @case_documents.fetch(case_id) do
            raise BriefingError, "#{case_id} must resolve to exactly one case definition"
          end
          next [entry, document]
        end

        matches = Dir[File.join(@root, "evals/cases/seed/#{case_id}-*.yaml")]
        unless matches.length == 1
          raise BriefingError, "#{case_id} must resolve to exactly one case definition"
        end

        relative = matches.first.delete_prefix("#{@root}/")
        [entry, validator.load_yaml(relative)]
      end
    end

    def reject_started_wave!(cases)
      return if cases.all? { |_entry, document| document.fetch("run_records").empty? }

      raise BriefingError, "role briefing v0 is only valid before the first Wave run record"
    end

    def render_facilitator(wave, workspace_root, workspace, cases)
      lines = common_header("主持人", "运行时 arm-only 隔离尚未形成端到端证明；不要启动计分臂。")
      lines.concat([
                     "",
                     "## 你的职责",
                     "",
                     "- 你可以保管 oracle，但只能回答某一流程实际提出的问题",
                     "- 不把 oracle、验收答案或一个实验臂的结果发送给另一个实验臂",
                     "- 每个 arm 使用全新上下文、同一冻结 Profile、30 分钟和一次计分尝试",
                     "- 两位评审必须独立收到去标签结果，不能看到对方判断",
                     "",
                     "## 冻结顺序与路径",
                     ""
                   ])
      cases.each do |entry, document|
        case_id = document.fetch("case_id")
        ordered_arms(entry.fetch("arm_order")).each_with_index do |arm, index|
          lines << "- #{safe(case_id)} 第 #{index + 1} 个 arm：#{arm_label(arm)} — #{safe(arm_path(workspace_root, workspace, case_id, arm))}"
        end
        lines << "- #{safe(case_id)} oracle：#{safe("evals/fixtures/#{case_id}/oracle")}"
      end
      lines.concat([
                     "",
                     "## 启动前最后阻断",
                     "",
                     "不得仅凭工作目录、提示词或 `workspace-write` 启动。实际启动路径必须先证明：当前 arm 可读写，PMind 仓库、oracle 和其他五个 arm 均不可读；本地测试可运行；Git、依赖安装、工具网络和外部写入均不可用。探测与计分运行必须使用同一权限配置。",
                     "",
                     "当前没有满足上述条件的已归档启动证据，因此本 Briefing 只用于角色协调。"
                   ])
      lines.join("\n")
    end

    def render_operator(workspace_root, workspace, cases)
      lines = common_header("PMind 操作者", "只准备 PMind Handoff；不要启动 Downstream Executor。")
      lines.concat([
                     "",
                     "## 你的边界",
                     "",
                     "- 只查看下列 Intake、主持人实际回答和当前 PMind 工作区",
                     "- 不查看 case 定义、oracle、Acceptance Criteria、基线工作区或任何运行结果",
                     "- 每轮提出 1–3 个最高信息增益问题；拒答时使用显式安全假设或停止",
                     "- 向主持人返回通过 Quality Gate 的 Prompt Package 和必要操作记录，不执行下游任务",
                     ""
                   ])
      cases.each do |_entry, document|
        case_id = document.fetch("case_id")
        intent = document.fetch("intent")
        policy = document.fetch("data_policy")
        lines.concat([
                       "## #{safe(case_id)}",
                       "",
                       "- PMind 工作区：#{safe(arm_path(workspace_root, workspace, case_id, "pmind"))}",
                       "- 用户画像：#{safe(intent.fetch("user_profile"))}",
                       "- 数据分类：#{safe(policy.fetch("classification"))}",
                       "- 原始 Intent：#{safe(intent.fetch("raw_intent"))}",
                       "- 已有上下文：#{safe_list(intent.fetch("context_available"))}",
                       "- 允许输入：#{safe_list(policy.fetch("allowed_inputs"))}",
                       "- 禁止动作：#{safe_list(policy.fetch("prohibited_actions"))}",
                       ""
                     ])
      end
      lines.concat([
                     "## 停止条件",
                     "",
                     "看到 oracle、另一实验臂、密钥、未授权数据或外部写入需求时立即停止并通知主持人；不要自行补齐或绕过。"
                   ])
      lines.join("\n")
    end

    def render_reviewer(wave, role, cases)
      own_ref = wave.dig("roles", role, "assignee_ref")
      lines = common_header(role == "reviewer_1" ? "评审 1" : "评审 2", "等待主持人提供去标签结果后再独立评分。")
      lines.concat([
                     "",
                     "## 你的评审身份",
                     "",
                     "- 本次 assignment-scoped ref：#{safe(own_ref)}",
                     "- Rubric：#{safe(RUBRIC_PATH)}",
                     "- 不查看实验臂标签、执行顺序、工作区路径或另一位评审的判断",
                     "- 在提交自己的完整判断前，不与另一位评审讨论",
                     "",
                     "## 案例材料边界",
                     ""
                   ])
      cases.each do |_entry, document|
        case_id = document.fetch("case_id")
        lines << "- #{safe(case_id)}：仅在收到对应去标签结果后使用 #{safe("evals/fixtures/#{case_id}/oracle")}"
      end
      lines.concat([
                     "",
                     "## 评分输出",
                     "",
                     "逐项记录运行有效性、Acceptance Criteria、Material Re-specification、Safety Violation、可用性、二元 First-pass Delivery Success、诊断分和主失败分类。证据不足时使用 ambiguous 或 invalid_run，不猜测。",
                     "",
                     "本 Briefing 不表示已经收到结果、完成评审或形成共识。"
                   ])
      lines.join("\n")
    end

    def common_header(role_label, boundary)
      [
        "# Calibration Wave 01 — #{role_label} Briefing",
        "",
        "当前启动门禁为 6/6，但仍有 0 条运行记录和 0 条 Acceptance Result。",
        "#{boundary}",
        "",
        "本渲染没有调用模型、写入 arm、创建 run record 或产生产品效果证据。"
      ]
    end

    def ordered_arms(order)
      order == "baseline_then_pmind" ? %w[baseline pmind] : %w[pmind baseline]
    end

    def arm_label(arm)
      arm == "baseline" ? "基线组" : "PMind 组"
    end

    def arm_path(workspace_root, workspace, case_id, arm)
      case_entry = workspace.fetch("cases").find { |entry| entry.fetch("case_id") == case_id }
      relative = case_entry.fetch("arms").fetch(arm).fetch("path")
      File.join(File.realpath(workspace_root), relative)
    end

    def safe_list(values)
      values.empty? ? "无" : values.map { |value| safe(value) }.join("；")
    end

    def safe(value)
      MarkdownSafety.inline(value)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |config|
    config.banner = "Usage: ruby scripts/render_calibration_role_briefing.rb --workspace-set ABSOLUTE_PATH --role ROLE"
    config.on("--workspace-set PATH", "Verify the exact prepared external workspace set") do |path|
      options[:workspace_set] = path
    end
    config.on("--role ROLE", PMind::CalibrationRoleBriefingRenderer::ROLES, "Render one least-privilege role briefing") do |role|
      options[:role] = role
    end
  end

  begin
    parser.parse!
    project_root = File.expand_path("..", __dir__)
    renderer = PMind::CalibrationRoleBriefingRenderer.new(project_root)
    puts renderer.render(workspace_set: options[:workspace_set], role: options[:role])
    exit 0
  rescue OptionParser::ParseError, PMind::CalibrationRoleBriefingRenderer::BriefingError => e
    warn "PMIND_CALIBRATION_ROLE_BRIEFING_ERROR #{e.message}"
    warn parser
    exit 1
  end
end
