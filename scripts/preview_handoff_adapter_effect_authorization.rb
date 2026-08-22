#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_payload_data_attestation"

module PMind
  class HandoffAdapterEffectAuthorizationPreview
    SCHEMA_PATH = "schemas/handoff-adapter-effect-authorization-proposal-v0.yaml"

    attr_reader :errors, :envelope, :profile, :selection_proposal,
                :selection_confirmation, :attestation, :effect_proposal,
                :input_digests, :effect_proposal_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path, profile_path, selection_proposal_path, selection_confirmation_path, attestation_path, effect_proposal_path)
      errors.clear
      reset_state

      attestation_preview = HandoffPayloadDataAttestationPreview.new(@root)
      attestation_copy = attestation_preview.preview_files(
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
        selection_confirmation_path,
        attestation_path
      )
      errors.concat(attestation_preview.errors)
      return nil unless attestation_copy

      copy_attestation_state(attestation_preview)
      return nil unless validate_compatible_attestation(attestation_path)

      proposal_document, proposal_bytes = load_yaml_file_with_bytes(effect_proposal_path)
      return nil unless proposal_document

      @effect_proposal = proposal_document
      @input_digests = attestation_preview.input_digests.merge(
        "payload_data_attestation_file_sha256" => attestation_preview.attestation_file_sha256
      )
      @effect_proposal_file_sha256 = Digest::SHA256.hexdigest(proposal_bytes)
      return nil unless validate_schema(proposal_document, effect_proposal_path)

      validate_binding(proposal_document, effect_proposal_path)
      validate_effect_set(proposal_document, effect_proposal_path)
      validate_disclosures(proposal_document, effect_proposal_path)
      validate_time(proposal_document, effect_proposal_path)
      validate_data_policy(proposal_document, effect_proposal_path)
      return nil unless errors.empty?

      render_copy(proposal_document)
    end

    private

    def reset_state
      @envelope = nil
      @profile = nil
      @selection_proposal = nil
      @selection_confirmation = nil
      @attestation = nil
      @effect_proposal = nil
      @input_digests = nil
      @effect_proposal_file_sha256 = nil
    end

    def copy_attestation_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @selection_proposal = preview.proposal
      @selection_confirmation = preview.selection_confirmation
      @attestation = preview.attestation
    end

    def validate_compatible_attestation(path)
      return true if attestation["payload_data_attestation_completed"] == true &&
                     attestation["overall_data_compatibility"] == "compatible"

      errors << "#{path}: Adapter effect authorization proposal requires a compatible completed Payload Data Attestation"
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

    def validate_schema(document, path)
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
        "adapter_selection_proposal_id" => selection_proposal["adapter_selection_proposal_id"],
        "adapter_selection_confirmation_id" => selection_confirmation["adapter_selection_confirmation_id"],
        "payload_data_attestation_id" => attestation["payload_data_attestation_id"],
        "envelope_delivery_state" => envelope["delivery_state"],
        "adapter_profile_status" => profile["status"],
        "adapter_selection_proposal_status" => selection_proposal.dig("confirmation", "status"),
        "selection_confirmation_decision" => selection_confirmation["confirmation_decision"],
        "adapter_selected" => selection_confirmation["adapter_selected"],
        "payload_data_attestation_completed" => attestation["payload_data_attestation_completed"],
        "overall_data_compatibility" => attestation["overall_data_compatibility"],
        "recipient" => envelope["recipient"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its attested source" unless document[field] == value
      end
    end

    def validate_effect_set(document, path)
      true_effects = HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |effect|
        profile.dig("effects", effect) == true
      end
      requested = document["requested_effect_authorizations"]
      return if requested.sort == true_effects.sort

      errors << "#{path}: requested_effect_authorizations must exactly match the selected Profile true effects"
    end

    def validate_disclosures(document, path)
      cost_present = profile.dig("effects", "cost_incurred") == true
      profile_cost_disclosure = profile.dig("cost_policy", "disclosure_required_before_dispatch")
      unless profile_cost_disclosure == cost_present
        errors << "#{path}: selected Profile cost disclosure policy must match its cost effect"
      end
      expected_cost_disclosure = cost_present
      expected_estimate_status = cost_present ? "not_estimated" : "not_applicable"
      production_present = profile.dig("effects", "production_data_access") == true

      errors << "#{path}: cost_effect_present must match the selected Profile" unless document["cost_effect_present"] == cost_present
      errors << "#{path}: cost_disclosure_required must match the selected Profile" unless document["cost_disclosure_required"] == expected_cost_disclosure
      errors << "#{path}: cost_estimate_status must reflect whether cost is possible" unless document["cost_estimate_status"] == expected_estimate_status
      unless document["production_data_access_disclosure_required"] == production_present
        errors << "#{path}: production_data_access_disclosure_required must match the selected Profile"
      end
    end

    def validate_time(document, path)
      attestation_time = parse_time(attestation["reviewed_at"])
      proposal_time = parse_time(document["created_at"])
      return unless attestation_time && proposal_time && proposal_time < attestation_time

      errors << "#{path}: Adapter effect authorization proposal cannot predate Payload Data Attestation"
    end

    def validate_data_policy(document, path)
      proposal_rank = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK[document["data_classification"]]
      attestation_rank = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK[attestation["data_classification"]]
      if proposal_rank && attestation_rank && proposal_rank < attestation_rank
        errors << "#{path}: Adapter effect authorization proposal data classification cannot downgrade its source"
      end
    end

    def render_copy(document)
      lines = [
        "# Adapter 副作用授权提案待确认，当前零授权",
        "",
        "数据兼容性已经通过，但这不等于任何渠道副作用或 dispatch 已获批准。",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "",
        "## 待确认的副作用",
        ""
      ]
      append_effects(lines, document)
      append_disclosures(lines, document)
      lines.concat([
                     "",
                     "## 当前权限边界",
                     "",
                     "- 用户选择：尚未记录",
                     "- 已授予的副作用授权：无",
                     "- dispatch：未授权",
                     "- 外部效果与高风险授权：均未授权",
                     "- retention / export / purpose：尚未核验",
                     "",
                     "## 请选择",
                     "",
                     "1. 确认全部列出的副作用：只允许后续建立独立 Confirmation Receipt；仍不 dispatch。",
                     "2. 请求修改授权范围：返回选择或 Profile 阶段重新生成后续链。",
                     "3. 拒绝：保持零授权并停止该 Adapter 路径。",
                     "",
                     "本 Proposal 不保存选择。任何选择都必须进入独立 Adapter Effect Authorization Confirmation Receipt；真实 Adapter 实现与 dispatch 确认继续后置。"
                   ])
      lines.join("\n")
    end

    def append_effects(lines, document)
      effects = document["requested_effect_authorizations"]
      if effects.empty?
        lines << "- 所选 Profile 未声明 true 副作用；仍需确认该声明，且不能跳过未来 dispatch 确认。"
      else
        effects.each do |effect|
          lines << "- #{HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)}：待单独授权"
        end
      end
    end

    def append_disclosures(lines, document)
      lines.concat(["", "## 强制披露", ""])
      if document["cost_effect_present"]
        lines << "- 费用：可能产生费用；当前未估算，dispatch 前必须另行披露。"
      else
        lines << "- 费用：Profile 未声明费用副作用。"
      end
      if document["production_data_access_disclosure_required"]
        lines << "- 生产数据：该 Adapter 路径会访问生产数据，当前未授权。"
      else
        lines << "- 生产数据：Profile 未声明生产数据访问。"
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
  if ARGV.length != 13
    warn "Usage: ruby scripts/preview_handoff_adapter_effect_authorization.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterEffectAuthorizationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
