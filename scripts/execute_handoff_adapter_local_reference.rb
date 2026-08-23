#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require "time"
require "yaml"
require_relative "verify_handoff_adapter_local_execution_receipt"

module PMind
  class HandoffAdapterLocalReferenceExecutor
    include HandoffAdapterLocalExecutionContract

    PAYLOAD_NAME = HandoffAdapterLocalExecutionContract::PAYLOAD_NAME
    RECEIPT_NAME = HandoffAdapterLocalExecutionContract::RECEIPT_NAME
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
      return nil unless validate_local_scope(preview)

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

    def validate_current_window(preview, now)
      validate_execution_time(preview, now)
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
      generated = build_local_receipt(preview, now, payload_bytes)
      return nil unless validate_local_receipt_schema(generated, "generated-local-execution-receipt")

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

    def validate_existing_bundle(_preview, paths)
      verifier = HandoffAdapterLocalExecutionReceiptVerifier.new(@root)
      copy = verifier.verify_files(*paths, File.dirname(bundle_path))
      errors.concat(verifier.errors)
      return nil unless copy && verifier.bundle_path == bundle_path

      @receipt = verifier.receipt
      @replayed = true
      render_copy(true)
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
