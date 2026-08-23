# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../scripts/execute_handoff_adapter_local_reference"
require_relative "../scripts/verify_handoff_adapter_local_execution_receipt"
require_relative "support/handoff_adapter_chain_fixture"

class VerifyHandoffAdapterLocalExecutionReceiptTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXECUTION_TIME = Time.iso8601("2026-08-23T10:30:00+08:00")

  def test_valid_persisted_bundle_is_verified_without_reexecution
    with_persisted_bundle do |paths, execution_root, executor|
      before = tree_snapshot(paths, execution_root)
      verifier = receipt_verifier
      copy = verifier.verify_files(*paths, execution_root)

      assert copy, verifier.errors.join("\n")
      assert_includes copy, "Execution Receipt 已独立验证"
      assert_includes copy, "本次只读审计没有再次请求或执行 dispatch"
      assert_includes copy, "未证明：provider 交付、生产就绪、校准结果或产品效果"
      refute_includes copy, verifier.receipt["dispatch_destination_ref"]
      refute_includes copy, verifier.receipt["idempotency_key_sha256"]
      assert_equal executor.receipt, verifier.receipt
      assert_equal executor.bundle_path, verifier.bundle_path
      assert_equal before, tree_snapshot(paths, execution_root)
    end
  end

  def test_a_valid_historical_receipt_remains_auditable_after_expiry
    with_persisted_bundle do |paths, execution_root, _executor|
      assert Time.now >= Time.iso8601(load_yaml(paths.fetch(17))["expires_at"])
      verifier = receipt_verifier
      assert verifier.verify_files(*paths, execution_root), verifier.errors.join("\n")
      assert_equal EXECUTION_TIME.iso8601, verifier.receipt["executed_at"]
    end
  end

  def test_upstream_or_terminal_source_drift_invalidates_persisted_receipt
    [0, 7, 17, 18].each do |index|
      with_persisted_bundle do |paths, execution_root, _executor|
        File.open(paths.fetch(index), "ab") { |file| file.write("# post-execution drift\n") }
        verifier = receipt_verifier
        refute verifier.verify_files(*paths, execution_root)
      end
    end
  end

  def test_payload_and_receipt_drift_are_rejected_without_repair
    with_persisted_bundle do |paths, execution_root, executor|
      payload = File.join(executor.bundle_path, "delivered-envelope.yaml")
      File.open(payload, "ab") { |file| file.write("# corruption\n") }
      corrupted = File.binread(payload)
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "does not match the exact dispatch"
      assert_equal corrupted, File.binread(payload)
    end

    with_persisted_bundle do |paths, execution_root, executor|
      receipt = File.join(executor.bundle_path, "execution-receipt.yaml")
      mutate_yaml(receipt) { |document| document["provider_called"] = true }
      corrupted = File.binread(receipt)
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert verifier.errors.any? { |error| error.include?("provider_called") }, verifier.errors.join("\n")
      assert_equal corrupted, File.binread(receipt)
    end
  end

  def test_execution_time_must_have_been_inside_original_confirmed_window
    with_persisted_bundle do |paths, execution_root, executor|
      receipt = File.join(executor.bundle_path, "execution-receipt.yaml")
      mutate_yaml(receipt) { |document| document["executed_at"] = "2026-08-23T10:45:00+08:00" }
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "outside the exact confirmed dispatch window"
    end

    with_persisted_bundle do |paths, execution_root, executor|
      receipt = File.join(executor.bundle_path, "execution-receipt.yaml")
      mutate_yaml(receipt) { |document| document["executed_at"] = "2026-08-23T10:29:59+08:00" }
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "cannot predate the exact Execution Preflight"
    end
  end

  def test_inventory_permissions_and_symlinks_are_rejected
    with_persisted_bundle do |paths, execution_root, executor|
      File.open(File.join(executor.bundle_path, "unexpected.txt"), "wb") { |file| file.write("unexpected\n") }
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "missing or unexpected entries"
    end

    with_persisted_bundle do |paths, execution_root, executor|
      File.chmod(0o755, executor.bundle_path)
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "permissions are not 0700"
    end

    with_persisted_bundle do |paths, execution_root, executor|
      payload = File.join(executor.bundle_path, "delivered-envelope.yaml")
      File.delete(payload)
      File.symlink(paths.fetch(7), payload)
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "regular 0600 files"
    end
  end

  def test_missing_file_or_non_bundle_destination_is_rejected
    with_persisted_bundle do |paths, execution_root, executor|
      File.delete(File.join(executor.bundle_path, "execution-receipt.yaml"))
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "missing or unexpected entries"
    end

    with_chain_without_execution do |paths, execution_root|
      destination = load_yaml(paths.fetch(18))["dispatch_destination_ref"]
      File.open(File.join(execution_root, destination), "wb") { |file| file.write("not a bundle\n") }
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, execution_root)
      assert_includes verifier.errors.join("\n"), "not an immutable bundle directory"
    end
  end

  def test_execution_root_must_exist_be_non_symlink_and_isolated
    Dir.mktmpdir("pmind-receipt-root") do |directory|
      chain = File.join(directory, "chain")
      real_root = File.join(directory, "real-root")
      link_root = File.join(directory, "link-root")
      Dir.mkdir(chain)
      Dir.mkdir(real_root)
      paths = chain_fixture.write_nineteen_files(chain)
      File.symlink(real_root, link_root)
      verifier = receipt_verifier
      refute verifier.verify_files(*paths, link_root)
      assert_includes verifier.errors.join("\n"), "non-symlink directory"

      refute verifier.verify_files(*paths, directory)
      assert_includes verifier.errors.join("\n"), "isolated from the repository and all source files"

      refute verifier.verify_files(*paths, File.join(directory, "missing"))
      assert_includes verifier.errors.join("\n"), "Execution root is unavailable"
    end
  end

  def test_cli_verifies_historical_bundle_without_writing
    with_persisted_bundle do |paths, execution_root, _executor|
      before = tree_snapshot(paths, execution_root)
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/verify_handoff_adapter_local_execution_receipt.rb"),
        *paths,
        execution_root,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "Execution Receipt 已独立验证"
      assert_equal "", stderr
      assert_equal before, tree_snapshot(paths, execution_root)
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/verify_handoff_adapter_local_execution_receipt.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_persisted_bundle
    with_chain_without_execution do |paths, execution_root|
      executor = PMind::HandoffAdapterLocalReferenceExecutor.new(ROOT, clock: -> { EXECUTION_TIME })
      raise executor.errors.join("\n") unless executor.execute_files(*paths, execution_root)

      yield paths, execution_root, executor
    end
  end

  def with_chain_without_execution
    Dir.mktmpdir("pmind-local-receipt-verification") do |directory|
      chain = File.join(directory, "chain")
      execution_root = File.join(directory, "execution-root")
      Dir.mkdir(chain)
      Dir.mkdir(execution_root, 0o700)
      yield chain_fixture.write_nineteen_files(chain), execution_root
    end
  end

  def receipt_verifier
    PMind::HandoffAdapterLocalExecutionReceiptVerifier.new(ROOT)
  end

  def tree_snapshot(paths, execution_root)
    targets = paths + Dir.glob(File.join(execution_root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
      [".", ".."].include?(File.basename(path))
    end
    targets.sort.to_h do |path|
      stat = File.lstat(path)
      content = stat.file? && !stat.symlink? ? File.binread(path) : nil
      [path, [stat.ftype, stat.mode & 0o777, stat.mtime.to_f, content]]
    end
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
