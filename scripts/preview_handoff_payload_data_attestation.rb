#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_selection_confirmation"

module PMind
  class HandoffPayloadDataAttestationPreview
    SCHEMA_PATH = "schemas/handoff-payload-data-attestation-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    REVIEW_METHOD_COPY = {
      "manual" => "人工完整审核",
      "automated" => "自动化完整扫描",
      "hybrid" => "自动化扫描与人工复核"
    }.freeze

    attr_reader :errors, :envelope, :profile, :proposal,
                :selection_confirmation, :attestation, :input_digests,
                :attestation_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path, profile_path, selection_proposal_path, selection_confirmation_path, attestation_path)
      errors.clear
      reset_state

      confirmation_preview = HandoffAdapterSelectionConfirmationPreview.new(@root)
      confirmation_copy = confirmation_preview.preview_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path,
        envelope_path,
        profile_path,
        selection_proposal_path,
        selection_confirmation_path
      )
      errors.concat(confirmation_preview.errors)
      return nil unless confirmation_copy

      copy_confirmation_state(confirmation_preview)
      return nil unless validate_selected_confirmation(selection_confirmation_path)

      attestation_document, attestation_bytes = load_yaml_file_with_bytes(attestation_path)
      return nil unless attestation_document

      @attestation = attestation_document
      @input_digests = confirmation_preview.input_digests.merge(
        "adapter_selection_confirmation_receipt_file_sha256" => confirmation_preview.confirmation_file_sha256
      )
      @attestation_file_sha256 = Digest::SHA256.hexdigest(attestation_bytes)
      return nil unless validate_attestation_schema(attestation_document, attestation_path)

      validate_binding(attestation_document, attestation_path)
      validate_review_provenance(attestation_document, attestation_path)
      validate_category_presence(attestation_document, attestation_path)
      validate_compatibility(attestation_document, attestation_path)
      validate_time(attestation_document, attestation_path)
      validate_data_policy(attestation_document, attestation_path)
      return nil unless errors.empty?

      render_copy(attestation_document)
    end

    private

    def reset_state
      @envelope = nil
      @profile = nil
      @proposal = nil
      @selection_confirmation = nil
      @attestation = nil
      @input_digests = nil
      @attestation_file_sha256 = nil
    end

    def copy_confirmation_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @proposal = preview.proposal
      @selection_confirmation = preview.confirmation
    end

    def validate_selected_confirmation(path)
      return true if selection_confirmation["confirmation_decision"] == "confirmed" && selection_confirmation["adapter_selected"] == true

      errors << "#{path}: Payload Data Attestation requires a confirmed Adapter selection"
      false
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
    rescue SystemCallError, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      [nil, nil]
    end

    def validate_attestation_schema(document, path)
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
        "package_id" => envelope["package_id"],
        "envelope_id" => envelope["envelope_id"],
        "adapter_profile_id" => profile["adapter_profile_id"],
        "adapter_selection_proposal_id" => proposal["adapter_selection_proposal_id"],
        "adapter_selection_confirmation_id" => selection_confirmation["adapter_selection_confirmation_id"],
        "envelope_delivery_state" => envelope["delivery_state"],
        "adapter_profile_status" => profile["status"],
        "adapter_selection_proposal_status" => proposal.dig("confirmation", "status"),
        "selection_confirmation_decision" => selection_confirmation["confirmation_decision"],
        "adapter_selected" => selection_confirmation["adapter_selected"],
        "recipient" => envelope["recipient"],
        "adapter_maximum_data_classification" => profile.dig("data_policy", "maximum_data_classification"),
        "adapter_personal_data_handling" => profile.dig("data_policy", "personal_data_handling"),
        "adapter_secret_handling" => profile.dig("data_policy", "secret_handling")
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its attested source" unless document[field] == value
      end
    end

    def validate_review_provenance(document, path)
      reviewer_present = document["reviewer_ref"] != "not_applicable"
      scanner_present = document["scanner_ref"] != "not_applicable" && document["scanner_version"] != "not_applicable"
      valid = case document["review_method"]
              when "manual"
                reviewer_present && !scanner_present && document["scanner_ref"] == "not_applicable" && document["scanner_version"] == "not_applicable"
              when "automated"
                !reviewer_present && document["reviewer_ref"] == "not_applicable" && scanner_present
              when "hybrid"
                reviewer_present && scanner_present
              end
      return if valid

      errors << "#{path}: review provenance must match manual, automated, or hybrid method"
    end

    def validate_category_presence(document, path)
      validate_presence_pair(
        document,
        path,
        "payload_contains_personal_data",
        "personal_data_categories"
      )
      validate_presence_pair(
        document,
        path,
        "payload_contains_secrets",
        "secret_categories"
      )
    end

    def validate_presence_pair(document, path, flag_field, categories_field)
      expected_presence = !document[categories_field].empty?
      return if document[flag_field] == expected_presence

      errors << "#{path}: #{categories_field} must be non-empty exactly when #{flag_field} is true"
    end

    def validate_compatibility(document, path)
      expected_personal = if document["payload_contains_personal_data"] && profile.dig("data_policy", "personal_data_handling") == "forbidden"
                            "incompatible"
                          else
                            "compatible"
                          end
      expected_secret = document["payload_contains_secrets"] ? "incompatible" : "compatible"
      attestation_rank = CLASSIFICATION_RANK.fetch(document["data_classification"])
      profile_rank = CLASSIFICATION_RANK.fetch(profile.dig("data_policy", "maximum_data_classification"))
      expected_classification = attestation_rank <= profile_rank ? "compatible" : "incompatible"
      expected_overall = [expected_personal, expected_secret, expected_classification].all?("compatible") ? "compatible" : "incompatible"
      expected = {
        "personal_data_compatibility" => expected_personal,
        "secret_compatibility" => expected_secret,
        "data_classification_compatibility" => expected_classification,
        "overall_data_compatibility" => expected_overall
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} must be derived from the payload facts and selected Profile policy" unless document[field] == value
      end
    end

    def validate_time(document, path)
      confirmation_time = parse_time(selection_confirmation["captured_at"])
      review_time = parse_time(document["reviewed_at"])
      return unless confirmation_time && review_time && review_time < confirmation_time

      errors << "#{path}: Payload Data Attestation cannot predate Adapter selection confirmation"
    end

    def validate_data_policy(document, path)
      source_ranks = [
        CLASSIFICATION_RANK[envelope["data_classification"]],
        CLASSIFICATION_RANK[selection_confirmation["data_classification"]]
      ].compact
      attestation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if attestation_rank && !source_ranks.empty? && attestation_rank < source_ranks.max
        errors << "#{path}: Payload Data Attestation data classification cannot downgrade its sources"
      end

      sensitive = document["payload_contains_personal_data"] ||
                  document["payload_contains_secrets"] ||
                  document["attestation_contains_personal_data"]
      if sensitive && document["data_classification"] == "public"
        errors << "#{path}: sensitive payload or attestation metadata cannot use public classification"
      end
    end

    def render_copy(document)
      if document["overall_data_compatibility"] == "compatible"
        render_compatible_copy(document)
      else
        render_incompatible_copy(document)
      end
    end

    def render_compatible_copy(document)
      lines = [
        "# Payload 数据审核已通过，仍未授权 dispatch",
        "",
        "完整 Handoff Envelope payload 已按所选 Adapter Profile 的数据策略完成审核。",
        "",
        "## 审核结果",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "- 审核范围：完整 Handoff Envelope payload",
        "- 审核方式：#{REVIEW_METHOD_COPY.fetch(document.fetch("review_method"))}",
        "- 个人数据：#{compatible_personal_copy(document)}",
        "- 密钥：未发现",
        "- 数据分类：所选 Adapter Profile 可接受",
        "- 数据兼容性：已通过",
        "- dispatch：未授权"
      ]
      append_effect_boundary(lines)
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "建立独立 Adapter Effect Authorization Proposal，逐项披露并请求批准 Profile 中的 true 副作用。数据审核通过不能代替副作用授权或 dispatch 确认。"
                   ])
      lines.join("\n")
    end

    def render_incompatible_copy(document)
      lines = [
        "# Payload 数据与所选 Adapter 不兼容，dispatch 已阻断",
        "",
        "完整 Handoff Envelope payload 已完成审核，但至少一项数据策略不满足所选 Profile。",
        "",
        "## 阻断原因",
        ""
      ]
      if document["personal_data_compatibility"] == "incompatible"
        lines << "- 个人数据：已发现；所选 Adapter Profile 禁止处理"
      end
      if document["secret_compatibility"] == "incompatible"
        lines << "- 密钥：已发现；所选 Adapter Profile 禁止处理"
      end
      if document["data_classification_compatibility"] == "incompatible"
        lines << "- 数据分类：超出所选 Adapter Profile 可接受的最高级别"
      end
      lines.concat([
                     "",
                     "当前 Adapter 选择仍有记录，但不得 dispatch，也没有任何渠道副作用或高风险动作获授权。",
                     "",
                     "请先移除或外置不兼容数据，或选择符合策略的新 Profile；任何变化都必须重新生成 Proposal、Selection Confirmation 与 Payload Data Attestation。"
                   ])
      lines.join("\n")
    end

    def compatible_personal_copy(document)
      return "未发现" unless document["payload_contains_personal_data"]

      "已发现；所选 Adapter Profile 允许处理"
    end

    def append_effect_boundary(lines)
      effects = HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |field|
        profile.dig("effects", field) == true
      end
      lines.concat(["", "## 仍未授权的 Adapter 副作用", ""])
      if effects.empty?
        lines << "- Profile 未声明 true 副作用；真实实现仍须重新验证。"
      else
        effects.each do |effect|
          lines << "- #{HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)}：未授权"
        end
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
  if ARGV.length != 12
    warn "Usage: ruby scripts/preview_handoff_payload_data_attestation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffPayloadDataAttestationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
