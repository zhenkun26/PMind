#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_runtime_readiness_attestation"

module PMind
  class HandoffAdapterDispatchProposalPreview
    SCHEMA_PATH = "schemas/handoff-adapter-dispatch-proposal-v0.yaml"
    CLASSIFICATION_RANK = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK
    DESTINATION_KIND = {
      "local_file" => "local_path",
      "local_process" => "local_process_endpoint",
      "remote_api" => "provider_endpoint",
      "message_channel" => "message_destination",
      "human_team" => "human_recipient"
    }.freeze
    DESTINATION_COPY = {
      "local_path" => "本地目标路径引用",
      "local_process_endpoint" => "本地进程端点引用",
      "provider_endpoint" => "provider 端点引用",
      "message_destination" => "消息目标引用",
      "human_recipient" => "人工接收者引用"
    }.freeze
    STOP_CONDITION_ORDER = %w[
      source_bytes_changed
      authorization_changed
      runtime_readiness_changed
      proposal_not_yet_valid
      proposal_expired
      idempotency_conflict
      credential_not_ready
      provider_health_not_current
      cost_ceiling_would_be_exceeded
      unlisted_effect_requested
      delivery_failure
      receipt_failure
    ].freeze
    STOP_CONDITION_COPY = {
      "source_bytes_changed" => "任一来源字节发生变化",
      "authorization_changed" => "具名 effect 授权发生变化",
      "runtime_readiness_changed" => "运行时就绪声明不再成立",
      "proposal_not_yet_valid" => "尚未进入 Proposal 有效窗口",
      "proposal_expired" => "Proposal 已过期",
      "idempotency_conflict" => "幂等键冲突",
      "credential_not_ready" => "凭据引用声明不再就绪",
      "provider_health_not_current" => "provider 健康证据不再新鲜",
      "cost_ceiling_would_be_exceeded" => "可能超过费用上限",
      "unlisted_effect_requested" => "请求了未具名授权的 effect",
      "delivery_failure" => "交付失败",
      "receipt_failure" => "无法取得要求的回执"
    }.freeze

    attr_reader :errors, :envelope, :profile, :selection_proposal,
                :selection_confirmation, :payload_attestation, :effect_proposal,
                :effect_confirmation, :implementation_attestation,
                :runtime_attestation, :dispatch_proposal, :input_digests,
                :dispatch_proposal_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(*paths)
      errors.clear
      reset_state
      unless paths.length == 17
        errors << "Adapter Dispatch Proposal preview requires exactly seventeen files"
        return nil
      end

      runtime_preview = HandoffAdapterRuntimeReadinessAttestationPreview.new(@root)
      runtime_copy = runtime_preview.preview_files(*paths.first(16))
      errors.concat(runtime_preview.errors)
      return nil unless runtime_copy

      copy_runtime_state(runtime_preview)
      return nil unless validate_ready_runtime(paths.fetch(15))
      return nil unless validate_adapter_dispatch_capability(paths.fetch(8))

      document, bytes = load_yaml_file_with_bytes(paths.fetch(16))
      return nil unless document

      @dispatch_proposal = document
      @input_digests = runtime_preview.input_digests.merge(
        "adapter_runtime_readiness_attestation_file_sha256" => runtime_preview.runtime_attestation_file_sha256
      )
      @dispatch_proposal_file_sha256 = Digest::SHA256.hexdigest(bytes)
      return nil unless validate_schema(document, paths.fetch(16))

      validate_binding(document, paths.fetch(16))
      validate_destination(document, paths.fetch(16))
      validate_time_window(document, paths.fetch(16))
      validate_idempotency(document, paths.fetch(16))
      validate_attempt_policy(document, paths.fetch(16))
      validate_health_freshness(document, paths.fetch(16))
      validate_cost_ceiling(document, paths.fetch(16))
      validate_stop_conditions(document, paths.fetch(16))
      validate_data_policy(document, paths.fetch(16))
      return nil unless errors.empty?

      render_copy(document)
    end

    def self.derived_idempotency_key(document)
      fields = %w[
        dispatch_payload_file_sha256
        adapter_profile_file_sha256
        adapter_implementation_attestation_file_sha256
        adapter_runtime_readiness_attestation_file_sha256
        dispatch_destination_kind
        dispatch_destination_ref
        proposed_at
        not_before
        expires_at
        dispatch_attempt_limit
        dispatch_timeout_seconds
        cost_ceiling_amount
        cost_ceiling_currency
      ]
      Digest::SHA256.hexdigest(fields.map { |field| document[field].to_s }.join("\n"))
    end

    private

    def reset_state
      @envelope = @profile = @selection_proposal = @selection_confirmation = nil
      @payload_attestation = @effect_proposal = @effect_confirmation = nil
      @implementation_attestation = @runtime_attestation = @dispatch_proposal = nil
      @input_digests = @dispatch_proposal_file_sha256 = nil
    end

    def copy_runtime_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @selection_proposal = preview.selection_proposal
      @selection_confirmation = preview.selection_confirmation
      @payload_attestation = preview.payload_attestation
      @effect_proposal = preview.effect_proposal
      @effect_confirmation = preview.effect_confirmation
      @implementation_attestation = preview.implementation_attestation
      @runtime_attestation = preview.runtime_attestation
    end

    def validate_ready_runtime(path)
      valid = runtime_attestation["adapter_runtime_readiness_attestation_completed"] == true &&
              runtime_attestation["runtime_evidence_reviewed"] == true &&
              runtime_attestation["overall_runtime_readiness"] == "ready"
      return true if valid

      errors << "#{path}: Adapter Dispatch Proposal requires a ready completed Runtime Readiness Attestation"
      false
    end

    def validate_adapter_dispatch_capability(path)
      return true if profile.dig("capabilities", "idempotency", "supported") == true

      errors << "#{path}: Adapter Dispatch Proposal requires Adapter idempotency support"
      false
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
        "envelope_delivery_state" => envelope["delivery_state"],
        "adapter_profile_status" => profile["status"],
        "adapter_selection_proposal_status" => selection_proposal.dig("confirmation", "status"),
        "selection_confirmation_decision" => selection_confirmation["confirmation_decision"],
        "adapter_selected" => selection_confirmation["adapter_selected"],
        "payload_data_attestation_completed" => payload_attestation["payload_data_attestation_completed"],
        "overall_data_compatibility" => payload_attestation["overall_data_compatibility"],
        "adapter_effect_authorization_proposal_status" => effect_proposal["proposal_status"],
        "effect_authorization_confirmation_decision" => effect_confirmation["confirmation_decision"],
        "effect_authorization_confirmed" => effect_confirmation["effect_authorization_confirmed"],
        "all_requested_effects_authorized" => effect_confirmation["all_requested_effects_authorized"],
        "adapter_implementation_attestation_completed" => implementation_attestation["adapter_implementation_attestation_completed"],
        "overall_implementation_compatibility" => implementation_attestation["overall_implementation_compatibility"],
        "adapter_runtime_readiness_attestation_completed" => runtime_attestation["adapter_runtime_readiness_attestation_completed"],
        "runtime_evidence_reviewed" => runtime_attestation["runtime_evidence_reviewed"],
        "overall_runtime_readiness" => runtime_attestation["overall_runtime_readiness"],
        "recipient" => envelope["recipient"],
        "adapter_key" => profile["adapter_key"],
        "implementation_kind" => implementation_attestation["implementation_kind"],
        "implementation_ref" => implementation_attestation["implementation_ref"],
        "implementation_version" => implementation_attestation["implementation_version"],
        "declared_implementation_sha256" => implementation_attestation["declared_implementation_sha256"],
        "runtime_environment_kind" => runtime_attestation["runtime_environment_kind"],
        "runtime_environment_ref" => runtime_attestation["runtime_environment_ref"],
        "delivery_mode" => profile.dig("capabilities", "delivery_mode"),
        "receipt_mode" => profile.dig("capabilities", "receipt_mode"),
        "adapter_idempotency_supported" => profile.dig("capabilities", "idempotency", "supported"),
        "adapter_idempotency_key_source" => profile.dig("capabilities", "idempotency", "key_source"),
        "adapter_retry_mode" => profile.dig("capabilities", "retry", "mode"),
        "adapter_maximum_attempts" => profile.dig("capabilities", "retry", "maximum_attempts"),
        "authorized_effects" => runtime_attestation["authorized_effects"],
        "dispatch_payload_file_sha256" => input_digests["handoff_envelope_file_sha256"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its attested source" unless document[field] == value
      end
    end

    def validate_destination(document, path)
      expected_kind = DESTINATION_KIND[profile.dig("capabilities", "delivery_mode")]
      errors << "#{path}: dispatch_destination_kind must match Adapter delivery mode" unless document["dispatch_destination_kind"] == expected_kind
      errors << "#{path}: dispatch_destination_ref must identify one controlled destination" if document["dispatch_destination_ref"] == "not_applicable"
    end

    def validate_time_window(document, path)
      runtime_time = parse_time(runtime_attestation["reviewed_at"])
      proposed_time = parse_time(document["proposed_at"])
      not_before_time = parse_time(document["not_before"])
      expiry_time = parse_time(document["expires_at"])
      return unless runtime_time && proposed_time && not_before_time && expiry_time

      errors << "#{path}: Dispatch Proposal cannot predate Runtime Readiness Attestation" if proposed_time < runtime_time
      errors << "#{path}: not_before cannot predate proposed_at" if not_before_time < proposed_time
      errors << "#{path}: not_before must predate expires_at" unless not_before_time < expiry_time
      expected_validity = expiry_time - proposed_time
      errors << "#{path}: validity_seconds must equal expires_at minus proposed_at" unless document["validity_seconds"] == expected_validity
    end

    def validate_idempotency(document, path)
      expected = self.class.derived_idempotency_key(document)
      return if document["idempotency_key_sha256"] == expected

      errors << "#{path}: idempotency_key_sha256 must be derived from the exact dispatch binding"
    end

    def validate_attempt_policy(document, path)
      limit = document["dispatch_attempt_limit"]
      maximum = profile.dig("capabilities", "retry", "maximum_attempts")
      if limit > maximum
        errors << "#{path}: dispatch_attempt_limit cannot exceed Adapter retry capability"
      end
      if profile.dig("capabilities", "retry", "mode") == "none" && limit != 1
        errors << "#{path}: no-retry Adapter requires exactly one dispatch attempt"
      end
      not_before_time = parse_time(document["not_before"])
      expiry_time = parse_time(document["expires_at"])
      if not_before_time && expiry_time && limit * document["dispatch_timeout_seconds"] > expiry_time - not_before_time
        errors << "#{path}: dispatch attempt budget cannot exceed the available validity window"
      end
    end

    def validate_health_freshness(document, path)
      required = runtime_attestation["provider_health_check_requirement"] == "required"
      expected_requirement = required ? "required" : "not_required"
      unless document["provider_health_freshness_requirement"] == expected_requirement
        errors << "#{path}: provider health freshness requirement must match Runtime Readiness Attestation"
      end

      unless required
        valid = document["maximum_health_evidence_age_seconds"] == 0 &&
                document["provider_health_evidence_freshness"] == "not_applicable"
        errors << "#{path}: non-required provider health freshness must be not_applicable" unless valid
        return
      end

      not_before_time = parse_time(document["not_before"])
      health_time = parse_time(runtime_attestation["provider_health_checked_at"])
      maximum_age = document["maximum_health_evidence_age_seconds"]
      current = not_before_time && health_time && not_before_time >= health_time &&
                (not_before_time - health_time) <= maximum_age
      unless current && document["provider_health_evidence_freshness"] == "current"
        errors << "#{path}: submitted provider health evidence must remain current at not_before"
      end
    end

    def validate_cost_ceiling(document, path)
      required = document["authorized_effects"].include?("cost_incurred")
      errors << "#{path}: cost_ceiling_required must be derived from cost_incurred" unless document["cost_ceiling_required"] == required
      if required
        valid = document["cost_ceiling_amount"] != "not_applicable" &&
                document["cost_ceiling_currency"] != "not_applicable" &&
                document["cost_limit_authorization_status"] == "pending_confirmation"
        errors << "#{path}: cost dispatch requires a positive fixed-point ceiling and pending confirmation" unless valid
      else
        values = [document["cost_ceiling_amount"], document["cost_ceiling_currency"],
                  document["cost_limit_authorization_status"]]
        errors << "#{path}: no-cost dispatch ceiling fields must be not_applicable" unless values.all? { |value| value == "not_applicable" }
      end
    end

    def validate_stop_conditions(document, path)
      expected = expected_stop_conditions(document)
      return if document["stop_conditions"] == expected

      errors << "#{path}: stop_conditions must be the canonical complete set for this dispatch"
    end

    def expected_stop_conditions(document)
      required = %w[
        source_bytes_changed
        authorization_changed
        runtime_readiness_changed
        proposal_not_yet_valid
        proposal_expired
        idempotency_conflict
        unlisted_effect_requested
        delivery_failure
      ]
      required << "credential_not_ready" if runtime_attestation["credential_requirement"] == "required"
      required << "provider_health_not_current" if runtime_attestation["provider_health_check_requirement"] == "required"
      required << "cost_ceiling_would_be_exceeded" if document["cost_ceiling_required"] == true
      required << "receipt_failure" unless document["receipt_mode"] == "none"
      STOP_CONDITION_ORDER.select { |condition| required.include?(condition) }
    end

    def validate_data_policy(document, path)
      source_rank = CLASSIFICATION_RANK[runtime_attestation["data_classification"]]
      proposal_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if source_rank && proposal_rank && proposal_rank < source_rank
        errors << "#{path}: Dispatch Proposal data classification cannot downgrade its source"
      end
    end

    def render_copy(document)
      lines = [
        "# Adapter dispatch 提案待确认，尚未调用 provider",
        "",
        "已准备一个绑定精确 payload、Adapter、目标、幂等键和有效期的只读决策提案。它没有保存选择、启动 Adapter、调用 provider 或执行任何 effect。",
        "",
        "## 提案摘要",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "- 接收者：coding agent",
        "- 目标类型：#{DESTINATION_COPY.fetch(document.fetch("dispatch_destination_kind"))}",
        "- 交付方式：#{HandoffAdapterSelectionPreview::DELIVERY_COPY.fetch(document.fetch("delivery_mode"))}",
        "- 回执方式：#{HandoffAdapterSelectionPreview::RECEIPT_COPY.fetch(document.fetch("receipt_mode"))}",
        "- 最大尝试次数：#{document.fetch("dispatch_attempt_limit")}",
        "- 单次超时：#{document.fetch("dispatch_timeout_seconds")} 秒",
        "- Proposal 有效期：#{document.fetch("validity_seconds")} 秒",
        "- 幂等边界：绑定本次精确 dispatch"
      ]
      append_cost(lines, document)
      append_effects(lines, document)
      append_stop_conditions(lines, document)
      lines.concat([
                     "",
                     "## 当前权限状态",
                     "",
                     "- 用户选择：尚未保存",
                     "- effects executable：否",
                     "- Adapter 已启动：否",
                     "- provider 已调用：否",
                     "- dispatch：未授权且未尝试",
                     "- 外部写入或费用：均未发生",
                     "",
                     "## 请选择",
                     "",
                     "- 确认：针对本次精确 Proposal 创建独立 Dispatch Confirmation Receipt",
                     "- 修改：调整目标、尝试次数、超时、有效期、费用上限或停止条件后重建 Proposal",
                     "- 拒绝：终止本次 dispatch 路径",
                     "",
                     "选择必须写入独立 Receipt 后再重放全部来源；本预演本身不能执行 dispatch。"
                   ])
      lines.join("\n")
    end

    def append_cost(lines, document)
      if document["cost_ceiling_required"]
        lines << "- 费用上限：#{document.fetch("cost_ceiling_amount")} #{document.fetch("cost_ceiling_currency")}；仍待本次 dispatch 独立确认"
      else
        lines << "- 费用上限：不适用；本 Proposal 不含 cost effect"
      end
    end

    def append_effects(lines, document)
      lines.concat(["", "## 已具名授权但仍不可执行的 effects", ""])
      if document["authorized_effects"].empty?
        lines << "- 零 effect 集合；dispatch 仍需确认"
      else
        document["authorized_effects"].each do |effect|
          lines << "- #{HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)}：已具名授权；仍不可执行"
        end
      end
    end

    def append_stop_conditions(lines, document)
      lines.concat(["", "## 强制停止条件", ""])
      document["stop_conditions"].each do |condition|
        lines << "- #{STOP_CONDITION_COPY.fetch(condition)}"
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
  if ARGV.length != 17
    warn "Usage: ruby scripts/preview_handoff_adapter_dispatch_proposal.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterDispatchProposalPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
