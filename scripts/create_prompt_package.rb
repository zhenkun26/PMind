#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "markdown_safety"
require_relative "preview_prompt_package_compilation_confirmation"

module PMind
  class PromptPackageCreator
    APPROVAL_COPY = {
      "required" => "仍待单独审批",
      "approved" => "已按限定范围批准",
      "rejected" => "已拒绝",
      "not_applicable" => "不适用"
    }.freeze

    attr_reader :errors, :prompt_package

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @prompt_package = nil
    end

    def create_files(session_path, draft_path, proposal_path, confirmation_path, output_path)
      errors.clear
      @prompt_package = nil
      absolute_output = File.expand_path(output_path)
      if File.exist?(absolute_output)
        errors << "#{output_path}: output already exists; refusing to overwrite"
        return nil
      end

      return nil unless build_files(session_path, draft_path, proposal_path, confirmation_path)

      return nil unless write_exclusive(absolute_output, YAML.dump(prompt_package), output_path)

      render_copy(prompt_package)
    end

    def build_files(session_path, draft_path, proposal_path, confirmation_path)
      errors.clear
      @prompt_package = nil

      preview = PromptPackageCompilationConfirmationPreview.new(@root)
      confirmation_copy = preview.preview_files(session_path, draft_path, proposal_path, confirmation_path)
      errors.concat(preview.errors)
      return nil unless confirmation_copy

      confirmation = preview.confirmation
      unless confirmation["confirmation_decision"] == "confirmed" &&
             confirmation["draft_package_handoff_ready"] == true &&
             confirmation["package_creation_authorized"] == true
        errors << "#{confirmation_path}: confirmation decision does not authorize final Package creation"
        return nil
      end

      @prompt_package = build_package(preview.prompt_package, preview.session, preview.proposal, confirmation, preview.input_digests)
      return nil unless validate_generated_package(preview.session)

      prompt_package
    rescue Errno::ENOENT, Errno::EACCES => e
      errors << "#{e.message}: cannot read final Package input"
      nil
    end

    private

    def build_package(draft, session, proposal, confirmation, digests)
      document = deep_copy(draft)
      document["compilation"] = {
        "created_at" => confirmation.fetch("captured_at"),
        "source_session_id" => session.fetch("session_id"),
        "source_session_revision_number" => confirmation.fetch("source_session_revision_number"),
        "source_session_file_sha256" => digests.fetch("source_session_file_sha256"),
        "draft_package_file_sha256" => digests.fetch("draft_package_file_sha256"),
        "compilation_proposal_id" => proposal.fetch("compilation_proposal_id"),
        "compilation_proposal_file_sha256" => digests.fetch("compilation_proposal_file_sha256"),
        "compilation_confirmation_id" => confirmation.fetch("compilation_confirmation_id"),
        "compilation_confirmation_receipt_file_sha256" => digests.fetch("compilation_confirmation_receipt_file_sha256"),
        "confirmation_decision" => "confirmed",
        "handoff_authorization_inferred" => false,
        "high_risk_authorization_inferred" => false
      }
      document
    end

    def validate_generated_package(session)
      package_validator = PromptPackageValidator.new(@root)
      unless package_validator.validate(prompt_package, "generated-final-package")
        errors.concat(package_validator.errors)
        @prompt_package = nil
        return false
      end

      lineage_validator = ClarificationSessionValidator.new(@root)
      unless lineage_validator.validate_pair(session, prompt_package, "source-session-revision", "generated-final-package")
        errors.concat(lineage_validator.errors)
        @prompt_package = nil
        return false
      end

      true
    end

    def write_exclusive(absolute_output, content, display_path)
      created = false
      File.open(absolute_output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        created = true
        file.binmode
        file.write(content)
        file.flush
        file.fsync
      end
      true
    rescue Errno::EEXIST
      errors << "#{display_path}: output already exists; refusing to overwrite"
      false
    rescue SystemCallError, IOError => e
      cleanup_partial_output(absolute_output) if created
      errors << "#{display_path}: cannot create final Package (#{e.message})"
      false
    end

    def cleanup_partial_output(path)
      File.delete(path) if File.file?(path)
    rescue SystemCallError => e
      errors << "#{path}: incomplete output cleanup failed (#{e.message})"
    end

    def render_copy(document)
      lines = [
        "# 最终 Prompt Package 已创建",
        "",
        "已根据明确确认在新的本地路径创建最终 Package。候选源文件保持不变。",
        "",
        "## 当前结果",
        "",
        "- Package Quality Gate：可交接",
        "- 本次只完成本地创建，尚未 Handoff"
      ]
      append_approvals(lines, document.fetch("approval_points"))
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "在 Handoff 前须独立重放已持久化 Package 的 lineage；该 verifier 尚未实现。本次创建不授权 Handoff，也不批准任何仍待处理的高风险动作。"
                   ])
      lines.join("\n")
    end

    def append_approvals(lines, approvals)
      return if approvals.empty?

      lines.concat(["", "## 审批边界保持不变", ""])
      approvals.each do |approval|
        scope = MarkdownSafety.inline(approval.fetch("scope"))
        lines << "- #{scope}：#{APPROVAL_COPY.fetch(approval.fetch("status"))}"
      end
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 5
    warn "Usage: ruby scripts/create_prompt_package.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml OUTPUT.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  creator = PMind::PromptPackageCreator.new(project_root)
  copy = creator.create_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn creator.errors.join("\n")
  exit 1
end
