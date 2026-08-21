#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "markdown_safety"
require_relative "preview_clarification_confirmation"

module PMind
  class ClarificationRevisionCreator
    STATUS_COPY = {
      "clarifying" => "继续澄清",
      "ready_to_compile" => "具备 Prompt Package 编译条件",
      "blocked" => "保持阻塞，等待最小必要信息"
    }.freeze

    attr_reader :errors, :revision

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @revision = nil
    end

    def create_files(session_path, receipt_path, proposal_path, confirmation_path, output_path)
      errors.clear
      @revision = nil
      absolute_output = File.expand_path(output_path)
      if File.exist?(absolute_output)
        errors << "#{output_path}: output already exists; refusing to overwrite"
        return nil
      end

      return nil unless build_files(session_path, receipt_path, proposal_path, confirmation_path)

      content = YAML.dump(revision)
      return nil unless write_exclusive(absolute_output, content, output_path)

      render_copy(revision)
    end

    def build_files(session_path, receipt_path, proposal_path, confirmation_path)
      errors.clear
      @revision = nil

      preview = ClarificationConfirmationPreview.new(@root)
      confirmation_copy = preview.preview_files(session_path, receipt_path, proposal_path, confirmation_path)
      errors.concat(preview.errors)
      return nil unless confirmation_copy

      confirmation = preview.confirmation
      unless confirmation["confirmation_decision"] == "confirmed" && confirmation["revision_creation_authorized"] == true
        errors << "#{confirmation_path}: confirmation decision does not authorize revision creation"
        return nil
      end

      @revision = build_revision(
        preview.candidate_session,
        confirmation,
        preview.input_digests,
        preview.input_digests.fetch("confirmation_receipt_file_sha256")
      )
      validator = ClarificationSessionValidator.new(@root)
      unless validator.validate(revision, "generated-revision")
        errors.concat(validator.errors)
        @revision = nil
        return nil
      end

      revision
    rescue Errno::ENOENT, Errno::EACCES => e
      errors << "#{e.message}: cannot read revision input"
      nil
    end

    private

    def build_revision(candidate, confirmation, digests, confirmation_digest)
      document = deep_copy(candidate)
      document["revision"] = {
        "revision_number" => confirmation.fetch("target_revision_number"),
        "created_at" => confirmation.fetch("captured_at"),
        "source_session_file_sha256" => digests.fetch("source_session_file_sha256"),
        "answer_receipt_id" => confirmation.fetch("answer_receipt_id"),
        "answer_receipt_file_sha256" => digests.fetch("answer_receipt_file_sha256"),
        "proposal_id" => confirmation.fetch("proposal_id"),
        "proposal_file_sha256" => digests.fetch("proposal_file_sha256"),
        "confirmation_id" => confirmation.fetch("confirmation_id"),
        "confirmation_receipt_file_sha256" => confirmation_digest,
        "confirmation_decision" => "confirmed",
        "high_risk_authorization_inferred" => false
      }
      document
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
      errors << "#{display_path}: cannot create revision (#{e.message})"
      false
    end

    def cleanup_partial_output(path)
      File.delete(path) if File.file?(path)
    rescue SystemCallError => e
      errors << "#{path}: incomplete output cleanup failed (#{e.message})"
    end

    def render_copy(document)
      revision_metadata = document.fetch("revision")
      lines = [
        "# Session revision 已创建",
        "",
        "已根据明确确认创建 Revision #{revision_metadata.fetch("revision_number")}。原 Session 未修改。",
        "",
        "## 当前状态",
        "",
        "- #{STATUS_COPY.fetch(document.fetch("status"))}"
      ]
      append_unknowns(lines, document.fetch("unknowns"))
      append_high_risk_actions(lines, document.dig("compile_gate", "high_risk_actions"))
      lines.concat([
                     "",
                     "后续步骤必须继续使用新的 revision 文件；本次创建不授权任何高风险动作。"
                   ])
      lines.join("\n")
    end

    def append_unknowns(lines, unknowns)
      return if unknowns.empty?

      lines.concat(["", "## 仍需留意的未知项", ""])
      unknowns.each do |unknown|
        suffix = unknown["blocking"] == true ? "（阻塞）" : "（不阻塞）"
        lines << "- #{MarkdownSafety.inline(unknown.fetch("question"))}#{suffix}"
      end
    end

    def append_high_risk_actions(lines, actions)
      return if actions.empty?

      lines.concat(["", "## 仍需单独审批", ""])
      actions.each do |action|
        lines << "- #{MarkdownSafety.inline(action.fetch("description"))}"
      end
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 5
    warn "Usage: ruby scripts/create_clarification_revision.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml OUTPUT.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  creator = PMind::ClarificationRevisionCreator.new(project_root)
  copy = creator.create_files(ARGV.fetch(0), ARGV.fetch(1), ARGV.fetch(2), ARGV.fetch(3), ARGV.fetch(4))
  if copy
    puts copy
    exit 0
  end

  warn creator.errors.join("\n")
  exit 1
end
