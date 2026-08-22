#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require_relative "create_handoff_envelope"
require_relative "markdown_safety"

module PMind
  class HandoffEnvelopeLineageVerifier
    attr_reader :errors, :envelope, :expected_envelope, :envelope_bytes

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @envelope = nil
      @expected_envelope = nil
      @envelope_bytes = nil
    end

    def verify_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path)
      errors.clear
      @envelope, @envelope_bytes = load_yaml_file_with_bytes(envelope_path)
      @expected_envelope = nil
      return nil unless envelope

      builder = HandoffEnvelopeCreator.new(@root)
      @expected_envelope = builder.build_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path
      )
      errors.concat(builder.errors)
      return nil unless expected_envelope

      return nil unless validate_persisted_envelope(envelope, envelope_path)

      validate_reconstruction(envelope, expected_envelope, envelope_path)
      return nil unless errors.empty?

      render_copy(envelope)
    end

    private

    def load_yaml_file_with_bytes(path)
      bytes = File.binread(File.expand_path(path))
      document = YAML.safe_load(
        bytes,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
      [document, bytes]
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      [nil, nil]
    end

    def validate_persisted_envelope(document, path)
      schema_validator = EvalValidator.new(@root)
      schema = schema_validator.load_yaml(HandoffEnvelopeCreator::SCHEMA_PATH)
      unless schema
        errors.concat(schema_validator.errors)
        return false
      end

      schema_validator.validate_document(schema, document, path, schema)
      errors.concat(schema_validator.errors)
      return false unless document.is_a?(Hash)

      prompt_package = document["prompt_package"]
      package_validator = PromptPackageValidator.new(@root)
      unless package_validator.validate(prompt_package, "#{path}.prompt_package")
        errors.concat(package_validator.errors)
      end
      package_fields = prompt_package.is_a?(Hash) ? prompt_package : {}
      handoff_fields = package_fields["handoff"].is_a?(Hash) ? package_fields["handoff"] : {}
      if document["package_id"] != package_fields["package_id"]
        errors << "#{path}: package_id must match embedded Prompt Package"
      end
      if document["recipient"] != handoff_fields["recipient"]
        errors << "#{path}: recipient must match embedded Prompt Package"
      end

      errors.empty?
    end

    def validate_reconstruction(document, expected, path)
      expected.each do |field, value|
        next if %w[authorization prompt_package].include?(field)

        unless document[field] == value
          errors << "#{path}: Envelope metadata #{field} does not match confirmed sources"
        end
      end

      validate_authorization(document["authorization"], expected.fetch("authorization"), path)
      unless document["prompt_package"] == expected["prompt_package"]
        errors << "#{path}: embedded Prompt Package does not match deterministic reconstruction"
      end
    end

    def validate_authorization(document, expected, path)
      unless document.is_a?(Hash)
        errors << "#{path}: persisted Envelope is missing authorization lineage metadata"
        return
      end

      expected.each do |field, value|
        unless document[field] == value
          errors << "#{path}: authorization lineage #{field} does not match confirmed sources"
        end
      end
    end

    def render_copy(document)
      prompt_package = document.fetch("prompt_package")
      lines = [
        "# Handoff Envelope 来源链已验证，仍未交接",
        "",
        "这份本地 Envelope 可以由七份已确认来源确定性重建。验证过程未修改任何文件。",
        "",
        "## 验证结果",
        "",
        "- 七份来源文件绑定：匹配",
        "- 用户 Handoff 选择：已确认",
        "- Envelope metadata：与确定性重建一致",
        "- 内嵌 Prompt Package：与确定性重建一致",
        "- 交付状态：已准备，未交付"
      ]
      append_action_list(lines, "仍禁止的动作", prompt_package.dig("handoff", "prohibited_actions"))
      append_list(lines, "停止条件", prompt_package.dig("handoff", "stop_conditions"))
      append_approvals(lines, prompt_package.fetch("approval_points"))
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "可以创建 provider-neutral Adapter Capability Profile 与 pending Selection Proposal，并用十文件只读预演器检查；本次验证未选择或调用任何适配器，也未启动 Downstream Executor。",
                     "",
                     "任何真实交付、网络、消息、进程、外部写入或其他渠道副作用仍须单独设计、验证并获得相应授权。"
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
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 8
    warn "Usage: ruby scripts/verify_handoff_envelope_lineage.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  verifier = PMind::HandoffEnvelopeLineageVerifier.new(project_root)
  copy = verifier.verify_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn verifier.errors.join("\n")
  exit 1
end
