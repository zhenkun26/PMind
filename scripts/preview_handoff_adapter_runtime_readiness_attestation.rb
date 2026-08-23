#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_implementation_attestation"

module PMind
  class HandoffAdapterRuntimeReadinessAttestationPreview
    SCHEMA_PATH = "schemas/handoff-adapter-runtime-readiness-attestation-v0.yaml"
    CLASSIFICATION_RANK = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK
    REVIEW_METHOD_COPY = HandoffPayloadDataAttestationPreview::REVIEW_METHOD_COPY
    CONFIGURATION_FIELDS = %w[
      delivery_configuration_compatibility
      receipt_configuration_compatibility
      idempotency_configuration_compatibility
      retry_configuration_compatibility
      effect_guard_configuration_compatibility
      data_policy_configuration_compatibility
      cost_policy_configuration_compatibility
    ].freeze
    CONFIGURATION_COPY = {
      "delivery_configuration_compatibility" => "交付配置",
      "receipt_configuration_compatibility" => "回执配置",
      "idempotency_configuration_compatibility" => "幂等配置",
      "retry_configuration_compatibility" => "重试配置",
      "effect_guard_configuration_compatibility" => "副作用守卫",
      "data_policy_configuration_compatibility" => "数据策略配置",
      "cost_policy_configuration_compatibility" => "费用策略配置"
    }.freeze
    LIFECYCLE_FIELDS = %w[retention_compatibility export_compatibility purpose_compatibility].freeze
    LIFECYCLE_COPY = {
      "retention_compatibility" => "保留策略",
      "export_compatibility" => "导出策略",
      "purpose_compatibility" => "目的绑定"
    }.freeze
    CREDENTIAL_EFFECTS = %w[notification external_service_write cost_incurred production_data_access].freeze
    HEALTH_EFFECTS = %w[network_access notification external_service_write cost_incurred production_data_access].freeze
    ENVIRONMENT_COPY = {
      "local_process" => "本地进程",
      "container" => "容器",
      "managed_service" => "托管服务",
      "remote_api" => "远程 API"
    }.freeze

    attr_reader :errors, :envelope, :profile, :selection_proposal,
                :selection_confirmation, :payload_attestation, :effect_proposal,
                :effect_confirmation, :implementation_attestation,
                :runtime_attestation, :input_digests,
                :runtime_attestation_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(*paths)
      errors.clear
      reset_state
      unless paths.length == 16
        errors << "Adapter Runtime Readiness Attestation preview requires exactly sixteen files"
        return nil
      end

      implementation_preview = HandoffAdapterImplementationAttestationPreview.new(@root)
      implementation_copy = implementation_preview.preview_files(*paths.first(15))
      errors.concat(implementation_preview.errors)
      return nil unless implementation_copy

      copy_implementation_state(implementation_preview)
      return nil unless validate_compatible_implementation(paths.fetch(14))

      document, bytes = load_yaml_file_with_bytes(paths.fetch(15))
      return nil unless document

      @runtime_attestation = document
      @input_digests = implementation_preview.input_digests.merge(
        "adapter_implementation_attestation_file_sha256" => implementation_preview.implementation_attestation_file_sha256
      )
      @runtime_attestation_file_sha256 = Digest::SHA256.hexdigest(bytes)
      return nil unless validate_schema(document, paths.fetch(15))

      validate_binding(document, paths.fetch(15))
      validate_review_provenance(document, paths.fetch(15))
      validate_required_references(document, paths.fetch(15))
      validate_configuration(document, paths.fetch(15))
      validate_credentials(document, paths.fetch(15))
      validate_health(document, paths.fetch(15))
      validate_lifecycle(document, paths.fetch(15))
      validate_cost_gate(document, paths.fetch(15))
      validate_overall_result(document, paths.fetch(15))
      validate_time(document, paths.fetch(15))
      validate_data_policy(document, paths.fetch(15))
      return nil unless errors.empty?

      render_copy(document)
    end

    private

    def reset_state
      @envelope = @profile = @selection_proposal = @selection_confirmation = nil
      @payload_attestation = @effect_proposal = @effect_confirmation = nil
      @implementation_attestation = @runtime_attestation = nil
      @input_digests = @runtime_attestation_file_sha256 = nil
    end

    def copy_implementation_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @selection_proposal = preview.selection_proposal
      @selection_confirmation = preview.selection_confirmation
      @payload_attestation = preview.payload_attestation
      @effect_proposal = preview.effect_proposal
      @effect_confirmation = preview.effect_confirmation
      @implementation_attestation = preview.implementation_attestation
    end

    def validate_compatible_implementation(path)
      valid = implementation_attestation["adapter_implementation_attestation_completed"] == true &&
              implementation_attestation["overall_implementation_compatibility"] == "compatible"
      return true if valid

      errors << "#{path}: Adapter Runtime Readiness Attestation requires a compatible completed implementation attestation"
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
        "recipient" => envelope["recipient"],
        "implementation_kind" => implementation_attestation["implementation_kind"],
        "implementation_ref" => implementation_attestation["implementation_ref"],
        "implementation_version" => implementation_attestation["implementation_version"],
        "declared_implementation_sha256" => implementation_attestation["declared_implementation_sha256"],
        "profile_declared_effects" => implementation_attestation["profile_declared_effects"],
        "authorized_effects" => implementation_attestation["authorized_effects"]
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
      errors << "#{path}: runtime review provenance must match manual, automated, or hybrid method" unless valid
    end

    def validate_required_references(document, path)
      errors << "#{path}: runtime_environment_ref must identify submitted runtime evidence" if document["runtime_environment_ref"] == "not_applicable"
      %w[retention_policy_ref export_policy_ref purpose_binding_ref].each do |field|
        errors << "#{path}: #{field} must identify submitted policy evidence" if document[field] == "not_applicable"
      end
    end

    def validate_configuration(document, path)
      expected = CONFIGURATION_FIELDS.all? { |field| document[field] == "compatible" } ? "compatible" : "incompatible"
      return if document["runtime_configuration_compatibility"] == expected

      errors << "#{path}: runtime_configuration_compatibility must be derived from all seven configuration dimensions"
    end

    def validate_credentials(document, path)
      effect_requires_credentials = (document["authorized_effects"] & CREDENTIAL_EFFECTS).any?
      if effect_requires_credentials && document["credential_requirement"] != "required"
        errors << "#{path}: declared remote write, cost, notification, or production-data effects require credential evidence"
      end

      expected = if document["credential_requirement"] == "not_required"
                   values = [document["credential_reference_status"], document["credential_ref"],
                             document["credential_scope_compatibility"], document["credential_expiry_status"],
                             document["credential_readiness"]]
                   errors << "#{path}: not-required credential evidence must be entirely not_applicable" unless values.all? { |value| value == "not_applicable" }
                   "not_applicable"
                 else
                   ready = document["credential_reference_status"] == "available" &&
                           document["credential_ref"] != "not_applicable" &&
                           document["credential_scope_compatibility"] == "compatible" &&
                           document["credential_expiry_status"] == "valid"
                   ready ? "ready" : "blocked"
                 end
      errors << "#{path}: credential_readiness must be derived from reference, scope, and expiry declarations" unless document["credential_readiness"] == expected
    end

    def validate_health(document, path)
      effect_requires_health = (document["authorized_effects"] & HEALTH_EFFECTS).any?
      if effect_requires_health && document["provider_health_check_requirement"] != "required"
        errors << "#{path}: declared network/provider effects require submitted provider-health evidence"
      end

      if document["provider_health_check_requirement"] == "not_required"
        values = [document["provider_health_evidence_status"], document["provider_health_evidence_ref"],
                  document["provider_health_evidence_sha256"], document["provider_health_checked_at"],
                  document["provider_health_readiness"]]
        errors << "#{path}: not-required provider-health evidence must be entirely not_applicable" unless values.all? { |value| value == "not_applicable" }
        return
      end

      present = document["provider_health_evidence_ref"] != "not_applicable" &&
                document["provider_health_evidence_sha256"] != "not_applicable" &&
                parse_time(document["provider_health_checked_at"])
      unless parse_time(document["provider_health_checked_at"])
        errors << "#{path}: required provider_health_checked_at must be an ISO-8601 timestamp"
      end
      expected = document["provider_health_evidence_status"] == "healthy" && present ? "ready" : "blocked"
      errors << "#{path}: provider_health_readiness must be derived from submitted health evidence" unless document["provider_health_readiness"] == expected
    end

    def validate_lifecycle(document, path)
      expected = LIFECYCLE_FIELDS.all? { |field| document[field] == "compatible" } ? "compatible" : "incompatible"
      return if document["retention_export_purpose_compatibility"] == expected

      errors << "#{path}: retention_export_purpose_compatibility must combine all three lifecycle dimensions"
    end

    def validate_cost_gate(document, path)
      required = document["authorized_effects"].include?("cost_incurred")
      expected_status = required ? "pending_authorization" : "not_applicable"
      errors << "#{path}: cost_limit_authorization_required must be derived from cost_incurred" unless document["cost_limit_authorization_required"] == required
      errors << "#{path}: dispatch_cost_gate_status must preserve the independent cost limit gate" unless document["dispatch_cost_gate_status"] == expected_status
    end

    def validate_overall_result(document, path)
      ready = document["runtime_configuration_compatibility"] == "compatible" &&
              document["credential_readiness"] != "blocked" &&
              document["provider_health_readiness"] != "blocked" &&
              document["retention_export_purpose_compatibility"] == "compatible"
      expected = ready ? "ready" : "blocked"
      errors << "#{path}: overall_runtime_readiness must combine configuration, credential, health, and lifecycle declarations" unless document["overall_runtime_readiness"] == expected
    end

    def validate_time(document, path)
      implementation_time = parse_time(implementation_attestation["reviewed_at"])
      review_time = parse_time(document["reviewed_at"])
      if implementation_time && review_time && review_time < implementation_time
        errors << "#{path}: Runtime Readiness Attestation cannot predate Implementation Attestation"
      end
      return unless document["provider_health_check_requirement"] == "required"

      health_time = parse_time(document["provider_health_checked_at"])
      if health_time && implementation_time && health_time < implementation_time
        errors << "#{path}: submitted provider-health evidence cannot predate Implementation Attestation"
      end
      if health_time && review_time && health_time > review_time
        errors << "#{path}: submitted provider-health evidence cannot postdate Runtime Readiness review"
      end
    end

    def validate_data_policy(document, path)
      source_rank = CLASSIFICATION_RANK[implementation_attestation["data_classification"]]
      attestation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if source_rank && attestation_rank && attestation_rank < source_rank
        errors << "#{path}: Runtime Readiness Attestation data classification cannot downgrade its source"
      end
    end

    def render_copy(document)
      document["overall_runtime_readiness"] == "ready" ? render_ready_copy(document) : render_blocked_copy(document)
    end

    def render_ready_copy(document)
      lines = [
        "# Adapter 运行时就绪声明已通过，仍未授权 dispatch",
        "",
        "已完成对精确实现、运行配置及提交证据的声明式审核。PMind 预演没有访问运行环境或凭据，也没有执行 provider 健康检查。",
        "",
        "## 审核结果",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "- 运行环境类型：#{ENVIRONMENT_COPY.fetch(document.fetch("runtime_environment_kind"))}",
        "- 审核方式：#{REVIEW_METHOD_COPY.fetch(document.fetch("review_method"))}",
        "- 七项运行配置：声明兼容",
        "- 凭据引用证据：#{document["credential_readiness"] == "ready" ? "声明就绪" : "不适用"}",
        "- provider 健康证据：#{document["provider_health_readiness"] == "ready" ? "声明健康" : "不适用"}",
        "- 保留、导出与目的策略：声明兼容",
        "- 运行时就绪：声明通过"
      ]
      append_effects(lines, document)
      append_dispatch_gates(lines, document)
      lines.concat(["", "## 下一步", "", "建立独立 Adapter Dispatch Proposal，绑定精确 payload、接收者、幂等键、费用边界和停止条件；之后仍需单独 dispatch 确认。本 Attestation 不能启动 Adapter 或调用 provider。"])
      lines.join("\n")
    end

    def render_blocked_copy(document)
      lines = [
        "# Adapter 运行时就绪声明未通过，dispatch 路径已阻断",
        "",
        "运行时证据审核已完成，但至少一项声明不符合要求。PMind 预演没有访问运行环境、凭据或 provider。",
        "",
        "## 阻断原因",
        ""
      ]
      CONFIGURATION_FIELDS.select { |field| document[field] == "incompatible" }.each do |field|
        lines << "- 运行配置不兼容：#{CONFIGURATION_COPY.fetch(field)}"
      end
      lines << "- 凭据引用、范围或有效期声明未就绪" if document["credential_readiness"] == "blocked"
      lines << "- provider 健康证据声明未就绪" if document["provider_health_readiness"] == "blocked"
      LIFECYCLE_FIELDS.select { |field| document[field] == "incompatible" }.each do |field|
        lines << "- 数据生命周期不兼容：#{LIFECYCLE_COPY.fetch(field)}"
      end
      append_dispatch_gates(lines, document)
      lines.concat(["", "请修复运行配置或独立证据并重建本 Attestation；当前不得建立 Dispatch Proposal 或执行任何 effect。"])
      lines.join("\n")
    end

    def append_effects(lines, document)
      lines.concat(["", "## 已声明就绪但仍不可执行的副作用", ""])
      if document["authorized_effects"].empty?
        lines << "- 零副作用集合：运行时声明就绪；仍不可执行"
      else
        document["authorized_effects"].each do |effect|
          lines << "- #{HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)}：实现、授权和运行配置声明已齐；仍不可执行"
        end
      end
    end

    def append_dispatch_gates(lines, document)
      lines.concat(["", "## 仍未满足的 dispatch 门禁", ""])
      lines << "- 凭据与 provider 健康：仅验证提交声明，PMind 未独立访问或探测"
      lines << "- 费用上限授权：仍待独立确认" if document["dispatch_cost_gate_status"] == "pending_authorization"
      lines << "- Adapter Dispatch Proposal：必需且尚未建立"
      lines << "- 独立 dispatch confirmation：必需且尚未取得"
      lines << "- 当前 effects executable：否"
      lines << "- 当前 dispatch：未授权"
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 16
    warn "Usage: ruby scripts/preview_handoff_adapter_runtime_readiness_attestation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterRuntimeReadinessAttestationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
