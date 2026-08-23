# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "time"
require_relative "../scripts/execute_handoff_adapter_local_reference"
require_relative "support/handoff_adapter_chain_fixture"

class ExecuteHandoffAdapterLocalReferenceTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FIXED_TIME = Time.iso8601("2026-08-23T10:30:00+08:00")

  def test_ready_local_chain_atomically_publishes_exact_envelope_and_receipt
    with_execution_chain do |paths, execution_root|
      source_before = paths.map { |path| File.binread(path) }
      executor = local_executor
      copy = executor.execute_files(*paths, execution_root)

      assert copy, executor.errors.join("\n")
      assert_includes copy, "本地参考 dispatch 已原子完成"
      assert_includes copy, "仅 local_file_write"
      assert_includes copy, "生产级 provider dispatch：尚未实现，也未获授权"
      refute_includes copy, load_yaml(paths.fetch(18))["dispatch_destination_ref"]
      assert_equal false, executor.replayed
      assert_equal source_before, paths.map { |path| File.binread(path) }

      bundle = executor.bundle_path
      assert_equal %w[delivered-envelope.yaml execution-receipt.yaml], Dir.children(bundle).sort
      assert_equal 0o700, File.stat(bundle).mode & 0o777
      payload_path = File.join(bundle, "delivered-envelope.yaml")
      receipt_path = File.join(bundle, "execution-receipt.yaml")
      assert_equal 0o600, File.stat(payload_path).mode & 0o777
      assert_equal 0o600, File.stat(receipt_path).mode & 0o777
      assert_equal File.binread(paths.fetch(7)), File.binread(payload_path)

      receipt = load_yaml(receipt_path)
      assert_valid_receipt(receipt, receipt_path)
      assert_equal Digest::SHA256.file(paths.fetch(7)).hexdigest, receipt["delivery_artifact_file_sha256"]
      assert_equal Digest::SHA256.file(paths.fetch(18)).hexdigest,
                   receipt["adapter_dispatch_execution_preflight_file_sha256"]
      assert_equal ["local_file_write"], receipt["executed_effects"]
      assert_equal "succeeded", receipt["execution_outcome"]
      assert_equal true, receipt["dispatch_attempted"]
      assert_equal false, receipt["provider_called"]
      assert_equal false, receipt["credential_accessed"]
      assert_equal false, receipt["network_accessed"]
      assert_equal false, receipt["process_started"]
      assert_equal false, receipt["cost_incurred"]
    end
  end

  def test_same_idempotency_key_verifies_and_reuses_without_a_second_write
    with_execution_chain do |paths, execution_root|
      first = local_executor
      assert first.execute_files(*paths, execution_root), first.errors.join("\n")
      snapshot = bundle_snapshot(first.bundle_path)

      no_write_class = Class.new(PMind::HandoffAdapterLocalReferenceExecutor) do
        private

        def write_file(*)
          raise "idempotent replay attempted a write"
        end
      end
      replay = no_write_class.new(ROOT, clock: -> { FIXED_TIME })
      copy = replay.execute_files(*paths, execution_root)

      assert copy, replay.errors.join("\n")
      assert replay.replayed
      assert_includes copy, "已验证并复用既有本地参考执行结果"
      assert_includes copy, "本次没有再次写入或执行"
      assert_equal snapshot, bundle_snapshot(replay.bundle_path)
    end
  end

  def test_expired_or_not_yet_valid_dispatch_never_creates_a_bundle
    [
      Time.iso8601("2026-08-23T10:14:59+08:00"),
      Time.iso8601("2026-08-23T10:45:00+08:00")
    ].each do |clock_time|
      with_execution_chain do |paths, execution_root|
        executor = PMind::HandoffAdapterLocalReferenceExecutor.new(ROOT, clock: -> { clock_time })
        refute executor.execute_files(*paths, execution_root)
        assert_includes executor.errors.join("\n"), "outside the exact confirmed dispatch window"
        assert_empty Dir.children(execution_root)
      end
    end
  end

  def test_execution_cannot_predate_exact_preflight
    with_execution_chain do |paths, execution_root|
      executor = PMind::HandoffAdapterLocalReferenceExecutor.new(
        ROOT,
        clock: -> { Time.iso8601("2026-08-23T10:29:59+08:00") }
      )
      refute executor.execute_files(*paths, execution_root)
      assert_includes executor.errors.join("\n"), "cannot predate the exact Execution Preflight"
      assert_empty Dir.children(execution_root)
    end
  end

  def test_blocked_preflight_never_executes
    with_execution_chain do |paths, execution_root|
      mutate_yaml(paths.fetch(18)) do |preflight|
        preflight["destination_check"] = "blocked"
        preflight["active_stop_conditions"] = ["delivery_failure"]
        preflight["overall_execution_preflight"] = "blocked"
        preflight["service_execution_gate_status"] = "blocked"
        preflight["execution_attempt_reservation_required"] = false
        preflight["execution_receipt_required"] = false
      end
      executor = local_executor
      refute executor.execute_files(*paths, execution_root)
      assert_includes executor.errors.join("\n"), "Execution Preflight must be ready"
      assert_empty Dir.children(execution_root)
    end
  end

  def test_upstream_source_drift_never_executes
    [0, 7, 17].each do |index|
      with_execution_chain do |paths, execution_root|
        File.open(paths.fetch(index), "ab") { |file| file.write("# drift\n") }
        executor = local_executor
        refute executor.execute_files(*paths, execution_root)
        assert_empty Dir.children(execution_root)
      end
    end
  end

  def test_receipt_binds_exact_current_preflight_bytes
    with_execution_chain do |paths, execution_root|
      File.open(paths.fetch(18), "ab") { |file| file.write("# equivalent current preflight YAML\n") }
      executor = local_executor
      assert executor.execute_files(*paths, execution_root), executor.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(18)).hexdigest,
                   executor.receipt["adapter_dispatch_execution_preflight_file_sha256"]
    end
  end

  def test_destination_ref_must_be_one_safe_path_segment
    %w[../escape nested/path .hidden].each do |destination_ref|
      with_execution_chain do |paths, execution_root|
        mutate_yaml(paths.fetch(16)) do |proposal|
          proposal["dispatch_destination_ref"] = destination_ref
          proposal["idempotency_key_sha256"] = PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(proposal)
        end
        chain_fixture.refresh_adapter_dispatch_confirmation_bindings(paths)
        chain_fixture.refresh_adapter_dispatch_execution_preflight_bindings(paths)
        executor = local_executor
        refute executor.execute_files(*paths, execution_root)
        assert_includes executor.errors.join("\n"), "one safe path segment"
        assert_empty Dir.children(execution_root)
      end
    end
  end

  def test_symlink_or_missing_execution_root_is_rejected
    Dir.mktmpdir("pmind-local-root-boundary") do |directory|
      paths = chain_fixture.write_nineteen_files(directory)
      real_root = File.join(directory, "real")
      link_root = File.join(directory, "link")
      Dir.mkdir(real_root)
      File.symlink(real_root, link_root)
      executor = local_executor
      refute executor.execute_files(*paths, link_root)
      assert_includes executor.errors.join("\n"), "non-symlink directory"
      assert_empty Dir.children(real_root)

      missing = File.join(directory, "missing")
      refute executor.execute_files(*paths, missing)
      assert_includes executor.errors.join("\n"), "Execution root is unavailable"
      refute File.exist?(missing)
    end
  end

  def test_execution_root_must_be_isolated_from_sources_and_repository
    Dir.mktmpdir("pmind-local-root-isolation") do |directory|
      chain_directory = File.join(directory, "chain")
      Dir.mkdir(chain_directory)
      paths = chain_fixture.write_nineteen_files(chain_directory)
      executor = local_executor
      refute executor.execute_files(*paths, directory)
      assert_includes executor.errors.join("\n"), "isolated from the repository and all source files"

      refute executor.execute_files(*paths, ROOT)
      assert_includes executor.errors.join("\n"), "isolated from the repository and all source files"
    end
  end

  def test_provider_credential_cost_and_additional_effect_chains_are_rejected
    %w[network_access external_service_write cost_incurred process_start].each do |effect|
      with_execution_chain do |paths, execution_root|
        set_profile_effects(paths, [effect])
        executor = local_executor
        refute executor.execute_files(*paths, execution_root)
        assert executor.errors.any? { |error| error.include?("local reference executor") }, executor.errors.join("\n")
        assert_empty Dir.children(execution_root)
      end
    end
  end

  def test_partial_write_failure_cleans_only_temp_and_lock_entries
    with_execution_chain do |paths, execution_root|
      sentinel = File.join(execution_root, "keep.txt")
      File.open(sentinel, "wb") { |file| file.write("keep\n") }
      failing_class = Class.new(PMind::HandoffAdapterLocalReferenceExecutor) do
        private

        def write_file(path, content)
          @write_count = @write_count.to_i + 1
          raise IOError, "synthetic second write failure" if @write_count == 2

          super
        end
      end
      executor = failing_class.new(ROOT, clock: -> { FIXED_TIME })

      refute executor.execute_files(*paths, execution_root)
      assert_includes executor.errors.join("\n"), "synthetic second write failure"
      assert_equal ["keep.txt"], Dir.children(execution_root)
      assert_equal "keep\n", File.binread(sentinel)
    end
  end

  def test_corrupt_or_incomplete_existing_bundle_is_never_overwritten
    with_execution_chain do |paths, execution_root|
      first = local_executor
      assert first.execute_files(*paths, execution_root), first.errors.join("\n")
      payload = File.join(first.bundle_path, "delivered-envelope.yaml")
      File.open(payload, "ab") { |file| file.write("# corruption\n") }
      corrupted = File.binread(payload)

      replay = local_executor
      refute replay.execute_files(*paths, execution_root)
      assert_includes replay.errors.join("\n"), "does not match the exact dispatch"
      assert_equal corrupted, File.binread(payload)
    end

    with_execution_chain do |paths, execution_root|
      destination = load_yaml(paths.fetch(18))["dispatch_destination_ref"]
      bundle = File.join(execution_root, destination)
      Dir.mkdir(bundle, 0o700)
      executor = local_executor
      refute executor.execute_files(*paths, execution_root)
      assert_includes executor.errors.join("\n"), "missing or unexpected entries"
      assert_empty Dir.children(bundle)
    end
  end

  def test_replay_rejects_receipt_lies_and_unsafe_permissions
    with_execution_chain do |paths, execution_root|
      first = local_executor
      assert first.execute_files(*paths, execution_root), first.errors.join("\n")
      receipt_path = File.join(first.bundle_path, "execution-receipt.yaml")
      mutate_yaml(receipt_path) { |receipt| receipt["provider_called"] = true }
      lying_bytes = File.binread(receipt_path)

      replay = local_executor
      refute replay.execute_files(*paths, execution_root)
      assert replay.errors.any? { |error| error.include?("provider_called") }, replay.errors.join("\n")
      assert_equal lying_bytes, File.binread(receipt_path)
    end

    with_execution_chain do |paths, execution_root|
      first = local_executor
      assert first.execute_files(*paths, execution_root), first.errors.join("\n")
      payload_path = File.join(first.bundle_path, "delivered-envelope.yaml")
      File.chmod(0o644, payload_path)

      replay = local_executor
      refute replay.execute_files(*paths, execution_root)
      assert_includes replay.errors.join("\n"), "regular 0600 files"
      assert_equal 0o644, File.stat(payload_path).mode & 0o777
    end
  end

  def test_existing_destination_file_is_never_overwritten
    with_execution_chain do |paths, execution_root|
      destination = load_yaml(paths.fetch(18))["dispatch_destination_ref"]
      target = File.join(execution_root, destination)
      File.open(target, "wb") { |file| file.write("sentinel\n") }
      executor = local_executor
      refute executor.execute_files(*paths, execution_root)
      assert_includes executor.errors.join("\n"), "not an immutable bundle directory"
      assert_equal "sentinel\n", File.binread(target)
    end
  end

  def test_existing_reservation_stops_without_waiting_or_writing
    with_execution_chain do |paths, execution_root|
      destination = load_yaml(paths.fetch(18))["dispatch_destination_ref"]
      lock = File.join(execution_root, ".pmind-dispatch-#{Digest::SHA256.hexdigest(destination)}.lock")
      Dir.mkdir(lock, 0o700)
      executor = local_executor
      refute executor.execute_files(*paths, execution_root)
      assert_includes executor.errors.join("\n"), "reservation is already held"
      assert_equal [File.basename(lock)], Dir.children(execution_root)
    end
  end

  def test_cli_uses_current_time_and_creates_only_the_isolated_bundle
    with_execution_chain do |paths, execution_root|
      make_window_current(paths)
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/execute_handoff_adapter_local_reference.rb"),
        *paths,
        execution_root,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "本地参考 dispatch 已原子完成"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
      assert_equal 1, Dir.children(execution_root).length
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/execute_handoff_adapter_local_reference.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_execution_chain
    Dir.mktmpdir("pmind-local-reference-execution") do |directory|
      chain_directory = File.join(directory, "chain")
      execution_root = File.join(directory, "execution-root")
      Dir.mkdir(chain_directory)
      Dir.mkdir(execution_root, 0o700)
      yield chain_fixture.write_nineteen_files(chain_directory), execution_root
    end
  end

  def local_executor
    PMind::HandoffAdapterLocalReferenceExecutor.new(ROOT, clock: -> { FIXED_TIME })
  end

  def set_profile_effects(paths, true_effects)
    mutate_yaml(paths.fetch(8)) do |profile|
      PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.each do |effect|
        profile.fetch("effects")[effect] = true_effects.include?(effect)
      end
      profile.fetch("authorization_requirements")["required_effect_authorizations"] = true_effects.dup
      cost_present = true_effects.include?("cost_incurred")
      profile.fetch("cost_policy")["can_incur_cost"] = cost_present
      profile.fetch("cost_policy")["disclosure_required_before_dispatch"] = cost_present
    end
    rebuild_after_profile_change(paths)
  end

  def rebuild_after_profile_change(paths)
    chain_fixture.refresh_profile_digest(paths)
    chain_fixture.refresh_selection_confirmation_bindings(paths)
    chain_fixture.refresh_payload_data_attestation_bindings(paths)
    chain_fixture.refresh_adapter_effect_authorization_proposal_bindings(paths)
    effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |effect|
      load_yaml(paths.fetch(8)).fetch("effects")[effect] == true
    end
    mutate_yaml(paths.fetch(12)) do |proposal|
      proposal["requested_effect_authorizations"] = effects.dup
      cost_present = effects.include?("cost_incurred")
      proposal["cost_effect_present"] = cost_present
      proposal["cost_disclosure_required"] = cost_present
      proposal["cost_estimate_status"] = cost_present ? "not_estimated" : "not_applicable"
      proposal["production_data_access_disclosure_required"] = effects.include?("production_data_access")
    end
    chain_fixture.refresh_effect_authorization_confirmation_bindings(paths)
    mutate_yaml(paths.fetch(13)) do |receipt|
      receipt["effect_authorizations_granted"] = effects.dup
      receipt["cost_effect_authorized"] = effects.include?("cost_incurred")
      receipt["production_data_access_authorized"] = effects.include?("production_data_access")
    end
    chain_fixture.refresh_adapter_implementation_attestation_bindings(paths)
    chain_fixture.refresh_adapter_runtime_readiness_attestation_bindings(paths)
    chain_fixture.refresh_adapter_dispatch_proposal_bindings(paths)
    chain_fixture.refresh_adapter_dispatch_confirmation_bindings(paths)
    chain_fixture.refresh_adapter_dispatch_execution_preflight_bindings(paths)
  end

  def make_window_current(paths)
    now = Time.now
    proposed = now - 60
    not_before = now - 30
    expires_at = now + 600
    mutate_yaml(paths.fetch(16)) do |proposal|
      proposal["proposed_at"] = proposed.iso8601
      proposal["not_before"] = not_before.iso8601
      proposal["expires_at"] = expires_at.iso8601
      proposal["validity_seconds"] = (expires_at - proposed).to_i
      proposal["idempotency_key_sha256"] = PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(proposal)
    end
    chain_fixture.refresh_adapter_dispatch_confirmation_bindings(paths)
    mutate_yaml(paths.fetch(17)) { |confirmation| confirmation["captured_at"] = (now - 20).iso8601 }
    chain_fixture.refresh_adapter_dispatch_execution_preflight_bindings(paths)
    mutate_yaml(paths.fetch(18)) { |preflight| preflight["checked_at"] = (now - 10).iso8601 }
  end

  def assert_valid_receipt(receipt, path)
    validator = PMind::EvalValidator.new(ROOT)
    schema = validator.load_yaml("schemas/handoff-adapter-local-execution-receipt-v0.yaml")
    validator.validate_document(schema, receipt, path, schema)
    assert_empty validator.errors, validator.errors.join("\n")
  end

  def bundle_snapshot(bundle)
    Dir.children(bundle).sort.to_h do |name|
      path = File.join(bundle, name)
      [name, [File.binread(path), File.stat(path).ino, File.stat(path).mtime.to_f]]
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
