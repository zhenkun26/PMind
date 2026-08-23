# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "verify_handoff_adapter_local_execution_receipt"

module PMind
  module HandoffAdapterLocalExecutionVerificationReportContract
    SCHEMA_PATH = "schemas/handoff-adapter-local-execution-verification-report-v0.yaml"
    SOURCE_DIGEST_FIELDS = %w[
      source_session_file_sha256 draft_package_file_sha256
      compilation_proposal_file_sha256 compilation_confirmation_receipt_file_sha256
      final_package_file_sha256 handoff_proposal_file_sha256
      handoff_confirmation_receipt_file_sha256 handoff_envelope_file_sha256
      adapter_profile_file_sha256 adapter_selection_proposal_file_sha256
      adapter_selection_confirmation_receipt_file_sha256 payload_data_attestation_file_sha256
      adapter_effect_authorization_proposal_file_sha256
      adapter_effect_authorization_confirmation_receipt_file_sha256
      adapter_implementation_attestation_file_sha256
      adapter_runtime_readiness_attestation_file_sha256
      adapter_dispatch_proposal_file_sha256
      adapter_dispatch_confirmation_receipt_file_sha256
      adapter_dispatch_execution_preflight_file_sha256
    ].freeze

    private

    def validate_verification_time(receipt, verified_at)
      executed_at = Time.iso8601(receipt.fetch("executed_at"))
      return true if verified_at >= executed_at

      errors << "Verification time cannot predate the persisted Execution Receipt"
      false
    end

    def evidence_snapshot(paths, bundle_path)
      source_digests = paths.map { |path| Digest::SHA256.file(path).hexdigest }
      payload_path = File.join(bundle_path, HandoffAdapterLocalExecutionContract::PAYLOAD_NAME)
      receipt_path = File.join(bundle_path, HandoffAdapterLocalExecutionContract::RECEIPT_NAME)
      {
        "source_digests" => source_digests,
        "delivery_artifact_file_sha256" => Digest::SHA256.file(payload_path).hexdigest,
        "execution_receipt_file_sha256" => Digest::SHA256.file(receipt_path).hexdigest
      }
    end

    def build_report(receipt, snapshot, verified_at)
      source_bindings = SOURCE_DIGEST_FIELDS.zip(snapshot.fetch("source_digests")).to_h
      receipt_digest = snapshot.fetch("execution_receipt_file_sha256")
      verified_at_text = verified_at.iso8601(6)
      report_suffix = Digest::SHA256.hexdigest([receipt_digest, verified_at_text].join("\0"))[0, 24]
      source_bindings.merge(
        "schema_version" => "0.1.0",
        "execution_verification_report_id" => "execution-verification-report-#{report_suffix}",
        "verified_at" => verified_at_text,
        "language" => "zh-CN",
        "verifier_name" => "pmind_local_execution_receipt_verifier",
        "verifier_version" => "0.1.0",
        "verification_scope" => "local_reference_bundle",
        "verification_method" => "exact_source_and_bundle_replay",
        "delivery_artifact_file_sha256" => snapshot.fetch("delivery_artifact_file_sha256"),
        "execution_receipt_file_sha256" => receipt_digest,
        "adapter_execution_receipt_id" => receipt.fetch("adapter_execution_receipt_id"),
        "receipt_executed_at" => receipt.fetch("executed_at"),
        "package_id" => receipt.fetch("package_id"),
        "envelope_id" => receipt.fetch("envelope_id"),
        "adapter_profile_id" => receipt.fetch("adapter_profile_id"),
        "adapter_dispatch_proposal_id" => receipt.fetch("adapter_dispatch_proposal_id"),
        "adapter_dispatch_confirmation_id" => receipt.fetch("adapter_dispatch_confirmation_id"),
        "adapter_dispatch_execution_preflight_id" => receipt.fetch("adapter_dispatch_execution_preflight_id"),
        "source_chain_check" => "passed",
        "local_scope_check" => "passed",
        "bundle_inventory_check" => "passed",
        "bundle_permissions_check" => "passed",
        "receipt_schema_check" => "passed",
        "canonical_receipt_check" => "passed",
        "delivered_payload_check" => "passed",
        "execution_window_check" => "passed",
        "verification_time_order_check" => "passed",
        "verification_outcome" => "verified",
        "local_audit_file_write_performed" => true,
        "external_write_performed" => true,
        "original_bundle_modified" => false,
        "source_files_modified" => false,
        "dispatch_reattempted" => false,
        "provider_called" => false,
        "credential_accessed" => false,
        "network_accessed" => false,
        "process_started" => false,
        "cost_incurred" => false,
        "high_risk_authorization_inferred" => false,
        "data_classification" => receipt.fetch("data_classification"),
        "contains_personal_data" => receipt.fetch("contains_personal_data"),
        "contains_secrets" => receipt.fetch("contains_secrets"),
        "credential_material_in_report" => false
      )
    end

    def validate_report_schema(document, path)
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

    def path_within?(candidate, parent)
      candidate == parent || candidate.start_with?("#{parent}#{File::SEPARATOR}")
    end
  end
end
