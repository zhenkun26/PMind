#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "yaml"
require_relative "handoff_adapter_local_execution_verification_report_contract"

module PMind
  class HandoffAdapterLocalExecutionVerificationReportCreator
    include HandoffAdapterLocalExecutionVerificationReportContract

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
      return nil unless validate_report_schema(report, "generated-local-execution-verification-report")

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
