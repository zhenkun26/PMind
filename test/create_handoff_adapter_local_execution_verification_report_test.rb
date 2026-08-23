# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../scripts/create_handoff_adapter_local_execution_verification_report"
require_relative "../scripts/execute_handoff_adapter_local_reference"
require_relative "support/handoff_adapter_chain_fixture"

class CreateHandoffAdapterLocalExecutionVerificationReportTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXECUTION_TIME = Time.iso8601("2026-08-23T10:30:00+08:00")
  VERIFICATION_TIME = Time.iso8601("2026-08-23T18:45:00+08:00")

  def test_valid_bundle_creates_one_immutable_schema_valid_report
    with_persisted_bundle do |paths, execution_root, audit_root, executor|
      before = evidence_snapshot(paths, execution_root)
      creator = report_creator
      copy = creator.create_files(*paths, execution_root, audit_root)

      assert copy, creator.errors.join("\n")
      assert_includes copy, "Execution Receipt 审计报告已创建"
      assert_includes copy, "没有重新执行 dispatch"
      assert_includes copy, "未证明：provider 交付、生产就绪、校准结果或产品效果"
      assert_equal before, evidence_snapshot(paths, execution_root)
      created_paths = Dir.children(audit_root).map { |entry| File.realpath(File.join(audit_root, entry)) }
      assert_equal [File.realpath(creator.report_path)], created_paths
      assert_equal 0o600, File.stat(creator.report_path).mode & 0o777
      assert_equal creator.report, load_yaml(creator.report_path)
      assert_equal "verified", creator.report["verification_outcome"]
      assert_equal true, creator.report["local_audit_file_write_performed"]
      assert_equal true, creator.report["external_write_performed"]
      assert_equal false, creator.report["dispatch_reattempted"]
      assert_equal false, creator.report["provider_called"]
      assert_equal executor.receipt["adapter_execution_receipt_id"], creator.report["adapter_execution_receipt_id"]
      assert_equal Digest::SHA256.file(File.join(executor.bundle_path, "execution-receipt.yaml")).hexdigest,
        creator.report["execution_receipt_file_sha256"]
      assert_match(/execution-verification-report-[a-f0-9]{24}\.yaml\z/, creator.report_path)
    end
  end

  def test_report_binds_all_exact_source_and_bundle_bytes
    with_persisted_bundle do |paths, execution_root, audit_root, executor|
      creator = report_creator
      assert creator.create_files(*paths, execution_root, audit_root), creator.errors.join("\n")

      expected_sources = creator.class::SOURCE_DIGEST_FIELDS.zip(paths.map { |path| Digest::SHA256.file(path).hexdigest }).to_h
      expected_sources.each { |field, digest| assert_equal digest, creator.report[field] }
      assert_equal Digest::SHA256.file(File.join(executor.bundle_path, "delivered-envelope.yaml")).hexdigest,
        creator.report["delivery_artifact_file_sha256"]
    end
  end

  def test_verification_time_cannot_predate_receipt
    with_persisted_bundle do |paths, execution_root, audit_root, _executor|
      creator = report_creator(clock: -> { EXECUTION_TIME - 1 })
      refute creator.create_files(*paths, execution_root, audit_root)
      assert_includes creator.errors.join("\n"), "cannot predate the persisted Execution Receipt"
      assert_empty Dir.children(audit_root)
    end
  end

  def test_invalid_or_drifted_bundle_never_creates_a_report
    with_persisted_bundle do |paths, execution_root, audit_root, executor|
      receipt_path = File.join(executor.bundle_path, "execution-receipt.yaml")
      document = load_yaml(receipt_path)
      document["provider_called"] = true
      write_yaml(receipt_path, document)

      creator = report_creator
      refute creator.create_files(*paths, execution_root, audit_root)
      assert_empty Dir.children(audit_root)
    end

    with_persisted_bundle do |paths, execution_root, audit_root, _executor|
      File.open(paths.fetch(18), "ab") { |file| file.write("# drift\n") }
      creator = report_creator
      refute creator.create_files(*paths, execution_root, audit_root)
      assert_empty Dir.children(audit_root)
    end
  end

  def test_evidence_drift_between_replays_is_rejected
    with_persisted_bundle do |paths, execution_root, audit_root, _executor|
      klass = Class.new(PMind::HandoffAdapterLocalExecutionVerificationReportCreator) do
        def initialize(root, drift_path:, **options)
          super(root, **options)
          @drift_path = drift_path
        end

        private

        def before_final_verification
          File.open(@drift_path, "ab") { |file| file.write("# concurrent drift\n") }
        end
      end
      creator = klass.new(ROOT, drift_path: paths.fetch(0), clock: -> { VERIFICATION_TIME })
      refute creator.create_files(*paths, execution_root, audit_root)
      assert_empty Dir.children(audit_root)
    end
  end

  def test_audit_root_must_exist_be_non_symlink_and_isolated
    Dir.mktmpdir("pmind-verification-report-roots") do |directory|
      chain = File.join(directory, "chain")
      execution_root = File.join(directory, "execution")
      audit_root = File.join(directory, "audit")
      audit_link = File.join(directory, "audit-link")
      Dir.mkdir(chain)
      Dir.mkdir(execution_root, 0o700)
      Dir.mkdir(audit_root, 0o700)
      paths = chain_fixture.write_nineteen_files(chain)
      executor = PMind::HandoffAdapterLocalReferenceExecutor.new(ROOT, clock: -> { EXECUTION_TIME })
      assert executor.execute_files(*paths, execution_root), executor.errors.join("\n")
      File.symlink(audit_root, audit_link)

      creator = report_creator
      refute creator.create_files(*paths, execution_root, audit_link)
      assert_includes creator.errors.join("\n"), "non-symlink directory"

      refute creator.create_files(*paths, execution_root, directory)
      assert_includes creator.errors.join("\n"), "isolated from the repository, source files, and execution root"

      refute creator.create_files(*paths, execution_root, execution_root)
      assert_includes creator.errors.join("\n"), "isolated from the repository, source files, and execution root"

      refute creator.create_files(*paths, execution_root, File.join(directory, "missing"))
      assert_includes creator.errors.join("\n"), "Audit root is unavailable"
    end
  end

  def test_same_report_destination_is_never_overwritten
    with_persisted_bundle do |paths, execution_root, audit_root, _executor|
      creator = report_creator
      assert creator.create_files(*paths, execution_root, audit_root), creator.errors.join("\n")
      report_path = creator.report_path
      before = File.binread(report_path)

      second = report_creator
      refute second.create_files(*paths, execution_root, audit_root)
      assert_includes second.errors.join("\n"), "refusing to overwrite"
      assert_equal before, File.binread(report_path)
      assert_equal [File.basename(report_path)], Dir.children(audit_root)
    end
  end

  def test_report_permissions_are_exact_even_under_a_restrictive_umask
    with_persisted_bundle do |paths, execution_root, audit_root, _executor|
      creator = report_creator
      previous_umask = File.umask(0o777)
      begin
        assert creator.create_files(*paths, execution_root, audit_root), creator.errors.join("\n")
      ensure
        File.umask(previous_umask)
      end
      assert_equal 0o600, File.stat(creator.report_path).mode & 0o777
    end
  end

  def test_partial_report_is_removed_after_write_failure
    [IOError.new("injected write failure"), Errno::EINVAL.new("injected invalid write")].each do |failure|
      with_persisted_bundle do |paths, execution_root, audit_root, _executor|
        klass = Class.new(PMind::HandoffAdapterLocalExecutionVerificationReportCreator) do
          def initialize(root, failure:, **options)
            super(root, **options)
            @failure = failure
          end

          private

          def write_report_bytes(file, _content)
            file.write("partial")
            raise @failure
          end
        end
        creator = klass.new(ROOT, failure: failure, clock: -> { VERIFICATION_TIME })
        refute creator.create_files(*paths, execution_root, audit_root)
        assert_includes creator.errors.join("\n"), failure.message
        assert_empty Dir.children(audit_root)
      end
    end
  end

  def test_cli_creates_a_report_with_current_time_and_safe_copy
    with_persisted_bundle do |paths, execution_root, audit_root, _executor|
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/create_handoff_adapter_local_execution_verification_report.rb"),
        *paths,
        execution_root,
        audit_root,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "Execution Receipt 审计报告已创建"
      assert_equal "", stderr
      assert_equal 1, Dir.children(audit_root).length
      refute_includes stdout, execution_root
      refute_includes stdout, audit_root
      refute_match(/[a-f0-9]{64}/, stdout)
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/create_handoff_adapter_local_execution_verification_report.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_persisted_bundle
    Dir.mktmpdir("pmind-verification-report") do |directory|
      chain = File.join(directory, "chain")
      execution_root = File.join(directory, "execution")
      audit_root = File.join(directory, "audit")
      Dir.mkdir(chain)
      Dir.mkdir(execution_root, 0o700)
      Dir.mkdir(audit_root, 0o700)
      paths = chain_fixture.write_nineteen_files(chain)
      executor = PMind::HandoffAdapterLocalReferenceExecutor.new(ROOT, clock: -> { EXECUTION_TIME })
      raise executor.errors.join("\n") unless executor.execute_files(*paths, execution_root)

      yield paths, execution_root, audit_root, executor
    end
  end

  def report_creator(clock: -> { VERIFICATION_TIME })
    PMind::HandoffAdapterLocalExecutionVerificationReportCreator.new(ROOT, clock: clock)
  end

  def evidence_snapshot(paths, execution_root)
    targets = paths + Dir.glob(File.join(execution_root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
      [".", ".."].include?(File.basename(path))
    end
    targets.sort.to_h do |path|
      stat = File.lstat(path)
      content = stat.file? && !stat.symlink? ? File.binread(path) : nil
      [path, [stat.ftype, stat.mode & 0o777, stat.mtime.to_f, content]]
    end
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
