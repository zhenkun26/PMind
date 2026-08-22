#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_effect_authorization"

module PMind
  class HandoffAdapterEffectAuthorizationConfirmationPreview
    SCHEMA_PATH = "schemas/handoff-adapter-effect-authorization-confirmation-receipt-v0.yaml"

    attr_reader :errors, :envelope, :profile, :selection_proposal,
                :selection_confirmation, :attestation, :effect_proposal,
                :confirmation, :input_digests, :confirmation_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path, profile_path, selection_proposal_path, selection_confirmation_path, attestation_path, effect_proposal_path, effect_confirmation_path)
      errors.clear
      reset_state

      effect_preview = HandoffAdapterEffectAuthorizationPreview.new(@root)
      effect_copy = effect_preview.preview_files(
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
        attestation_path,
        effect_proposal_path
      )
      errors.concat(effect_preview.errors)
      return nil unless effect_copy

      copy_effect_state(effect_preview)
      confirmation_document, confirmation_bytes = load_yaml_file_with_bytes(effect_confirmation_path)
      return nil unless confirmation_document

      @confirmation = confirmation_document
      @input_digests = effect_preview.input_digests.merge(
        "adapter_effect_authorization_proposal_file_sha256" => effect_preview.effect_proposal_file_sha256
      )
      @confirmation_file_sha256 = Digest::SHA256.hexdigest(confirmation_bytes)
      return nil unless validate_schema(confirmation_document, effect_confirmation_path)

      validate_binding(confirmation_document, effect_confirmation_path)
      validate_choice(confirmation_document, effect_confirmation_path)
      validate_response_digest(confirmation_document, effect_confirmation_path)
      validate_time(confirmation_document, effect_confirmation_path)
      validate_data_policy(confirmation_document, effect_confirmation_path)
      return nil unless errors.empty?

      render_copy(confirmation_document)
    end

    private

    def reset_state
      @envelope = nil
      @profile = nil
      @selection_proposal = nil
      @selection_confirmation = nil
      @attestation = nil
      @effect_proposal = nil
      @confirmation = nil
      @input_digests = nil
      @confirmation_file_sha256 = nil
    end

    def copy_effect_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @selection_proposal = preview.selection_proposal
      @selection_confirmation = preview.selection_confirmation
      @attestation = preview.attestation
      @effect_proposal = preview.effect_proposal
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
        "adapter_effect_authorization_proposal_id" => effect_proposal["adapter_effect_authorization_proposal_id"],
        "envelope_delivery_state" => envelope["delivery_state"],
        "adapter_profile_status" => profile["status"],
        "adapter_selection_proposal_status" => selection_proposal.dig("confirmation", "status"),
        "selection_confirmation_decision" => selection_confirmation["confirmation_decision"],
        "adapter_selected" => selection_confirmation["adapter_selected"],
        "payload_data_attestation_completed" => attestation["payload_data_attestation_completed"],
        "overall_data_compatibility" => attestation["overall_data_compatibility"],
        "adapter_effect_authorization_proposal_status" => effect_proposal["proposal_status"],
        "recipient" => envelope["recipient"],
        "requested_effect_authorizations" => effect_proposal["requested_effect_authorizations"],
        "cost_disclosure_before_dispatch_required" => effect_proposal["cost_disclosure_required"],
        "retention_export_purpose_compatibility" => effect_proposal["retention_export_purpose_compatibility"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its confirmed source" unless document[field] == value
      end
    end

    def validate_choice(document, path)
      confirmed = document["confirmation_decision"] == "confirmed"
      requested = effect_proposal["requested_effect_authorizations"]
      expected_grants = confirmed ? requested : []
      expected_cost = confirmed && requested.include?("cost_incurred")
      expected_production = confirmed && requested.include?("production_data_access")

      unless document["effect_authorization_confirmed"] == confirmed
        errors << "#{path}: effect_authorization_confirmed must be true only for confirmed"
      end
      unless document["effect_authorizations_granted"] == expected_grants
        errors << "#{path}: effect_authorizations_granted must equal all requested effects only for confirmed"
      end
      unless document["all_requested_effects_authorized"] == confirmed
        errors << "#{path}: all_requested_effects_authorized must be true only for confirmed"
      end
      unless document["cost_effect_authorized"] == expected_cost
        errors << "#{path}: cost_effect_authorized must be derived from the confirmed requested effects"
      end
      unless document["production_data_access_authorized"] == expected_production
        errors << "#{path}: production_data_access_authorized must be derived from the confirmed requested effects"
      end
    end

    def validate_response_digest(document, path)
      expected = Digest::SHA256.hexdigest(document["user_response"])
      return if document["user_response_sha256"] == expected

      errors << "#{path}: user response digest does not match"
    end

    def validate_time(document, path)
      proposal_time = parse_time(effect_proposal["created_at"])
      confirmation_time = parse_time(document["captured_at"])
      return unless proposal_time && confirmation_time && confirmation_time < proposal_time

      errors << "#{path}: Adapter Effect Authorization Confirmation Receipt cannot predate its Proposal"
    end

    def validate_data_policy(document, path)
      classification_rank = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK
      proposal_rank = classification_rank[effect_proposal["data_classification"]]
      confirmation_rank = classification_rank[document["data_classification"]]
      if proposal_rank && confirmation_rank && confirmation_rank < proposal_rank
        errors << "#{path}: Adapter Effect Authorization Confirmation Receipt data classification cannot downgrade its source"
      end

      if document["contains_personal_data"] == true && document["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def render_copy(document)
      case document.fetch("confirmation_decision")
      when "confirmed"
        render_confirmed_copy(document)
      when "modify_requested"
        [
          "# 已收到 Adapter 副作用授权修改请求，当前零授权",
          "",
          "当前 Effect Authorization Proposal 与全部来源保持不变；本 Receipt 没有修改 Profile 或授权范围。",
          "",
          "请返回 Profile 或 Proposal 阶段重新生成受影响链。当前不会执行任何副作用，也未授权 dispatch。"
        ].join("\n")
      when "rejected"
        [
          "# 已拒绝当前 Adapter 副作用请求",
          "",
          "没有副作用获授权，Adapter 路径在 dispatch 之前停止。",
          "",
          "本次拒绝不会运行 Adapter、产生外部效果、访问生产数据或改变任何 Approval Point。"
        ].join("\n")
      end
    end

    def render_confirmed_copy(document)
      effects = document["effect_authorizations_granted"]
      lines = [
        "# 已记录 Adapter 副作用授权，仍未授权 dispatch",
        "",
        "已记录用户对当前精确 Effect Authorization Proposal 的明确选择。授权只覆盖下列具名效果，不允许这些效果立即执行。",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "",
        "## 已授权的具名副作用",
        ""
      ]
      append_authorized_effects(lines, effects)
      append_sensitive_effect_boundaries(lines, document)
      lines.concat([
                     "",
                     "## 仍未满足的执行门禁",
                     "",
                     "- Adapter 实现证明：仍为必需",
                     "- provider contract test：仍为必需",
                     "- 凭据与健康检查：尚未建立",
                     "- retention / export / purpose：尚未核验",
                     "- dispatch 确认：仍为必需",
                     "- 当前 effects executable：否",
                     "- 当前 dispatch：未授权",
                     "",
                     "## 下一步",
                     "",
                     "建立 provider-neutral Adapter Implementation Attestation，证明实现与 reviewed Profile 及已授权 effects 一致。本 Receipt 不能启动 Adapter 或代替独立 dispatch 确认。"
                   ])
      lines.join("\n")
    end

    def append_authorized_effects(lines, effects)
      if effects.empty?
        lines << "- 所选 Profile 未声明 true 副作用；已确认零效果集合。"
      else
        effects.each do |effect|
          copy = HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)
          lines << "- #{copy}：已记录授权；尚不可执行"
        end
      end
    end

    def append_sensitive_effect_boundaries(lines, document)
      lines.concat(["", "## 费用与生产数据边界", ""])
      if document["cost_effect_authorized"]
        lines << "- 费用效果类别：已记录授权；金额与上限未授权，dispatch 前仍须披露。"
      else
        lines << "- 费用效果类别：未授权。"
      end
      if document["production_data_access_authorized"]
        lines << "- 生产数据访问效果类别：已记录授权；只适用于精确 Payload，尚不可执行。"
      else
        lines << "- 生产数据访问效果类别：未授权。"
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
  if ARGV.length != 14
    warn "Usage: ruby scripts/preview_handoff_adapter_effect_authorization_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterEffectAuthorizationConfirmationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
