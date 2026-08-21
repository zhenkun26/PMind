#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "create_clarification_revision"
require_relative "markdown_safety"

module PMind
  class ClarificationRevisionLineageVerifier
    STATUS_COPY = {
      "clarifying" => "继续澄清",
      "ready_to_compile" => "具备 Prompt Package 编译条件",
      "blocked" => "保持阻塞，等待最小必要信息"
    }.freeze
    NEXT_STEP_COPY = {
      "clarifying" => "继续当前 Session 的下一轮 Clarification。",
      "ready_to_compile" => "可以进入 Prompt Package 编译准备；尚未生成 Prompt Package。",
      "blocked" => "保留阻塞原因，获得最小必要信息后再形成新的受控 revision。"
    }.freeze

    attr_reader :errors, :revision, :expected_revision

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @revision = nil
      @expected_revision = nil
    end

    def verify_files(session_path, receipt_path, proposal_path, confirmation_path, revision_path)
      errors.clear
      @revision = load_yaml_file(revision_path)
      @expected_revision = nil
      return nil unless revision

      builder = ClarificationRevisionCreator.new(@root)
      @expected_revision = builder.build_files(session_path, receipt_path, proposal_path, confirmation_path)
      errors.concat(builder.errors)
      return nil unless expected_revision

      validator = ClarificationSessionValidator.new(@root)
      unless validator.validate(revision, revision_path)
        errors.concat(validator.errors)
        return nil
      end

      validate_reconstruction(revision, expected_revision, revision_path)
      return nil unless errors.empty?

      render_copy(revision)
    end

    private

    def load_yaml_file(path)
      YAML.safe_load(
        File.binread(File.expand_path(path)),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      nil
    end

    def validate_reconstruction(document, expected, path)
      metadata = document["revision"]
      expected_metadata = expected.fetch("revision")
      unless metadata.is_a?(Hash)
        errors << "#{path}: persisted Session is missing revision lineage metadata"
        return
      end

      expected_metadata.each do |field, value|
        unless metadata[field] == value
          errors << "#{path}: revision lineage #{field} does not match confirmed sources"
        end
      end

      document_content = document.reject { |field, _value| field == "revision" }
      expected_content = expected.reject { |field, _value| field == "revision" }
      unless document_content == expected_content
        errors << "#{path}: persisted Session content does not match deterministic reconstruction"
      end
    end

    def render_copy(document)
      metadata = document.fetch("revision")
      lines = [
        "# Session revision 来源链已验证",
        "",
        "这份 revision 可以由已确认的来源工件确定性重建。",
        "",
        "## 验证结果",
        "",
        "- 来源文件绑定：匹配",
        "- 用户确认选择：已确认",
        "- Session 内容：与确定性重建一致",
        "- Revision #{metadata.fetch("revision_number")} 状态：#{STATUS_COPY.fetch(document.fetch("status"))}"
      ]
      append_high_risk_actions(lines, document.dig("compile_gate", "high_risk_actions"))
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     NEXT_STEP_COPY.fetch(document.fetch("status")),
                     "",
                     "来源链验证不授权任何高风险动作，也不代表 Prompt Package 或下游交付已经完成。"
                   ])
      lines.join("\n")
    end

    def append_high_risk_actions(lines, actions)
      return if actions.empty?

      lines.concat(["", "## 仍需单独审批", ""])
      actions.each do |action|
        lines << "- #{MarkdownSafety.inline(action.fetch("description"))}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 5
    warn "Usage: ruby scripts/verify_clarification_revision_lineage.rb SOURCE_SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml REVISION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  verifier = PMind::ClarificationRevisionLineageVerifier.new(project_root)
  copy = verifier.verify_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn verifier.errors.join("\n")
  exit 1
end
