#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "create_prompt_package"
require_relative "markdown_safety"

module PMind
  class PromptPackageLineageVerifier
    attr_reader :errors, :prompt_package, :expected_package

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @prompt_package = nil
      @expected_package = nil
    end

    def verify_files(session_path, draft_path, proposal_path, confirmation_path, package_path)
      errors.clear
      @prompt_package = load_yaml_file(package_path)
      @expected_package = nil
      return nil unless prompt_package

      builder = PromptPackageCreator.new(@root)
      @expected_package = builder.build_files(session_path, draft_path, proposal_path, confirmation_path)
      errors.concat(builder.errors)
      return nil unless expected_package

      package_validator = PromptPackageValidator.new(@root)
      unless package_validator.validate(prompt_package, package_path)
        errors.concat(package_validator.errors)
        return nil
      end

      lineage_validator = ClarificationSessionValidator.new(@root)
      unless lineage_validator.validate_pair(builder.source_session, prompt_package, "source-session-revision", package_path)
        errors.concat(lineage_validator.errors)
        return nil
      end

      validate_reconstruction(prompt_package, expected_package, package_path)
      return nil unless errors.empty?

      render_copy(prompt_package)
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
      metadata = document["compilation"]
      expected_metadata = expected.fetch("compilation")
      unless metadata.is_a?(Hash)
        errors << "#{path}: persisted Package is missing compilation lineage metadata"
        return
      end

      expected_metadata.each do |field, value|
        unless metadata[field] == value
          errors << "#{path}: compilation lineage #{field} does not match confirmed sources"
        end
      end

      document_content = document.reject { |field, _value| field == "compilation" }
      expected_content = expected.reject { |field, _value| field == "compilation" }
      unless document_content == expected_content
        errors << "#{path}: persisted Package content does not match deterministic reconstruction"
      end
    end

    def render_copy(document)
      lines = [
        "# Prompt Package 来源链已验证",
        "",
        "这份最终 Package 可以由已确认的来源工件确定性重建。",
        "",
        "## 验证结果",
        "",
        "- 四份来源文件绑定：匹配",
        "- 用户确认选择：已确认",
        "- Package 内容：与确定性重建一致",
        "- Package Quality Gate：可交接"
      ]
      append_approvals(lines, document.fetch("approval_points"))
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "可以进入受控 Handoff 决策；实际 Handoff 仍须遵守 Package 中的 Approval Points、禁止动作和停止条件。",
                     "",
                     "来源链验证本身不执行或授权 Handoff，也不批准任何仍待处理的高风险动作。"
                   ])
      lines.join("\n")
    end

    def append_approvals(lines, approvals)
      return if approvals.empty?

      lines.concat(["", "## 审批边界保持不变", ""])
      approvals.each do |approval|
        scope = MarkdownSafety.inline(approval.fetch("scope"))
        status = PromptPackageCreator::APPROVAL_COPY.fetch(approval.fetch("status"))
        lines << "- #{scope}：#{status}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 5
    warn "Usage: ruby scripts/verify_prompt_package_lineage.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  verifier = PMind::PromptPackageLineageVerifier.new(project_root)
  copy = verifier.verify_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn verifier.errors.join("\n")
  exit 1
end
