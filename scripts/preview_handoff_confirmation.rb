#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_proposal"

module PMind
  class HandoffConfirmationPreview
    SCHEMA_PATH = "schemas/handoff-confirmation-receipt-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze

    attr_reader :errors, :prompt_package, :proposal, :confirmation, :input_digests

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @prompt_package = nil
      @proposal = nil
      @confirmation = nil
      @input_digests = nil
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path)
      errors.clear
      @prompt_package = nil
      @proposal = nil
      @confirmation = nil
      @input_digests = nil

      proposal_preview = HandoffProposalPreview.new(@root)
      proposal_copy = proposal_preview.preview_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path
      )
      errors.concat(proposal_preview.errors)
      return nil unless proposal_copy

      confirmation_document = load_yaml_file(handoff_confirmation_path)
      return nil unless confirmation_document

      @prompt_package = proposal_preview.prompt_package
      @proposal = proposal_preview.proposal
      @confirmation = confirmation_document
      @input_digests = proposal_preview.input_digests.dup
      return nil unless validate_confirmation_schema(confirmation_document, handoff_confirmation_path)

      validate_binding(confirmation_document, handoff_confirmation_path)
      validate_choice(confirmation_document, handoff_confirmation_path)
      validate_response_digest(confirmation_document, handoff_confirmation_path)
      validate_time(confirmation_document, handoff_confirmation_path)
      validate_data_policy(confirmation_document, handoff_confirmation_path)
      return nil unless errors.empty?

      render_copy(confirmation_document)
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

    def validate_confirmation_schema(document, path)
      validator = EvalValidator.new(@root)
      schema = validator.load_yaml(SCHEMA_PATH)
      unless schema
        errors.concat(validator.errors)
        return false
      end

      validator.validate_document(schema, document, path, schema)
      errors.concat(validator.errors)
      document.is_a?(Hash) && validator.errors.empty?
    end

    def validate_binding(document, path)
      expected = input_digests.merge(
        "package_id" => prompt_package["package_id"],
        "handoff_proposal_id" => proposal["handoff_proposal_id"],
        "package_handoff_ready" => prompt_package.dig("handoff", "ready"),
        "recipient" => prompt_package.dig("handoff", "recipient"),
        "handoff_proposal_status" => proposal.dig("confirmation", "status")
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its confirmed source" unless document[field] == value
      end
    end

    def validate_choice(document, path)
      expected_authorization = document["confirmation_decision"] == "confirmed"
      return if document["handoff_authorized"] == expected_authorization

      errors << "#{path}: handoff_authorized must be true only for confirmed"
    end

    def validate_response_digest(document, path)
      expected = Digest::SHA256.hexdigest(document["user_response"])
      return if document["user_response_sha256"] == expected

      errors << "#{path}: user response digest does not match"
    end

    def validate_time(document, path)
      proposal_time = parse_time(proposal["created_at"])
      confirmation_time = parse_time(document["captured_at"])
      return unless proposal_time && confirmation_time && confirmation_time < proposal_time

      errors << "#{path}: Handoff Confirmation Receipt cannot predate its Proposal"
    end

    def validate_data_policy(document, path)
      source_ranks = prompt_package.dig("execution_contract", "inputs").map do |input|
        CLASSIFICATION_RANK[input["data_classification"]]
      end.compact
      source_ranks << CLASSIFICATION_RANK[proposal["data_classification"]]
      confirmation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if confirmation_rank && source_ranks.compact.any? && confirmation_rank < source_ranks.compact.max
        errors << "#{path}: Handoff Confirmation Receipt data classification cannot downgrade its sources"
      end

      if document["contains_personal_data"] == true && document["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def render_copy(document)
      case document.fetch("confirmation_decision")
      when "confirmed"
        render_confirmed_copy
      when "modify_requested"
        [
          "# 已收到 Handoff 修改请求，当前授权未成立",
          "",
          "最终 Prompt Package 和现有 Proposal 均未修改，也尚未发生 Handoff。",
          "",
          "请从新的候选 Package 开始，重新完成编译确认、最终 Package 来源链验证和 Handoff Proposal。外部效果与高风险动作仍未获授权。"
        ].join("\n")
      when "rejected"
        [
          "# 已拒绝本次 Handoff，最终 Package 保持不变",
          "",
          "当前 Package 不会交给 Downstream Executor。已验证文件继续保留，但本次 Handoff 授权未成立。",
          "",
          "本次拒绝不会改变任何 Approval Point，也不会产生外部效果。"
        ].join("\n")
      end
    end

    def render_confirmed_copy
      handoff = prompt_package.fetch("handoff")
      lines = [
        "# 已收到 Handoff 确认，尚未交接",
        "",
        "已记录对当前精确 Handoff Proposal 的明确确认。最终 Prompt Package 尚未交给执行器。",
        "",
        "## 授权范围",
        "",
        "- 接收者：#{HandoffProposalPreview::RECIPIENT_COPY.fetch(handoff.fetch("recipient"))}",
        "- 对象：仅限当前已验证的精确 Prompt Package",
        "- Handoff：允许后续受控步骤继续"
      ]
      append_action_list(lines, "仍禁止的动作", handoff.fetch("prohibited_actions"))
      append_list(lines, "停止条件", handoff.fetch("stop_conditions"))
      append_approvals(lines, prompt_package.fetch("approval_points"))
      lines.concat([
                     "",
                     "## 仍未授权",
                     "",
                     "- 任何外部效果",
                     "- 任何仍待 Approval Point 的高风险动作",
                     "",
                     "## 下一步",
                     "",
                     "只有独立的受控 Handoff 步骤可以继续，并必须再次核对这份 Receipt 与完整来源链。若交接渠道需要网络、消息或外部系统写入，必须停止并获得单独授权。"
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

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 7
    warn "Usage: ruby scripts/preview_handoff_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffConfirmationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
