#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_confirmation"

module PMind
  class HandoffEnvelopeCreator
    SCHEMA_PATH = "schemas/handoff-envelope-v0.yaml"

    attr_reader :errors, :envelope

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @envelope = nil
    end

    def create_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, output_path)
      errors.clear
      @envelope = nil
      absolute_output = File.expand_path(output_path)
      if File.exist?(absolute_output)
        errors << "#{output_path}: output already exists; refusing to overwrite"
        return nil
      end

      return nil unless build_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path
      )
      return nil unless write_exclusive(absolute_output, YAML.dump(envelope), output_path)

      render_copy(envelope)
    end

    def build_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path)
      errors.clear
      @envelope = nil

      preview = HandoffConfirmationPreview.new(@root)
      confirmation_copy = preview.preview_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path
      )
      errors.concat(preview.errors)
      return nil unless confirmation_copy

      confirmation = preview.confirmation
      unless confirmation["confirmation_decision"] == "confirmed" && confirmation["handoff_authorized"] == true
        errors << "#{handoff_confirmation_path}: confirmation decision does not authorize Handoff Envelope creation"
        return nil
      end

      @envelope = build_envelope(
        preview.prompt_package,
        confirmation,
        preview.input_digests,
        preview.confirmation_file_sha256
      )
      return nil unless validate_generated_envelope

      envelope
    rescue Errno::ENOENT, Errno::EACCES => e
      errors << "#{e.message}: cannot read Handoff Envelope input"
      nil
    end

    private

    def build_envelope(prompt_package, confirmation, digests, confirmation_digest)
      {
        "schema_version" => "0.1.0",
        "envelope_id" => confirmation.fetch("handoff_confirmation_id").sub("handoff-confirmation-", "handoff-envelope-"),
        "created_at" => confirmation.fetch("captured_at"),
        "language" => confirmation.fetch("language"),
        "package_id" => prompt_package.fetch("package_id"),
        "recipient" => prompt_package.dig("handoff", "recipient"),
        "delivery_state" => "prepared",
        "handoff_authorized" => true,
        "external_effects_authorized" => false,
        "high_risk_authorization_inferred" => false,
        "data_classification" => confirmation.fetch("data_classification"),
        "authorization" => {
          "handoff_proposal_id" => confirmation.fetch("handoff_proposal_id"),
          "handoff_confirmation_id" => confirmation.fetch("handoff_confirmation_id"),
          "handoff_confirmation_receipt_file_sha256" => confirmation_digest,
          "source_session_file_sha256" => digests.fetch("source_session_file_sha256"),
          "draft_package_file_sha256" => digests.fetch("draft_package_file_sha256"),
          "compilation_proposal_file_sha256" => digests.fetch("compilation_proposal_file_sha256"),
          "compilation_confirmation_receipt_file_sha256" => digests.fetch("compilation_confirmation_receipt_file_sha256"),
          "final_package_file_sha256" => digests.fetch("final_package_file_sha256"),
          "handoff_proposal_file_sha256" => digests.fetch("handoff_proposal_file_sha256"),
          "confirmation_decision" => "confirmed",
          "handoff_authorized" => true,
          "external_effects_authorized" => false,
          "high_risk_authorization_inferred" => false,
          "confirmation_contains_personal_data" => confirmation.fetch("contains_personal_data"),
          "confirmation_contains_secrets" => confirmation.fetch("contains_secrets")
        },
        "prompt_package" => deep_copy(prompt_package)
      }
    end

    def validate_generated_envelope
      schema_validator = EvalValidator.new(@root)
      schema = schema_validator.load_yaml(SCHEMA_PATH)
      unless schema
        errors.concat(schema_validator.errors)
        @envelope = nil
        return false
      end

      schema_validator.validate_document(schema, envelope, "generated-handoff-envelope", schema)
      errors.concat(schema_validator.errors)

      package_validator = PromptPackageValidator.new(@root)
      unless package_validator.validate(envelope["prompt_package"], "generated-handoff-envelope.prompt_package")
        errors.concat(package_validator.errors)
      end
      if envelope["package_id"] != envelope.dig("prompt_package", "package_id")
        errors << "generated-handoff-envelope: package_id must match embedded Prompt Package"
      end
      if envelope["recipient"] != envelope.dig("prompt_package", "handoff", "recipient")
        errors << "generated-handoff-envelope: recipient must match embedded Prompt Package"
      end

      if errors.empty?
        true
      else
        @envelope = nil
        false
      end
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
      errors << "#{display_path}: cannot create Handoff Envelope (#{e.message})"
      false
    end

    def cleanup_partial_output(path)
      File.delete(path) if File.file?(path)
    rescue SystemCallError => e
      errors << "#{path}: incomplete output cleanup failed (#{e.message})"
    end

    def render_copy(document)
      prompt_package = document.fetch("prompt_package")
      lines = [
        "# Handoff Envelope 已创建，尚未交接",
        "",
        "已在新的本地路径封装当前精确 Prompt Package 与确认授权链。所有来源文件保持不变。",
        "",
        "## 当前状态",
        "",
        "- Envelope：已准备，未交付",
        "- 接收者：#{HandoffProposalPreview::RECIPIENT_COPY.fetch(document.fetch("recipient"))}",
        "- 内容：当前精确 Prompt Package 与七文件授权 lineage"
      ]
      append_action_list(lines, "仍禁止的动作", prompt_package.dig("handoff", "prohibited_actions"))
      append_list(lines, "停止条件", prompt_package.dig("handoff", "stop_conditions"))
      append_approvals(lines, prompt_package.fetch("approval_points"))
      lines.concat([
                     "",
                     "## 仍未发生",
                     "",
                     "- 未启动 Downstream Executor",
                     "- 未调用模型、网络、进程、通知或外部服务",
                     "- 未批准任何仍待 Approval Point 的动作",
                     "",
                     "## 下一步",
                     "",
                     "必须先独立重放 Envelope 的完整来源链。验证通过也只证明本地 Envelope 可供后续受控适配器使用；任何真实交付或外部效果仍需与所选渠道相匹配的单独授权。"
                   ])
      lines.join("\n")
    end

    def append_action_list(lines, title, actions)
      readable = actions.map do |action|
        HandoffProposalPreview::ACTION_COPY.fetch(action, action.tr("_", " "))
      end
      append_list(lines, title, readable)
    end

    def append_list(lines, title, values)
      lines.concat(["", "## #{title}", ""])
      values.each { |value| lines << "- #{MarkdownSafety.inline(value)}" }
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

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 8
    warn "Usage: ruby scripts/create_handoff_envelope.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml OUTPUT.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  creator = PMind::HandoffEnvelopeCreator.new(project_root)
  copy = creator.create_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn creator.errors.join("\n")
  exit 1
end
