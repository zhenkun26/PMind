#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_dispatch_confirmation"

module PMind
  class HandoffAdapterDispatchExecutionPreflightPreview
    SCHEMA_PATH = "schemas/handoff-adapter-dispatch-execution-preflight-v0.yaml"
    CLASSIFICATION_RANK = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK
    ACTIVE_CONDITION_ORDER = %w[
      proposal_not_yet_valid
      proposal_expired
      idempotency_conflict
      credential_not_ready
      provider_health_not_current
      cost_ceiling_would_be_exceeded
      unlisted_effect_requested
      delivery_failure
    ].freeze

    attr_reader :errors, :envelope, :profile, :runtime_attestation,
                :dispatch_proposal, :dispatch_confirmation, :execution_preflight,
                :input_digests, :execution_preflight_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(*paths)
      errors.clear
      reset_state
      unless paths.length == 19
        errors << "Adapter Dispatch Execution Preflight preview requires exactly nineteen files"
        return nil
      end

      confirmation_preview = HandoffAdapterDispatchConfirmationPreview.new(@root)
      confirmation_copy = confirmation_preview.preview_files(*paths.first(18))
      errors.concat(confirmation_preview.errors)
      return nil unless confirmation_copy

      copy_confirmation_state(confirmation_preview)
      return nil unless validate_confirmed_receipt(paths.fetch(17))

      document, bytes = load_yaml_file_with_bytes(paths.fetch(18))
      return nil unless document

      @execution_preflight = document
      @input_digests = confirmation_preview.input_digests.merge(
        "adapter_dispatch_confirmation_receipt_file_sha256" => confirmation_preview.dispatch_confirmation_file_sha256
      )
      @execution_preflight_file_sha256 = Digest::SHA256.hexdigest(bytes)
      return nil unless validate_schema(document, paths.fetch(18))

      validate_binding(document, paths.fetch(18))
      validate_review_provenance(document, paths.fetch(18))
      validate_checked_time(document, paths.fetch(18))
      validate_requirement_checks(document, paths.fetch(18))
      validate_provider_health(document, paths.fetch(18))
      validate_cost_budget(document, paths.fetch(18))
      validate_derived_result(document, paths.fetch(18))
      validate_data_policy(document, paths.fetch(18))
      return nil unless errors.empty?

      render_copy(document)
    end

    private

    def reset_state
      @envelope = @profile = @runtime_attestation = nil
      @dispatch_proposal = @dispatch_confirmation = @execution_preflight = nil
      @input_digests = @execution_preflight_file_sha256 = nil
    end

    def copy_confirmation_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @runtime_attestation = preview.runtime_attestation
      @dispatch_proposal = preview.dispatch_proposal
      @dispatch_confirmation = preview.dispatch_confirmation
    end

    def validate_confirmed_receipt(path)
      valid = dispatch_confirmation["confirmation_decision"] == "confirmed" &&
              dispatch_confirmation["dispatch_authorized"] == true &&
              dispatch_confirmation["service_execution_request_required"] == true
      return true if valid

      errors << "#{path}: Execution Preflight requires a confirmed authorized Dispatch Receipt"
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
        "adapter_dispatch_proposal_id" => dispatch_proposal["adapter_dispatch_proposal_id"],
        "adapter_dispatch_confirmation_id" => dispatch_confirmation["adapter_dispatch_confirmation_id"],
        "confirmation_decision" => dispatch_confirmation["confirmation_decision"],
        "dispatch_authorized" => dispatch_confirmation["dispatch_authorized"],
        "service_execution_request_required" => dispatch_confirmation["service_execution_request_required"],
        "dispatch_payload_file_sha256" => dispatch_confirmation["dispatch_payload_file_sha256"],
        "dispatch_destination_kind" => dispatch_confirmation["dispatch_destination_kind"],
        "dispatch_destination_ref" => dispatch_confirmation["dispatch_destination_ref"],
        "idempotency_key_sha256" => dispatch_confirmation["idempotency_key_sha256"],
        "not_before" => dispatch_confirmation["not_before"],
        "expires_at" => dispatch_confirmation["expires_at"],
        "authorized_effects" => dispatch_confirmation["authorized_effects"],
        "stop_conditions" => dispatch_confirmation["stop_conditions"],
        "cost_ceiling_required" => dispatch_confirmation["cost_ceiling_required"],
        "cost_ceiling_amount" => dispatch_confirmation["cost_ceiling_amount"],
        "cost_ceiling_currency" => dispatch_confirmation["cost_ceiling_currency"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its confirmed Dispatch Receipt source" unless document[field] == value
      end
    end

    def validate_review_provenance(document, path)
      %w[reviewer_ref evidence_ref].each do |field|
        errors << "#{path}: #{field} must identify submitted preflight evidence" if document[field] == "not_applicable"
      end
    end

    def validate_checked_time(document, path)
      checked = parse_time(document["checked_at"])
      captured = parse_time(dispatch_confirmation["captured_at"])
      return unless checked && captured && checked < captured

      errors << "#{path}: Execution Preflight cannot predate Dispatch Confirmation"
    end

    def validate_requirement_checks(document, path)
      credential_required = runtime_attestation["credential_requirement"] == "required"
      expected_credential = credential_required ? %w[passed blocked] : ["not_required"]
      unless expected_credential.include?(document["credential_check"])
        errors << "#{path}: credential_check must match the confirmed runtime requirement"
      end

      health_required = runtime_attestation["provider_health_check_requirement"] == "required"
      expected_health = health_required ? %w[passed blocked] : ["not_required"]
      unless expected_health.include?(document["provider_health_check"])
        errors << "#{path}: provider_health_check must match the confirmed runtime requirement"
      end
    end

    def validate_provider_health(document, path)
      required = runtime_attestation["provider_health_check_requirement"] == "required"
      unless required
        fields = %w[provider_health_checked_at provider_health_evidence_ref provider_health_evidence_sha256]
        errors << "#{path}: non-required provider health evidence must be not_applicable" unless fields.all? { |field| document[field] == "not_applicable" }
        return
      end

      checked = parse_time(document["checked_at"])
      health_checked = parse_time(document["provider_health_checked_at"])
      concrete = document["provider_health_evidence_ref"] != "not_applicable" &&
                 document["provider_health_evidence_sha256"].match?(/\A[a-f0-9]{64}\z/)
      current = checked && health_checked && health_checked <= checked &&
                (checked - health_checked) <= dispatch_proposal["maximum_health_evidence_age_seconds"]
      if document["provider_health_check"] == "passed" && !(concrete && current)
        errors << "#{path}: passed provider health check requires current submitted evidence"
      end
    end

    def validate_cost_budget(document, path)
      required = dispatch_confirmation["cost_ceiling_required"] == true
      unless required
        values = [document["estimated_cost_amount"], document["estimated_cost_currency"], document["cost_budget_check"]]
        errors << "#{path}: no-cost preflight budget fields must be not_applicable or not_required" unless values == %w[not_applicable not_applicable not_required]
        return
      end

      if document["estimated_cost_amount"] == "not_applicable" ||
         document["estimated_cost_currency"] != dispatch_confirmation["cost_ceiling_currency"]
        errors << "#{path}: cost preflight requires an estimate in the confirmed ceiling currency"
        return
      end

      within = fixed_point_units(document["estimated_cost_amount"]) <=
               fixed_point_units(dispatch_confirmation["cost_ceiling_amount"])
      expected = within ? "passed" : "blocked"
      errors << "#{path}: cost_budget_check must be derived from fixed-point estimate and ceiling" unless document["cost_budget_check"] == expected
    end

    def validate_derived_result(document, path)
      expected_conditions = derived_active_conditions(document)
      unless document["active_stop_conditions"] == expected_conditions
        errors << "#{path}: active_stop_conditions must be the canonical derived blocker set"
      end

      ready = expected_conditions.empty?
      expected_overall = ready ? "ready" : "blocked"
      expected_gate = ready ? "ready_for_service" : "blocked"
      errors << "#{path}: overall_execution_preflight must be derived" unless document["overall_execution_preflight"] == expected_overall
      errors << "#{path}: service_execution_gate_status must be derived" unless document["service_execution_gate_status"] == expected_gate
      %w[execution_attempt_reservation_required execution_receipt_required].each do |field|
        errors << "#{path}: #{field} must be true only for ready" unless document[field] == ready
      end
    end

    def derived_active_conditions(document)
      active = []
      checked = parse_time(document["checked_at"])
      not_before = parse_time(dispatch_confirmation["not_before"])
      expires = parse_time(dispatch_confirmation["expires_at"])
      validity_condition = if checked && not_before && checked < not_before
                             "proposal_not_yet_valid"
                           elsif checked && expires && checked >= expires
                             "proposal_expired"
                           end
      expected_validity = validity_condition ? "blocked" : "passed"
      errors << "validity_check must be derived from checked_at and the exact Proposal window" unless document["validity_check"] == expected_validity
      active << validity_condition if validity_condition
      active << "idempotency_conflict" if document["idempotency_check"] == "blocked"
      active << "credential_not_ready" if document["credential_check"] == "blocked"
      active << "provider_health_not_current" if document["provider_health_check"] == "blocked"
      active << "cost_ceiling_would_be_exceeded" if document["cost_budget_check"] == "blocked"
      active << "unlisted_effect_requested" if document["effect_scope_check"] == "blocked"
      active << "delivery_failure" if document["destination_check"] == "blocked"
      ACTIVE_CONDITION_ORDER.select { |condition| active.include?(condition) }
    end

    def validate_data_policy(document, path)
      source_rank = CLASSIFICATION_RANK[dispatch_confirmation["data_classification"]]
      preflight_rank = CLASSIFICATION_RANK[document["data_classification"]]
      return unless source_rank && preflight_rank && preflight_rank < source_rank

      errors << "#{path}: Execution Preflight data classification cannot downgrade its Receipt"
    end

    def render_copy(document)
      if document["overall_execution_preflight"] == "ready"
        render_ready_copy(document)
      else
        render_blocked_copy(document)
      end
    end

    def render_ready_copy(document)
      [
        "# Adapter dispatch Service preflight 声明已通过，仍未执行",
        "",
        "提交的临执行证据与当前 exact Dispatch Receipt 自洽。PMind 只读预演没有访问环境或凭据、检查 provider/destination、预留幂等键或执行 dispatch。",
        "",
        "- Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "- 有效期门禁：提交声明通过",
        "- 凭据门禁：#{check_copy(document.fetch("credential_check"))}",
        "- provider 健康门禁：#{check_copy(document.fetch("provider_health_check"))}",
        "- destination 门禁：提交声明通过",
        "- 幂等可用性门禁：提交声明通过；尚未预留",
        "- effect scope 门禁：提交声明通过",
        "- 费用预算门禁：#{check_copy(document.fetch("cost_budget_check"))}",
        "",
        "## 仍未发生",
        "",
        "- effects executable：否",
        "- Adapter/provider/dispatch：均未启动或尝试",
        "- delivery receipt、外部写入、费用：均不存在",
        "",
        "下一步必须由受控 Service 原子预留幂等键并创建独立 Execution Receipt。本 preflight 声明不能执行 dispatch。"
      ].join("\n")
    end

    def render_blocked_copy(document)
      lines = [
        "# Adapter dispatch Service preflight 声明未通过，执行已阻断",
        "",
        "提交的临执行证据触发以下强制停止条件：",
        ""
      ]
      document["active_stop_conditions"].each do |condition|
        lines << "- #{HandoffAdapterDispatchProposalPreview::STOP_CONDITION_COPY.fetch(condition)}"
      end
      lines.concat([
                     "",
                     "Adapter 未启动，provider 未调用，幂等键未预留，dispatch 未尝试，也未产生 delivery、外部写入或费用。修复后必须创建新的 exact preflight evidence；不得把 blocked 改写为 ready。"
                   ])
      lines.join("\n")
    end

    def check_copy(value)
      { "passed" => "提交声明通过", "blocked" => "提交声明阻断", "not_required" => "不适用" }.fetch(value)
    end

    def fixed_point_units(value)
      whole, fraction = value.split(".", 2)
      (whole.to_i * 10_000) + fraction.to_s.ljust(4, "0").to_i
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 19
    warn "Usage: ruby scripts/preview_handoff_adapter_dispatch_execution_preflight.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterDispatchExecutionPreflightPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
