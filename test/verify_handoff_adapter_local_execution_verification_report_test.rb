# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../scripts/create_handoff_adapter_local_execution_verification_report"
require_relative "../scripts/execute_handoff_adapter_local_reference"
require_relative "../scripts/verify_handoff_adapter_local_execution_verification_report"
require_relative "support/handoff_adapter_chain_fixture"

class VerifyHandoffAdapterLocalExecutionVerificationReportTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXECUTION_TIME = Time.iso8601("2026-08-23T10:30:00+08:00")
  VERIFICATION_TIME = Time.iso8601("2026-08-23T18:45:00+08:00")

  def test_valid_persisted_report_is_verified_without_writes
    with_persisted_report do |paths, execution_root, audit_root, creator|
      before = tree_snapshot(paths, execution_root, audit_root)
      verifier = report_verifier
      copy = verifier.verify_files(*paths, execution_root, creator.report_path)

      assert copy, verifier.errors.join("\n")
      assert_includes copy, "Execution Verification Report 已独立验证"
      assert_includes copy, "没有修改证据或重新执行 dispatch"
      assert_includes copy, "未证明：provider 交付、生产就绪、校准结果或产品效果"
      refute_includes copy, creator.report["execution_verification_report_id"]
      refute_includes copy, creator.report["execution_receipt_file_sha256"]
      assert_equal creator.report, verifier.report
      assert_equal File.realpath(creator.report_path), verifier.report_path
      assert_equal before, tree_snapshot(paths, execution_root, audit_root)
    end
  end

  def test_equivalent_yaml_formatting_remains_valid
    with_persisted_report do |paths, execution_root, _audit_root, creator|
      File.open(creator.report_path, "ab") { |file| file.write("# equivalent formatting\n") }
      verifier = report_verifier
      assert verifier.verify_files(*paths, execution_root, creator.report_path), verifier.errors.join("\n")
    end
  end

  def test_semantic_report_drift_is_rejected_without_repair
    with_persisted_report do |paths, execution_root, _audit_root, creator|
      mutate_yaml(creator.report_path) do |document|
        document["source_session_file_sha256"] = Digest::SHA256.hexdigest("different source")
      end
      corrupted = File.binread(creator.report_path)
      verifier = report_verifier
      refute verifier.verify_files(*paths, execution_root, creator.report_path)
      assert_includes verifier.errors.join("\n"), "does not match the exact audited evidence"
      assert_equal corrupted, File.binread(creator.report_path)
    end
  end

  def test_report_time_cannot_predate_execution
    with_persisted_report do |paths, execution_root, _audit_root, creator|
      mutate_yaml(creator.report_path) do |document|
        document["verified_at"] = (EXECUTION_TIME - 1).iso8601(6)
      end
      verifier = report_verifier
      refute verifier.verify_files(*paths, execution_root, creator.report_path)
      assert_includes verifier.errors.join("\n"), "cannot predate the persisted Execution Receipt"
    end
  end

  def test_source_bundle_or_receipt_drift_invalidates_report
    [0, 18].each do |index|
      with_persisted_report do |paths, execution_root, _audit_root, creator|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }
        verifier = report_verifier
        refute verifier.verify_files(*paths, execution_root, creator.report_path)
      end
    end

    with_persisted_report do |paths, execution_root, _audit_root, creator|
      bundle = File.join(execution_root, load_yaml(paths.fetch(18))["dispatch_destination_ref"])
      File.open(File.join(bundle, "delivered-envelope.yaml"), "ab") { |file| file.write("# bundle drift\n") }
      verifier = report_verifier
      refute verifier.verify_files(*paths, execution_root, creator.report_path)
    end
  end

  def test_report_filename_must_match_deterministic_identity
    with_persisted_report do |paths, execution_root, audit_root, creator|
      wrong_path = File.join(audit_root, "wrong-verification-report.yaml")
      FileUtils.copy_file(creator.report_path, wrong_path)
      File.chmod(0o600, wrong_path)
      verifier = report_verifier
      refute verifier.verify_files(*paths, execution_root, wrong_path)
      assert_includes verifier.errors.join("\n"), "filename does not match its deterministic identity"
    end
  end

  def test_report_must_be_a_regular_non_symlink_0600_file
    with_persisted_report do |paths, execution_root, audit_root, creator|
      File.chmod(0o644, creator.report_path)
      verifier = report_verifier
      refute verifier.verify_files(*paths, execution_root, creator.report_path)
      assert_includes verifier.errors.join("\n"), "regular non-symlink 0600 file"

      File.chmod(0o600, creator.report_path)
      link_path = File.join(audit_root, "report-link.yaml")
      File.symlink(creator.report_path, link_path)
      refute verifier.verify_files(*paths, execution_root, link_path)
      assert_includes verifier.errors.join("\n"), "regular non-symlink 0600 file"
    end
  end

  def test_report_parent_must_be_non_symlink_and_isolated
    with_persisted_report do |paths, execution_root, audit_root, creator|
      parent_link = File.join(File.dirname(audit_root), "audit-link")
      File.symlink(audit_root, parent_link)
      linked_report = File.join(parent_link, File.basename(creator.report_path))
      verifier = report_verifier
      refute verifier.verify_files(*paths, execution_root, linked_report)
      assert_includes verifier.errors.join("\n"), "parent must be an existing non-symlink directory"

      nested_parent = File.join(execution_root, "audit")
      Dir.mkdir(nested_parent, 0o700)
      nested_report = File.join(nested_parent, File.basename(creator.report_path))
      FileUtils.copy_file(creator.report_path, nested_report)
      File.chmod(0o600, nested_report)
      refute verifier.verify_files(*paths, execution_root, nested_report)
      assert_includes verifier.errors.join("\n"), "parent must be isolated"

      missing = File.join(File.dirname(audit_root), "missing", "report.yaml")
      refute verifier.verify_files(*paths, execution_root, missing)
      assert_includes verifier.errors.join("\n"), "Verification Report is unavailable"
    end
  end

  def test_cli_verifies_report_without_writing_or_leaking_evidence
    with_persisted_report do |paths, execution_root, audit_root, creator|
      before = tree_snapshot(paths, execution_root, audit_root)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/verify_handoff_adapter_local_execution_verification_report.rb"),
        *paths,
        execution_root,
        creator.report_path,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "Execution Verification Report 已独立验证"
      assert_equal "", stderr
      refute_includes stdout, execution_root
      refute_includes stdout, audit_root
      refute_match(/[a-f0-9]{64}/, stdout)
      assert_equal before, tree_snapshot(paths, execution_root, audit_root)
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/verify_handoff_adapter_local_execution_verification_report.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_persisted_report
    Dir.mktmpdir("pmind-persisted-verification-report") do |directory|
      chain = File.join(directory, "chain")
      execution_root = File.join(directory, "execution")
      audit_root = File.join(directory, "audit")
      Dir.mkdir(chain)
      Dir.mkdir(execution_root, 0o700)
      Dir.mkdir(audit_root, 0o700)
      paths = chain_fixture.write_nineteen_files(chain)
      executor = PMind::HandoffAdapterLocalReferenceExecutor.new(ROOT, clock: -> { EXECUTION_TIME })
      raise executor.errors.join("\n") unless executor.execute_files(*paths, execution_root)
      creator = PMind::HandoffAdapterLocalExecutionVerificationReportCreator.new(
        ROOT,
        clock: -> { VERIFICATION_TIME }
      )
      raise creator.errors.join("\n") unless creator.create_files(*paths, execution_root, audit_root)

      yield paths, execution_root, audit_root, creator
    end
  end

  def report_verifier
    PMind::HandoffAdapterLocalExecutionVerificationReportVerifier.new(ROOT)
  end

  def tree_snapshot(paths, execution_root, audit_root)
    targets = paths + [execution_root, audit_root] +
      Dir.glob(File.join(execution_root, "**", "*"), File::FNM_DOTMATCH) +
      Dir.glob(File.join(audit_root, "**", "*"), File::FNM_DOTMATCH)
    targets.reject! { |path| [".", ".."].include?(File.basename(path)) }
    targets.uniq.sort.to_h do |path|
      stat = File.lstat(path)
      content = stat.file? && !stat.symlink? ? File.binread(path) : nil
      [path, [stat.ftype, stat.mode & 0o777, stat.mtime.to_f, content]]
    end
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    write_yaml(path, document)
    File.chmod(0o600, path)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def write_yaml(path, document)
    chain_fixture.write_yaml(path, document)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
