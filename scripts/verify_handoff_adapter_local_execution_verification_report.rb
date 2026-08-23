#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "yaml"
require_relative "handoff_adapter_local_execution_verification_report_contract"

module PMind
  class HandoffAdapterLocalExecutionVerificationReportVerifier
    include HandoffAdapterLocalExecutionVerificationReportContract

    attr_reader :errors, :report, :report_path, :bundle_path

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def verify_files(*arguments)
      errors.clear
      reset_state
      unless arguments.length == 21
        errors << "Local Execution Verification Report verification requires exactly nineteen source files, one execution root, and one report path"
        return nil
      end

      paths = arguments.first(19)
      execution_root = arguments.fetch(19)
      submitted_report_path = arguments.fetch(20)
      receipt_verifier = HandoffAdapterLocalExecutionReceiptVerifier.new(@root)
      copy = receipt_verifier.verify_files(*paths, execution_root)
      errors.concat(receipt_verifier.errors)
      return nil unless copy
      @bundle_path = receipt_verifier.bundle_path

      @report_path = validate_report_path(submitted_report_path, paths, execution_root)
      return nil unless report_path
      document = YAML.safe_load(File.binread(report_path), permitted_classes: [], permitted_symbols: [], aliases: false)
      return nil unless validate_report_schema(document, report_path)

      verified_at = Time.iso8601(document.fetch("verified_at"))
      return nil unless validate_verification_time(receipt_verifier.receipt, verified_at)
      expected = build_report(receipt_verifier.receipt, evidence_snapshot(paths, bundle_path), verified_at)
      unless document == expected
        errors << "Persisted Verification Report does not match the exact audited evidence"
        return nil
      end
      unless File.basename(report_path) == "#{expected.fetch("execution_verification_report_id")}.yaml"
        errors << "Persisted Verification Report filename does not match its deterministic identity"
        return nil
      end

      @report = document
      render_copy
    rescue SystemCallError, IOError, Psych::Exception, KeyError, ArgumentError => e
      errors << "Local Execution Verification Report verification failed (#{e.message})"
      nil
    end

    private

    def reset_state
      @report = nil
      @report_path = nil
      @bundle_path = nil
    end

    def validate_report_path(path, source_paths, execution_root)
      stat = File.lstat(path)
      unless stat.file? && !stat.symlink? && (stat.mode & 0o777) == 0o600
        errors << "Verification Report must be a regular non-symlink 0600 file"
        return nil
      end

      parent = File.dirname(File.expand_path(path))
      parent_stat = File.lstat(parent)
      unless parent_stat.directory? && !parent_stat.symlink?
        errors << "Verification Report parent must be an existing non-symlink directory"
        return nil
      end

      real_parent = File.realpath(parent)
      execution_real = File.realpath(execution_root)
      unsafe = path_within?(real_parent, @root) || path_within?(@root, real_parent) ||
        path_within?(real_parent, execution_real) || path_within?(execution_real, real_parent) ||
        source_paths.any? { |source_path| path_within?(File.realpath(source_path), real_parent) }
      if unsafe
        errors << "Verification Report parent must be isolated from the repository, source files, and execution root"
        return nil
      end
      File.realpath(path)
    rescue SystemCallError => e
      errors << "Verification Report is unavailable (#{e.message})"
      nil
    end

    def render_copy
      [
        "# 本地 Execution Verification Report 已独立验证",
        "",
        "报告、exact historical bundle 与十九文件来源一致。本次只读重放没有修改证据或重新执行 dispatch。",
        "",
        "- 已证明：一份不可变本地报告准确记录了对应审计事件",
        "- 未证明：provider 交付、生产就绪、校准结果或产品效果"
      ].join("\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 21
    warn "Usage: ruby scripts/verify_handoff_adapter_local_execution_verification_report.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml ADAPTER_RUNTIME_READINESS_ATTESTATION.yaml ADAPTER_DISPATCH_PROPOSAL.yaml ADAPTER_DISPATCH_CONFIRMATION.yaml ADAPTER_DISPATCH_EXECUTION_PREFLIGHT.yaml EXECUTION_ROOT VERIFICATION_REPORT.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  verifier = PMind::HandoffAdapterLocalExecutionVerificationReportVerifier.new(project_root)
  copy = verifier.verify_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn verifier.errors.join("\n")
  exit 1
end
