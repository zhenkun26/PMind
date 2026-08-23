#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "preview_handoff_adapter_dispatch_execution_preflight"

module PMind
  module HandoffAdapterLocalExecutionContract
    SCHEMA_PATH = "schemas/handoff-adapter-local-execution-receipt-v0.yaml"
    PAYLOAD_NAME = "delivered-envelope.yaml"
    RECEIPT_NAME = "execution-receipt.yaml"
    BUNDLE_ENTRIES = [PAYLOAD_NAME, RECEIPT_NAME].freeze
    REQUIRED_EFFECTS = ["local_file_write"].freeze
    SAFE_DESTINATION_REF = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/

    private

    def validate_local_scope(preview)
      preflight = preview.execution_preflight
      profile = preview.profile
      runtime = preview.runtime_attestation
      confirmation = preview.dispatch_confirmation
      checks = {
        "Execution Preflight must be ready at the Service gate" =>
          preflight["overall_execution_preflight"] == "ready" &&
          preflight["service_execution_gate_status"] == "ready_for_service" &&
          preflight["execution_attempt_reservation_required"] == true &&
          preflight["execution_receipt_required"] == true,
        "local reference executor only supports local_file delivery" =>
          profile.dig("capabilities", "delivery_mode") == "local_file" && confirmation["delivery_mode"] == "local_file",
        "local reference executor only supports local_digest receipts" =>
          profile.dig("capabilities", "receipt_mode") == "local_digest" && confirmation["receipt_mode"] == "local_digest",
        "local reference executor only supports local_path destinations" =>
          confirmation["dispatch_destination_kind"] == "local_path",
        "local reference executor requires exactly local_file_write authority" =>
          confirmation["authorized_effects"] == REQUIRED_EFFECTS && preflight["authorized_effects"] == REQUIRED_EFFECTS,
        "local reference executor cannot use credentials" =>
          runtime["credential_requirement"] == "not_required" && preflight["credential_check"] == "not_required",
        "local reference executor cannot require provider health" =>
          runtime["provider_health_check_requirement"] == "not_required" && preflight["provider_health_check"] == "not_required",
        "local reference executor cannot incur cost" =>
          confirmation["cost_ceiling_required"] == false &&
          confirmation["cost_ceiling_amount"] == "not_applicable" &&
          confirmation["cost_ceiling_currency"] == "not_applicable" &&
          preflight["cost_budget_check"] == "not_required",
        "local reference destination ref must be one safe path segment" =>
          safe_destination_ref?(confirmation["dispatch_destination_ref"])
      }
      checks.each { |message, valid| errors << message unless valid }
      errors.empty?
    end

    def safe_destination_ref?(value)
      value.is_a?(String) && value.match?(SAFE_DESTINATION_REF) && value != "." && value != ".."
    end

    def build_local_receipt(preview, executed_at, payload_bytes)
      preflight = preview.execution_preflight
      preview.input_digests.merge(
        "adapter_dispatch_execution_preflight_file_sha256" => preview.execution_preflight_file_sha256,
        "schema_version" => "0.1.0",
        "adapter_execution_receipt_id" => "adapter-execution-receipt-#{preflight.fetch("idempotency_key_sha256")[0, 24]}",
        "executed_at" => executed_at.iso8601,
        "language" => "zh-CN",
        "package_id" => preflight.fetch("package_id"),
        "envelope_id" => preflight.fetch("envelope_id"),
        "adapter_profile_id" => preflight.fetch("adapter_profile_id"),
        "adapter_dispatch_proposal_id" => preflight.fetch("adapter_dispatch_proposal_id"),
        "adapter_dispatch_confirmation_id" => preflight.fetch("adapter_dispatch_confirmation_id"),
        "adapter_dispatch_execution_preflight_id" => preflight.fetch("adapter_dispatch_execution_preflight_id"),
        "execution_mode" => "local_reference",
        "dispatch_destination_kind" => "local_path",
        "dispatch_destination_ref" => preflight.fetch("dispatch_destination_ref"),
        "delivery_mode" => "local_file",
        "receipt_mode" => "local_digest",
        "idempotency_key_sha256" => preflight.fetch("idempotency_key_sha256"),
        "idempotency_status" => "committed",
        "attempt_number" => 1,
        "delivery_artifact_name" => PAYLOAD_NAME,
        "delivery_artifact_file_sha256" => Digest::SHA256.hexdigest(payload_bytes),
        "authorized_effects" => REQUIRED_EFFECTS.dup,
        "executed_effects" => REQUIRED_EFFECTS.dup,
        "execution_outcome" => "succeeded",
        "adapter_started" => true,
        "dispatch_attempted" => true,
        "delivery_receipt_present" => true,
        "local_file_write_performed" => true,
        "external_write_performed" => true,
        "provider_called" => false,
        "credential_accessed" => false,
        "network_accessed" => false,
        "process_started" => false,
        "cost_incurred" => false,
        "cost_amount" => "0",
        "cost_currency" => "not_applicable",
        "high_risk_authorization_inferred" => false,
        "data_classification" => preflight.fetch("data_classification"),
        "contains_personal_data" => false,
        "contains_secrets" => false,
        "credential_material_in_receipt" => false
      )
    end

    def validate_local_receipt_schema(document, path)
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

    def validate_execution_time(preview, time)
      not_before = Time.iso8601(preview.dispatch_confirmation.fetch("not_before"))
      expires_at = Time.iso8601(preview.dispatch_confirmation.fetch("expires_at"))
      unless time >= not_before && time < expires_at
        errors << "Execution time is outside the exact confirmed dispatch window"
        return false
      end

      checked_at = Time.iso8601(preview.execution_preflight.fetch("checked_at"))
      unless time >= checked_at
        errors << "Execution time cannot predate the exact Execution Preflight"
        return false
      end
      true
    rescue ArgumentError
      errors << "Execution timing evidence is not a valid timestamp"
      false
    end

    def path_within?(candidate, parent)
      candidate == parent || candidate.start_with?("#{parent}#{File::SEPARATOR}")
    end
  end

  class HandoffAdapterLocalExecutionReceiptVerifier
    include HandoffAdapterLocalExecutionContract

    attr_reader :errors, :receipt, :bundle_path

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def verify_files(*arguments)
      errors.clear
      reset_state
      unless arguments.length == 20
        errors << "Local Execution Receipt verification requires exactly nineteen source files and one execution root"
        return nil
      end

      paths = arguments.first(19)
      execution_root = arguments.fetch(19)
      preview = HandoffAdapterDispatchExecutionPreflightPreview.new(@root)
      copy = preview.preview_files(*paths)
      errors.concat(preview.errors)
      return nil unless copy
      return nil unless validate_local_scope(preview)

      root_path = validate_execution_root(execution_root, paths)
      return nil unless root_path
      @bundle_path = File.join(root_path, preview.execution_preflight.fetch("dispatch_destination_ref"))
      return nil unless validate_bundle(preview, paths)

      render_copy
    rescue SystemCallError, IOError, Psych::Exception, KeyError, ArgumentError => e
      errors << "Local Execution Receipt verification failed (#{e.message})"
      nil
    end

    private

    def reset_state
      @receipt = nil
      @bundle_path = nil
    end

    def validate_execution_root(path, source_paths)
      stat = File.lstat(path)
      unless stat.directory? && !stat.symlink?
        errors << "Execution root must be an existing non-symlink directory"
        return nil
      end

      real = File.realpath(path)
      if path_within?(real, @root) || path_within?(@root, real) ||
         source_paths.any? { |source_path| path_within?(File.realpath(source_path), real) }
        errors << "Execution root must be isolated from the repository and all source files"
        return nil
      end
      real
    rescue SystemCallError => e
      errors << "Execution root is unavailable (#{e.message})"
      nil
    end

    def validate_bundle(preview, paths)
      unless File.directory?(bundle_path) && !File.lstat(bundle_path).symlink?
        errors << "Existing execution destination is not an immutable bundle directory"
        return false
      end
      unless Dir.children(bundle_path).sort == BUNDLE_ENTRIES.sort
        errors << "Existing execution bundle has missing or unexpected entries"
        return false
      end
      unless (File.stat(bundle_path).mode & 0o777) == 0o700
        errors << "Existing execution bundle permissions are not 0700"
        return false
      end

      payload_path = File.join(bundle_path, PAYLOAD_NAME)
      receipt_path = File.join(bundle_path, RECEIPT_NAME)
      return false unless validate_bundle_file(payload_path) && validate_bundle_file(receipt_path)

      payload_bytes = File.binread(payload_path)
      existing = YAML.safe_load(File.binread(receipt_path), permitted_classes: [], permitted_symbols: [], aliases: false)
      return false unless validate_local_receipt_schema(existing, receipt_path)
      executed_at = Time.iso8601(existing.fetch("executed_at"))
      unless existing == build_local_receipt(preview, executed_at, payload_bytes)
        errors << "Existing execution receipt does not match the exact dispatch"
        return false
      end
      unless payload_bytes == File.binread(paths.fetch(7))
        errors << "Existing delivered Envelope bytes do not match the exact dispatch payload"
        return false
      end
      return false unless validate_execution_time(preview, executed_at)

      @receipt = existing
      true
    end

    def validate_bundle_file(path)
      stat = File.lstat(path)
      valid = stat.file? && !stat.symlink? && (stat.mode & 0o777) == 0o600
      errors << "Execution bundle entries must be regular 0600 files" unless valid
      valid
    rescue SystemCallError => e
      errors << "Execution bundle entry is unavailable (#{e.message})"
      false
    end

    def render_copy
      [
        "# 本地参考 Execution Receipt 已独立验证",
        "",
        "十九文件来源、exact delivered Envelope、Receipt 状态与首次执行窗口一致。本次只读审计没有再次请求或执行 dispatch。",
        "",
        "- 已证明：隔离的 local_file_write 与 committed 本地回执自洽",
        "- 未证明：provider 交付、生产就绪、校准结果或产品效果"
      ].join("\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 20
    warn "Usage: ruby scripts/verify_handoff_adapter_local_execution_receipt.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  verifier = PMind::HandoffAdapterLocalExecutionReceiptVerifier.new(project_root)
  copy = verifier.verify_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn verifier.errors.join("\n")
  exit 1
end
