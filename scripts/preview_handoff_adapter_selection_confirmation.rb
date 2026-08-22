#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_selection"

module PMind
  class HandoffAdapterSelectionConfirmationPreview
    SCHEMA_PATH = "schemas/handoff-adapter-selection-confirmation-receipt-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze

    attr_reader :errors, :envelope, :profile, :proposal, :confirmation,
                :input_digests, :confirmation_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path, profile_path, selection_proposal_path, selection_confirmation_path)
      errors.clear
      reset_state

      selection_preview = HandoffAdapterSelectionPreview.new(@root)
      selection_copy = selection_preview.preview_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path,
        envelope_path,
        profile_path,
        selection_proposal_path
      )
      errors.concat(selection_preview.errors)
      return nil unless selection_copy

      confirmation_document, confirmation_bytes = load_yaml_file_with_bytes(selection_confirmation_path)
      return nil unless confirmation_document

      @envelope = selection_preview.envelope
      @profile = selection_preview.profile
      @proposal = selection_preview.proposal
      @confirmation = confirmation_document
      @input_digests = selection_preview.input_digests.dup
      @confirmation_file_sha256 = Digest::SHA256.hexdigest(confirmation_bytes)
      return nil unless validate_confirmation_schema(confirmation_document, selection_confirmation_path)

      validate_binding(confirmation_document, selection_confirmation_path)
      validate_choice(confirmation_document, selection_confirmation_path)
      validate_response_digest(confirmation_document, selection_confirmation_path)
      validate_time(confirmation_document, selection_confirmation_path)
      validate_data_policy(confirmation_document, selection_confirmation_path)
      return nil unless errors.empty?

      render_copy(confirmation_document)
    end

    private

    def reset_state
      @envelope = nil
      @profile = nil
      @proposal = nil
      @confirmation = nil
      @input_digests = nil
      @confirmation_file_sha256 = nil
    end

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
        "envelope_id" => envelope["envelope_id"],
        "adapter_profile_id" => profile["adapter_profile_id"],
        "adapter_selection_proposal_id" => proposal["adapter_selection_proposal_id"],
        "envelope_delivery_state" => envelope["delivery_state"],
        "adapter_profile_status" => profile["status"],
        "adapter_selection_proposal_status" => proposal.dig("confirmation", "status"),
        "recipient" => envelope["recipient"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its confirmed source" unless document[field] == value
      end
    end

    def validate_choice(document, path)
      expected_selection = document["confirmation_decision"] == "confirmed"
      return if document["adapter_selected"] == expected_selection

      errors << "#{path}: adapter_selected must be true only for confirmed"
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

      errors << "#{path}: Adapter Selection Confirmation Receipt cannot predate its Proposal"
    end

    def validate_data_policy(document, path)
      source_ranks = [
        CLASSIFICATION_RANK[envelope["data_classification"]],
        CLASSIFICATION_RANK[proposal["data_classification"]]
      ].compact
      confirmation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if confirmation_rank && !source_ranks.empty? && confirmation_rank < source_ranks.max
        errors << "#{path}: Adapter Selection Confirmation Receipt data classification cannot downgrade its sources"
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
          "# 已收到 Adapter 选择修改请求，当前未选择",
          "",
          "Handoff Envelope 保持不变，当前 Adapter Profile 与 Selection Proposal 也未被修改。",
          "",
          "请修订或更换 Profile，并生成新的 pending Selection Proposal。当前不会 dispatch，任何渠道副作用和高风险动作仍未获授权。"
        ].join("\n")
      when "rejected"
        [
          "# 已拒绝当前 Adapter 候选",
          "",
          "Handoff Envelope 继续保留，但没有 Adapter 被选择。",
          "",
          "本次拒绝不会 dispatch、不会产生渠道副作用，也不会改变任何 Approval Point。"
        ].join("\n")
      end
    end

    def render_confirmed_copy
      true_effects = HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |field|
        profile.dig("effects", field) == true
      end
      lines = [
        "# 已记录 Adapter 选择，尚未 dispatch",
        "",
        "已记录用户对当前精确 Selection Proposal 的明确确认。选择只绑定这份 verified Envelope 与 reviewed Profile。",
        "",
        "## 已选择的 Adapter",
        "",
        MarkdownSafety.inline(profile.fetch("display_name")),
        "",
        "- Adapter 选择：已记录",
        "- Envelope 状态：prepared，尚未交付",
        "- dispatch：未授权"
      ]
      append_effects(lines, true_effects)
      lines.concat([
                     "",
                     "## 数据边界",
                     "",
                     "- 个人数据兼容性：未知",
                     "- 密钥兼容性：未知",
                     "- Payload Data Attestation：仍为必需",
                     "",
                     "## 下一步",
                     "",
                     "运行独立 Handoff Payload Data Attestation，审核完整 Envelope payload。即使数据审核通过，也必须再对每一项 Adapter 副作用取得明确授权；本 Receipt 不能直接进入 dispatch。"
                   ])
      lines.join("\n")
    end

    def append_effects(lines, effects)
      lines.concat(["", "## 仍未授权的 Adapter 副作用", ""])
      if effects.empty?
        lines << "- Profile 未声明 true 副作用；真实实现仍须重新验证。"
      else
        effects.each do |effect|
          copy = HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)
          lines << "- #{copy}：未授权"
        end
      end
      lines << ""
      lines << "本次选择没有授予任何 effect authorization。"
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 11
    warn "Usage: ruby scripts/preview_handoff_adapter_selection_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterSelectionConfirmationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
