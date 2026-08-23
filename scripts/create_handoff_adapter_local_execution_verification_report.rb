#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "verify_handoff_adapter_local_execution_receipt"

module PMind
  class HandoffAdapterLocalExecutionVerificationReportCreator
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

    attr_reader :errors, :report, :report_path

    def initialize(root, clock: -> { Time.now })
      @root = File.realpath(root)
      @clock = clock
      @errors = []
      reset_state
    end

    def create_files(*arguments)
      errors.clear
      reset_state
      unless arguments.length == 21
        errors << "Local Execution Verification Report creation requires exactly nineteen source files, one execution root, and one audit root"
        return nil
      end

      paths = arguments.first(19)
      execution_root = arguments.fetch(19)
      audit_root = arguments.fetch(20)
      verifier = verify_bundle(paths, execution_root)
      return nil unless verifier

      verified_at = current_time
      return nil unless validate_verification_time(verifier.receipt, verified_at)
      root_path = validate_audit_root(audit_root, paths, execution_root)
      return nil unless root_path

      snapshot = evidence_snapshot(paths, verifier.bundle_path)
      @report = build_report(verifier.receipt, snapshot, verified_at)
      return nil unless validate_report_schema(report)

      before_final_verification
      final_verifier = verify_bundle(paths, execution_root)
      return nil unless final_verifier
      unless snapshot == evidence_snapshot(paths, final_verifier.bundle_path)
        errors << "Verification evidence changed before report persistence"
        return nil
      end

      @report_path = File.join(root_path, "#{report.fetch("execution_verification_report_id")}.yaml")
      return nil if path_entry_exists?(report_path) && collision_error

      persist_report(YAML.dump(report))
      render_copy
    rescue SystemCallError, IOError, Psych::Exception, KeyError, ArgumentError => e
      errors << "Local Execution Verification Report creation failed (#{e.message})"
      nil
    end

    private

    def reset_state
      @report = nil
      @report_path = nil
    end

    def verify_bundle(paths, execution_root)
      verifier = HandoffAdapterLocalExecutionReceiptVerifier.new(@root)
      copy = verifier.verify_files(*paths, execution_root)
      errors.concat(verifier.errors)
      copy ? verifier : nil
    end

    def validate_verification_time(receipt, verified_at)
      executed_at = Time.iso8601(receipt.fetch("executed_at"))
      return true if verified_at >= executed_at

      errors << "Verification time cannot predate the persisted Execution Receipt"
      false
    end

    def validate_audit_root(path, source_paths, execution_root)
      stat = File.lstat(path)
      unless stat.directory? && !stat.symlink?
        errors << "Audit root must be an existing non-symlink directory"
        return nil
      end

      real = File.realpath(path)
      execution_real = File.realpath(execution_root)
      unsafe = path_within?(real, @root) || path_within?(@root, real) ||
        path_within?(real, execution_real) || path_within?(execution_real, real) ||
        source_paths.any? { |source_path| path_within?(File.realpath(source_path), real) }
      if unsafe
        errors << "Audit root must be isolated from the repository, source files, and execution root"
        return nil
      end
      unless File.writable?(real)
        errors << "Audit root must be writable"
        return nil
      end
      real
    rescue SystemCallError => e
      errors << "Audit root is unavailable (#{e.message})"
      nil
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

    def validate_report_schema(document)
      validator = EvalValidator.new(@root)
      schema = validator.load_yaml(SCHEMA_PATH)
      unless schema
        errors.concat(validator.errors)
        return false
      end
      validator.validate_document(schema, document, "generated-local-execution-verification-report", schema)
      errors.concat(validator.errors)
      validator.errors.empty?
    end

    def before_final_verification
      nil
    end

    def persist_report(content)
      created = false
      begin
        File.open(report_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          created = true
          file.binmode
          write_report_bytes(file, content)
          file.flush
          file.fsync
        end
        File.chmod(0o600, report_path)
        sync_directory(File.dirname(report_path))
      rescue StandardError
        File.delete(report_path) if created && path_entry_exists?(report_path)
        raise
      end
    end

    def sync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::EINVAL, Errno::EISDIR
      nil
    end

    def write_report_bytes(file, content)
      file.write(content)
    end

    def collision_error
      errors << "Verification Report destination already exists; refusing to overwrite"
      true
    end

    def path_entry_exists?(path)
      File.lstat(path)
      true
    rescue Errno::ENOENT
      false
    end

    def path_within?(candidate, parent)
      candidate == parent || candidate.start_with?("#{parent}#{File::SEPARATOR}")
    end

    def current_time
      value = @clock.call
      value.is_a?(Time) ? value : Time.iso8601(value.to_s)
    end

    def render_copy
      [
        "# 本地 Execution Receipt 审计报告已创建",
        "",
        "exact historical bundle 已通过独立只读核验，并在隔离审计目录中保存一份不可覆盖的本地报告。",
        "",
        "- 本次没有重新执行 dispatch，也没有修改来源或原 bundle",
        "- 未证明：provider 交付、生产就绪、校准结果或产品效果"
      ].join("\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 21
    warn "Usage: ruby scripts/create_handoff_adapter_local_execution_verification_report.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT AUDIT_ROOT"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  creator = PMind::HandoffAdapterLocalExecutionVerificationReportCreator.new(project_root)
  copy = creator.create_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn creator.errors.join("\n")
  exit 1
end
