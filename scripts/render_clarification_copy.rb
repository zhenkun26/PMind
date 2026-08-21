#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "markdown_safety"
require_relative "validate_clarification_session"

module PMind
  class ClarificationCopyRenderer
    attr_reader :errors

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
    end

    def render_file(path)
      errors.clear
      document = load_yaml_file(path)
      return nil unless document

      render(document, path)
    end

    def render(document, path = "clarification-session")
      errors.clear
      validator = ClarificationSessionValidator.new(@root)
      unless validator.validate(document, path)
        errors.concat(validator.errors)
        return nil
      end

      lines = case document["status"]
              when "intake" then render_intake(document)
              when "gap_scan" then render_questions(document, first_round: true)
              when "clarifying" then render_questions(document, first_round: false)
              when "ready_to_compile" then render_ready(document)
              when "blocked" then render_blocked(document)
              else
                errors << "#{path}: unsupported Clarification Session status"
                return nil
              end
      lines.join("\n")
    end

    private

    def load_yaml_file(path)
      YAML.safe_load(
        File.read(File.expand_path(path)),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      nil
    end

    def render_intake(document)
      lines = [
        "# 需求已记录",
        "",
        "PMind 已逐字保留你的原始需求。下一步会识别可能影响范围、风险和验收的信息缺口。"
      ]
      append_privacy_notice(lines, document)
      lines
    end

    def render_questions(document, first_round:)
      lines = [
        first_round ? "# 继续前需要确认" : "# 还需要确认少量信息",
        ""
      ]
      if first_round
        lines << "为了让后续交付不依赖猜测，请先确认以下信息。"
      else
        lines << "已完成 #{document.fetch("rounds").length} 轮澄清。基于已有回答，还需要确认以下信息。"
      end
      append_privacy_notice(lines, document)
      lines.concat(["", "## 本轮问题", ""])

      questions = document.fetch("questions").each_with_object({}) do |question, index|
        index[question.fetch("question_id")] = question
      end
      document.dig("compile_gate", "next_question_ids").each_with_index do |question_id, index|
        question = questions.fetch(question_id)
        lines << "#{index + 1}. #{safe_text(question.fetch("question"))}"
        lines << ""
        lines << "   为什么需要：#{safe_text(question.fetch("why_now"))}"
        lines << ""
        lines << "   若暂时跳过：#{safe_text(question.fetch("safe_default_or_stop"))}"
        lines << "" unless index == document.dig("compile_gate", "next_question_ids").length - 1
      end
      lines.concat([
                     "",
                     "请按顺序简短回答；你也可以明确说“跳过”或“不知道”。"
                   ])
      lines
    end

    def render_ready(document)
      lines = [
        "# 已具备编译条件",
        "",
        "关键信息已足够，可以开始编译 Prompt Package；这不表示 Package 或下游交付已经完成。"
      ]
      append_privacy_notice(lines, document)
      append_assumptions(lines, document.fetch("assumptions"))
      append_unknowns(lines, document.fetch("unknowns"))
      append_high_risk_actions(lines, document.dig("compile_gate", "high_risk_actions"))
      lines
    end

    def render_blocked(document)
      lines = [
        "# 当前无法安全继续",
        "",
        "在以下问题解决前，PMind 不会生成可执行 Handoff。"
      ]
      append_privacy_notice(lines, document)
      append_list(lines, "## 阻塞原因", document.dig("compile_gate", "blocking_reasons"))
      append_list(lines, "## 需要解决的冲突", document.dig("compile_gate", "material_conflicts"))
      lines.concat([
                     "",
                     "请只补充解除上述阻塞所需的最少信息；无法安全确认时可以保持暂停。"
                   ])
      lines
    end

    def append_privacy_notice(lines, document)
      intake = document.fetch("intake")
      sensitive = intake["contains_personal_data"] == true ||
                  %w[confidential restricted].include?(intake["data_classification"])
      return unless sensitive

      lines.concat([
                     "",
                     "> 隐私提示：请只提供本轮所需的最少信息，并先对敏感内容脱敏；不要发送密钥或 token。"
                   ])
    end

    def append_assumptions(lines, assumptions)
      return if assumptions.empty?

      lines.concat(["", "## 当前采用的假设", ""])
      assumptions.each do |assumption|
        lines << "- #{safe_text(assumption.fetch("statement"))}（如果不成立：#{safe_text(assumption.fetch("invalidation_impact"))}）"
      end
    end

    def append_unknowns(lines, unknowns)
      return if unknowns.empty?

      lines.concat(["", "## 仍需留意的未知项", ""])
      unknowns.each do |unknown|
        lines << "- #{safe_text(unknown.fetch("question"))}"
      end
    end

    def append_high_risk_actions(lines, actions)
      return if actions.empty?

      lines.concat(["", "## 后续需要单独授权", ""])
      actions.each do |action|
        lines << "- #{safe_text(action.fetch("description"))}（仍需单独授权）"
      end
    end

    def append_list(lines, heading, values)
      return if values.empty?

      lines.concat(["", heading, ""])
      values.each { |value| lines << "- #{safe_text(value)}" }
    end

    def safe_text(value)
      MarkdownSafety.inline(value)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 1
    warn "Usage: ruby scripts/render_clarification_copy.rb SESSION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  renderer = PMind::ClarificationCopyRenderer.new(project_root)
  copy = renderer.render_file(ARGV.fetch(0))
  if copy
    puts copy
    exit 0
  end

  warn renderer.errors.join("\n")
  exit 1
end
