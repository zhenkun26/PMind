#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_dispatch_proposal"

module PMind
  class HandoffAdapterDispatchConfirmationPreview
    SCHEMA_PATH = "schemas/handoff-adapter-dispatch-confirmation-receipt-v0.yaml"
    CLASSIFICATION_RANK = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK

    attr_reader :errors, :envelope, :profile, :selection_proposal,
                :selection_confirmation, :payload_attestation, :effect_proposal,
                :effect_confirmation, :implementation_attestation,
                :runtime_attestation, :dispatch_proposal, :dispatch_confirmation,
                :input_digests, :dispatch_confirmation_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(*paths)
      errors.clear
      reset_state
      unless paths.length == 18
        errors << "Adapter Dispatch Confirmation preview requires exactly eighteen files"
        return nil
      end

      proposal_preview = HandoffAdapterDispatchProposalPreview.new(@root)
      proposal_copy = proposal_preview.preview_files(*paths.first(17))
      errors.concat(proposal_preview.errors)
      return nil unless proposal_copy

      copy_proposal_state(proposal_preview)
      document, bytes = load_yaml_file_with_bytes(paths.fetch(17))
      return nil unless document

      @dispatch_confirmation = document
      @input_digests = proposal_preview.input_digests.merge(
        "adapter_dispatch_proposal_file_sha256" => proposal_preview.dispatch_proposal_file_sha256
      )
      @dispatch_confirmation_file_sha256 = Digest::SHA256.hexdigest(bytes)
      return nil unless validate_schema(document, paths.fetch(17))

      validate_binding(document, paths.fetch(17))
      validate_choice(document, paths.fetch(17))
      validate_response_digest(document, paths.fetch(17))
      validate_time(document, paths.fetch(17))
      validate_data_policy(document, paths.fetch(17))
      return nil unless errors.empty?

      render_copy(document)
    end

    private

    def reset_state
      @envelope = @profile = @selection_proposal = @selection_confirmation = nil
      @payload_attestation = @effect_proposal = @effect_confirmation = nil
      @implementation_attestation = @runtime_attestation = nil
      @dispatch_proposal = @dispatch_confirmation = nil
      @input_digests = @dispatch_confirmation_file_sha256 = nil
    end

    def copy_proposal_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @selection_proposal = preview.selection_proposal
      @selection_confirmation = preview.selection_confirmation
      @payload_attestation = preview.payload_attestation
      @effect_proposal = preview.effect_proposal
      @effect_confirmation = preview.effect_confirmation
      @implementation_attestation = preview.implementation_attestation
      @runtime_attestation = preview.runtime_attestation
      @dispatch_proposal = preview.dispatch_proposal
    end

    def load_yaml_file_with_bytes(path)
      bytes = File.binread(File.expand_path(path))
      document = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
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
        "payload_data_attestation_id" => payload_attestation["payload_data_attestation_id"],
        "adapter_effect_authorization_proposal_id" => effect_proposal["adapter_effect_authorization_proposal_id"],
        "adapter_effect_authorization_confirmation_id" => effect_confirmation["adapter_effect_authorization_confirmation_id"],
        "adapter_implementation_attestation_id" => implementation_attestation["adapter_implementation_attestation_id"],
        "adapter_runtime_readiness_attestation_id" => runtime_attestation["adapter_runtime_readiness_attestation_id"],
        "adapter_dispatch_proposal_id" => dispatch_proposal["adapter_dispatch_proposal_id"],
        "overall_runtime_readiness" => runtime_attestation["overall_runtime_readiness"],
        "dispatch_proposal_status" => dispatch_proposal["dispatch_proposal_status"],
        "recipient" => dispatch_proposal["recipient"],
        "adapter_key" => dispatch_proposal["adapter_key"],
        "dispatch_payload_kind" => dispatch_proposal["dispatch_payload_kind"],
        "dispatch_payload_file_sha256" => dispatch_proposal["dispatch_payload_file_sha256"],
        "delivery_mode" => dispatch_proposal["delivery_mode"],
        "receipt_mode" => dispatch_proposal["receipt_mode"],
        "dispatch_destination_kind" => dispatch_proposal["dispatch_destination_kind"],
        "dispatch_destination_ref" => dispatch_proposal["dispatch_destination_ref"],
        "idempotency_key_sha256" => dispatch_proposal["idempotency_key_sha256"],
        "proposed_at" => dispatch_proposal["proposed_at"],
        "not_before" => dispatch_proposal["not_before"],
        "expires_at" => dispatch_proposal["expires_at"],
        "dispatch_attempt_limit" => dispatch_proposal["dispatch_attempt_limit"],
        "dispatch_timeout_seconds" => dispatch_proposal["dispatch_timeout_seconds"],
        "authorized_effects" => dispatch_proposal["authorized_effects"],
        "stop_conditions" => dispatch_proposal["stop_conditions"],
        "cost_ceiling_required" => dispatch_proposal["cost_ceiling_required"],
        "cost_ceiling_amount" => dispatch_proposal["cost_ceiling_amount"],
        "cost_ceiling_currency" => dispatch_proposal["cost_ceiling_currency"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its Dispatch Proposal source" unless document[field] == value
      end
    end

    def validate_choice(document, path)
      confirmed = document["confirmation_decision"] == "confirmed"
      expected_cost_authorization = confirmed && dispatch_proposal["cost_ceiling_required"] == true

      unless document["dispatch_authorized"] == confirmed
        errors << "#{path}: dispatch_authorized must be true only for confirmed"
      end
      unless document["cost_limit_authorized"] == expected_cost_authorization
        errors << "#{path}: cost_limit_authorized must be true only for a confirmed cost-bearing Proposal"
      end
      unless document["service_execution_request_required"] == confirmed
        errors << "#{path}: service_execution_request_required must be true only for confirmed"
      end
      unless document["execution_receipt_required"] == confirmed
        errors << "#{path}: execution_receipt_required must be true only for confirmed"
      end
    end

    def validate_response_digest(document, path)
      expected = Digest::SHA256.hexdigest(document["user_response"])
      return if document["user_response_sha256"] == expected

      errors << "#{path}: user response digest does not match"
    end

    def validate_time(document, path)
      proposed_time = parse_time(dispatch_proposal["proposed_at"])
      expires_time = parse_time(dispatch_proposal["expires_at"])
      captured_time = parse_time(document["captured_at"])
      return unless proposed_time && expires_time && captured_time

      if captured_time < proposed_time
        errors << "#{path}: Dispatch Confirmation Receipt cannot predate its Proposal"
      end
      if document["confirmation_decision"] == "confirmed" && captured_time >= expires_time
        errors << "#{path}: confirmed Dispatch Confirmation Receipt must be captured before Proposal expiry"
      end
    end

    def validate_data_policy(document, path)
      proposal_rank = CLASSIFICATION_RANK[dispatch_proposal["data_classification"]]
      confirmation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if proposal_rank && confirmation_rank && confirmation_rank < proposal_rank
        errors << "#{path}: Dispatch Confirmation Receipt data classification cannot downgrade its Proposal"
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
          "# 已收到 Adapter dispatch 修改请求，当前未授权",
          "",
          "当前 Dispatch Proposal 与十六份来源保持不变；本 Receipt 没有改写目标、时间、费用或停止条件。",
          "",
          "请修改精确 dispatch 条件并重建 Proposal。Adapter 未启动，provider 未调用，dispatch 未尝试，也未产生费用。"
        ].join("\n")
      when "rejected"
        [
          "# 已拒绝当前 Adapter dispatch",
          "",
          "当前精确 Dispatch Proposal 未获授权，本次路径在执行请求之前停止。",
          "",
          "本次拒绝不会启动 Adapter、调用 provider、执行 effect、写入外部系统或产生费用。"
        ].join("\n")
      end
    end

    def render_confirmed_copy(document)
      lines = [
        "# 已记录 Adapter dispatch 确认，尚未执行",
        "",
        "已记录用户对当前精确 Dispatch Proposal 的明确确认。授权仅覆盖已绑定的 payload、Adapter、目标、幂等键、时间窗口、限制和停止条件。",
        "",
        "## 已确认范围",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "- 目标类型：#{HandoffAdapterDispatchProposalPreview::DESTINATION_COPY.fetch(document.fetch("dispatch_destination_kind"))}",
        "- 交付方式：#{HandoffAdapterSelectionPreview::DELIVERY_COPY.fetch(document.fetch("delivery_mode"))}",
        "- 回执方式：#{HandoffAdapterSelectionPreview::RECEIPT_COPY.fetch(document.fetch("receipt_mode"))}",
        "- 最大尝试次数：#{document.fetch("dispatch_attempt_limit")}",
        "- 单次超时：#{document.fetch("dispatch_timeout_seconds")} 秒",
        "- dispatch 授权：已记录；仅限当前 exact Proposal"
      ]
      append_cost(lines, document)
      append_effects(lines, document)
      append_stops(lines, document)
      lines.concat([
                     "",
                     "## 尚未发生",
                     "",
                     "- effects executable：否",
                     "- Adapter 已启动：否",
                     "- provider 已调用：否",
                     "- dispatch 已尝试：否",
                     "- delivery receipt：不存在",
                     "- 外部写入或费用：均未发生",
                     "",
                     "## 下一步",
                     "",
                     "创建独立的 Service execution request / preflight，重放全部十八份文件并重新检查有效期、凭据、provider 健康、幂等、费用预算与停止条件。本 Receipt 不能执行 dispatch，也不能代替执行回执。"
                   ])
      lines.join("\n")
    end

    def append_cost(lines, document)
      if document["cost_ceiling_required"]
        lines << "- 费用上限：#{document.fetch("cost_ceiling_amount")} #{document.fetch("cost_ceiling_currency")}；已随本次 exact dispatch 确认"
      else
        lines << "- 费用上限：不适用；本次确认不包含 cost effect"
      end
    end

    def append_effects(lines, document)
      lines.concat(["", "## 已具名授权但仍不可执行的 effects", ""])
      if document["authorized_effects"].empty?
        lines << "- 零 effect 集合"
      else
        document["authorized_effects"].each do |effect|
          lines << "- #{HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)}：已绑定确认；仍不可执行"
        end
      end
    end

    def append_stops(lines, document)
      lines.concat(["", "## Service 必须继续强制的停止条件", ""])
      document["stop_conditions"].each do |condition|
        lines << "- #{HandoffAdapterDispatchProposalPreview::STOP_CONDITION_COPY.fetch(condition)}"
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
  if ARGV.length != 18
    warn "Usage: ruby scripts/preview_handoff_adapter_dispatch_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterDispatchConfirmationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
