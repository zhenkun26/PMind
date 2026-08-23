#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require "time"
require "yaml"
require_relative "preview_handoff_adapter_dispatch_execution_preflight"

module PMind
  class HandoffAdapterLocalReferenceExecutor
    SCHEMA_PATH = "schemas/handoff-adapter-local-execution-receipt-v0.yaml"
    PAYLOAD_NAME = "delivered-envelope.yaml"
    RECEIPT_NAME = "execution-receipt.yaml"
    BUNDLE_ENTRIES = [PAYLOAD_NAME, RECEIPT_NAME].freeze
    REQUIRED_EFFECTS = ["local_file_write"].freeze
    SAFE_DESTINATION_REF = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
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
    ].freeze

    attr_reader :errors, :receipt, :bundle_path, :replayed

    def initialize(root, clock: -> { Time.now })
      @root = File.realpath(root)
      @clock = clock
      @errors = []
      reset_state
    end

    def execute_files(*arguments)
      errors.clear
      reset_state
      unless arguments.length == 20
        errors << "Local reference execution requires exactly nineteen source files and one execution root"
        return nil
      end

      paths = arguments.first(19)
      execution_root = arguments.fetch(19)
      preview = HandoffAdapterDispatchExecutionPreflightPreview.new(@root)
      copy = preview.preview_files(*paths)
      errors.concat(preview.errors)
      return nil unless copy
      return nil unless validate_local_contract(preview)

      now = current_time
      return nil unless validate_current_window(preview, now)

      root_path = validate_execution_root(execution_root, paths)
      return nil unless root_path
      return nil unless source_snapshot(preview, paths)

      destination_ref = preview.execution_preflight.fetch("dispatch_destination_ref")
      @bundle_path = File.join(root_path, destination_ref)
      lock_path = File.join(root_path, ".pmind-dispatch-#{Digest::SHA256.hexdigest(destination_ref)}.lock")
      execute_reserved(preview, paths, root_path, lock_path, now)
    rescue SystemCallError, IOError, Psych::Exception => e
      errors << "Local reference execution failed (#{e.message})"
      nil
    end

    private

    def reset_state
      @receipt = nil
      @bundle_path = nil
      @replayed = false
    end

    def validate_local_contract(preview)
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

    def validate_current_window(preview, now)
      not_before = Time.iso8601(preview.dispatch_confirmation.fetch("not_before"))
      expires_at = Time.iso8601(preview.dispatch_confirmation.fetch("expires_at"))
      return true if now >= not_before && now < expires_at

      errors << "Current execution time is outside the exact confirmed dispatch window"
      false
    rescue ArgumentError
      errors << "Confirmed dispatch window is not a valid timestamp"
      false
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
      unless File.writable?(real)
        errors << "Execution root must be writable"
        return nil
      end
      real
    rescue SystemCallError => e
      errors << "Execution root is unavailable (#{e.message})"
      nil
    end

    def path_within?(candidate, parent)
      candidate == parent || candidate.start_with?("#{parent}#{File::SEPARATOR}")
    end

    def source_snapshot(preview, paths)
      expected = SOURCE_DIGEST_FIELDS.map { |field| preview.input_digests.fetch(field) }
      expected << preview.execution_preflight_file_sha256
      actual = paths.map { |path| Digest::SHA256.file(path).hexdigest }
      unless actual == expected
        errors << "Source bytes changed after Execution Preflight replay"
        return nil
      end

      payload_bytes = File.binread(paths.fetch(7))
      unless Digest::SHA256.hexdigest(payload_bytes) == preview.execution_preflight["dispatch_payload_file_sha256"]
        errors << "Exact Handoff Envelope bytes do not match the confirmed dispatch payload"
        return nil
      end
      payload_bytes
    end

    def execute_reserved(preview, paths, root_path, lock_path, now)
      reserved = false
      temporary_path = nil
      begin
        Dir.mkdir(lock_path, 0o700)
        reserved = true
      rescue Errno::EEXIST
        return validate_existing_bundle(preview, paths) if path_entry_exists?(bundle_path)

        errors << "Execution attempt reservation is already held"
        return nil
      end

      return validate_existing_bundle(preview, paths) if path_entry_exists?(bundle_path)

      payload_bytes = source_snapshot(preview, paths)
      return nil unless payload_bytes
      return nil unless validate_current_window(preview, now)

      temporary_path = Dir.mktmpdir(".pmind-execution-", root_path)
      File.chmod(0o700, temporary_path)
      generated = build_receipt(preview, now, payload_bytes)
      return nil unless validate_receipt_schema(generated, "generated-local-execution-receipt")

      write_file(File.join(temporary_path, PAYLOAD_NAME), payload_bytes)
      write_file(File.join(temporary_path, RECEIPT_NAME), YAML.dump(generated))
      sync_directory(temporary_path)
      return nil unless source_snapshot(preview, paths)
      return nil unless validate_current_window(preview, current_time)

      if path_entry_exists?(bundle_path)
        errors << "Execution destination appeared before atomic publish; refusing to overwrite"
        return nil
      end
      File.rename(temporary_path, bundle_path)
      temporary_path = nil
      sync_directory(root_path)
      @receipt = generated
      render_copy(false)
    ensure
      cleanup_temporary(temporary_path, root_path) if temporary_path
      cleanup_lock(lock_path, root_path) if reserved
    end

    def build_receipt(preview, executed_at, payload_bytes)
      preflight = preview.execution_preflight
      receipt = preview.input_digests.merge(
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
      receipt
    end

    def validate_existing_bundle(preview, paths)
      unless File.directory?(bundle_path) && !File.lstat(bundle_path).symlink?
        errors << "Existing execution destination is not an immutable bundle directory"
        return nil
      end
      unless Dir.children(bundle_path).sort == BUNDLE_ENTRIES.sort
        errors << "Existing execution bundle has missing or unexpected entries"
        return nil
      end

      payload_path = File.join(bundle_path, PAYLOAD_NAME)
      receipt_path = File.join(bundle_path, RECEIPT_NAME)
      return nil unless validate_bundle_file(payload_path) && validate_bundle_file(receipt_path)

      existing = YAML.safe_load(File.binread(receipt_path), permitted_classes: [], permitted_symbols: [], aliases: false)
      return nil unless validate_receipt_schema(existing, receipt_path)
      executed_at = Time.iso8601(existing.fetch("executed_at"))
      expected = build_receipt(preview, executed_at, File.binread(payload_path))
      unless existing == expected
        errors << "Existing execution receipt does not match the exact dispatch"
        return nil
      end
      unless File.binread(payload_path) == File.binread(paths.fetch(7))
        errors << "Existing delivered Envelope bytes do not match the exact dispatch payload"
        return nil
      end
      unless time_within_dispatch_window?(preview, executed_at)
        errors << "Existing execution receipt time is outside the confirmed dispatch window"
        return nil
      end
      unless (File.stat(bundle_path).mode & 0o777) == 0o700
        errors << "Existing execution bundle permissions are not 0700"
        return nil
      end

      @receipt = existing
      @replayed = true
      render_copy(true)
    rescue SystemCallError, Psych::Exception, KeyError, ArgumentError => e
      errors << "Existing execution bundle cannot be verified (#{e.message})"
      nil
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

    def validate_receipt_schema(document, path)
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

    def write_file(path, content)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.binmode
        file.write(content)
        file.flush
        file.fsync
      end
    end

    def sync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::EINVAL, Errno::EISDIR
      nil
    end

    def cleanup_temporary(path, root_path)
      return unless File.dirname(path) == root_path && File.basename(path).start_with?(".pmind-execution-")

      FileUtils.remove_entry(path) if path_entry_exists?(path)
    rescue SystemCallError => e
      errors << "Incomplete execution bundle cleanup failed (#{e.message})"
    end

    def cleanup_lock(path, root_path)
      return unless File.dirname(path) == root_path && File.basename(path).start_with?(".pmind-dispatch-")

      Dir.rmdir(path) if File.directory?(path) && !File.lstat(path).symlink?
    rescue SystemCallError => e
      errors << "Execution reservation cleanup failed (#{e.message})"
    end

    def time_within_dispatch_window?(preview, time)
      not_before = Time.iso8601(preview.dispatch_confirmation.fetch("not_before"))
      expires_at = Time.iso8601(preview.dispatch_confirmation.fetch("expires_at"))
      time >= not_before && time < expires_at
    end

    def path_entry_exists?(path)
      File.lstat(path)
      true
    rescue Errno::ENOENT
      false
    end

    def current_time
      value = @clock.call
      value.is_a?(Time) ? value : Time.iso8601(value.to_s)
    end

    def render_copy(is_replay)
      if is_replay
        [
          "# 已验证并复用既有本地参考执行结果",
          "",
          "相同幂等键对应的不可变 bundle 与 exact Envelope 已重新验证；本次没有再次写入或执行。",
          "",
          "- provider、网络、凭据、进程、费用：均未使用",
          "- 生产级 provider dispatch：尚未实现，也未获授权"
        ].join("\n")
      else
        [
          "# 本地参考 dispatch 已原子完成",
          "",
          "exact Handoff Envelope 与不可变 Execution Receipt 已作为一个本地隔离 bundle 发布。",
          "",
          "- 已执行 effect：仅 local_file_write",
          "- provider、网络、凭据、进程、费用：均未使用",
          "- 生产级 provider dispatch：尚未实现，也未获授权"
        ].join("\n")
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 20
    warn "Usage: ruby scripts/execute_handoff_adapter_local_reference.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  executor = PMind::HandoffAdapterLocalReferenceExecutor.new(project_root)
  copy = executor.execute_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn executor.errors.join("\n")
  exit 1
end
