# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_dispatch_execution_preflight"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterDispatchExecutionPreflightTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DIGEST_FIELDS = %w[
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

  def test_ready_preflight_is_submitted_evidence_not_execution
    with_nineteen_files do |paths|
      preview = preflight_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Service preflight 声明已通过，仍未执行"
      assert_includes copy, "PMind 只读预演没有访问环境或凭据"
      assert_includes copy, "幂等可用性门禁：提交声明通过；尚未预留"
      assert_includes copy, "effects executable：否"
      assert_equal "ready", preview.execution_preflight["overall_execution_preflight"]
      assert_equal false, preview.execution_preflight["idempotency_reserved"]
    end
  end

  def test_not_before_and_expiry_are_derived_as_validity_blockers
    with_nineteen_files do |paths|
      mutate_yaml(paths.fetch(16)) do |proposal|
        proposal["not_before"] = "2026-08-23T10:35:00+08:00"
        proposal["idempotency_key_sha256"] = PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(proposal)
      end
      chain_fixture.refresh_adapter_dispatch_confirmation_bindings(paths)
      chain_fixture.refresh_adapter_dispatch_execution_preflight_bindings(paths)
      set_blocked(paths, "proposal_not_yet_valid") { |document| document["validity_check"] = "blocked" }
      preview = preflight_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "尚未进入 Proposal 有效窗口"
    end

    with_nineteen_files do |paths|
      set_blocked(paths, "proposal_expired") do |document|
        document["checked_at"] = "2026-08-23T10:45:00+08:00"
        document["validity_check"] = "blocked"
      end
      preview = preflight_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "Proposal 已过期"
    end
  end

  def test_preflight_cannot_predate_confirmation
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["checked_at"] = "2026-08-23T10:19:59+08:00" }
      assert_invalid(paths, "cannot predate Dispatch Confirmation")
    end
  end

  def test_required_credential_check_can_pass_or_create_canonical_blocker
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["external_service_write"])
      preview = preflight_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal "passed", preview.execution_preflight["credential_check"]
    end
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["external_service_write"])
      set_blocked(paths, "credential_not_ready") { |document| document["credential_check"] = "blocked" }
      preview = preflight_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "凭据引用声明不再就绪"
    end
  end

  def test_credential_requirement_cannot_be_downgraded_or_invented
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["external_service_write"])
      mutate_preflight(paths) { |document| document["credential_check"] = "not_required" }
      assert_invalid(paths, "credential_check must match")
    end
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["credential_check"] = "passed" }
      assert_invalid(paths, "credential_check must match")
    end
  end

  def test_required_provider_health_pass_needs_current_submitted_evidence
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      preview = preflight_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal "passed", preview.execution_preflight["provider_health_check"]
    end
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      mutate_preflight(paths) { |document| document["provider_health_checked_at"] = "2026-08-23T08:00:00+08:00" }
      assert_invalid(paths, "requires current submitted evidence")
    end
  end

  def test_provider_health_can_create_a_valid_blocked_result
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      set_blocked(paths, "provider_health_not_current") { |document| document["provider_health_check"] = "blocked" }
      preview = preflight_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "provider 健康证据不再新鲜"
    end
  end

  def test_non_required_provider_health_evidence_must_be_not_applicable
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["provider_health_evidence_ref"] = "invented-health" }
      assert_invalid(paths, "non-required provider health evidence must be not_applicable")
    end
  end

  def test_destination_idempotency_and_effect_scope_failures_are_canonical_blockers
    {
      "destination_check" => "delivery_failure",
      "idempotency_check" => "idempotency_conflict",
      "effect_scope_check" => "unlisted_effect_requested"
    }.each do |field, condition|
      with_nineteen_files do |paths|
        set_blocked(paths, condition) { |document| document[field] = "blocked" }
        preview = preflight_preview
        assert preview.preview_files(*paths), "#{field}: #{preview.errors.join("\n")}"
        assert_equal [condition], preview.execution_preflight["active_stop_conditions"]
      end
    end
  end

  def test_fixed_point_cost_budget_is_compared_without_float
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      preview = preflight_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal "passed", preview.execution_preflight["cost_budget_check"]
    end
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      set_blocked(paths, "cost_ceiling_would_be_exceeded") do |document|
        document["estimated_cost_amount"] = "10.0001"
        document["cost_budget_check"] = "blocked"
      end
      preview = preflight_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "可能超过费用上限"
    end
  end

  def test_cost_budget_state_currency_and_number_form_cannot_be_forged
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      mutate_preflight(paths) { |document| document["cost_budget_check"] = "blocked" }
      assert_invalid(paths, "cost_budget_check must be derived")
    end
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      mutate_preflight(paths) { |document| document["estimated_cost_currency"] = "EUR" }
      assert_invalid(paths, "requires an estimate in the confirmed ceiling currency")
    end
    with_nineteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      mutate_preflight(paths) { |document| document["estimated_cost_amount"] = "1e3" }
      assert_invalid(paths, "estimated_cost_amount")
    end
  end

  def test_no_cost_preflight_requires_not_applicable_budget_fields
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["estimated_cost_amount"] = "0" }
      assert_invalid(paths, "no-cost preflight budget fields")
    end
  end

  def test_active_conditions_and_overall_results_are_derived
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["active_stop_conditions"] = ["delivery_failure"] }
      assert_invalid(paths, "active_stop_conditions must be the canonical")
    end
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["overall_execution_preflight"] = "blocked" }
      assert_invalid(paths, "overall_execution_preflight must be derived")
    end
    with_nineteen_files do |paths|
      mutate_preflight(paths) { |document| document["service_execution_gate_status"] = "blocked" }
      assert_invalid(paths, "service_execution_gate_status must be derived")
    end
  end

  def test_ready_requires_future_reservation_and_execution_receipt
    %w[execution_attempt_reservation_required execution_receipt_required].each do |field|
      with_nineteen_files do |paths|
        mutate_preflight(paths) { |document| document[field] = false }
        assert_invalid(paths, "#{field} must be true only for ready")
      end
    end
  end

  def test_blocked_result_terminates_future_execution_gates
    %w[execution_attempt_reservation_required execution_receipt_required].each do |field|
      with_nineteen_files do |paths|
        set_blocked(paths, "delivery_failure") { |document| document["destination_check"] = "blocked" }
        mutate_preflight(paths) { |document| document[field] = true }
        assert_invalid(paths, "#{field} must be true only for ready")
      end
    end
  end

  def test_non_confirmed_receipt_cannot_enter_preflight
    with_nineteen_files do |paths|
      mutate_yaml(paths.fetch(17)) do |receipt|
        receipt["confirmation_decision"] = "rejected"
        receipt["dispatch_authorized"] = false
        receipt["service_execution_request_required"] = false
        receipt["execution_receipt_required"] = false
        receipt["cost_limit_authorized"] = false
      end
      assert_invalid(paths, "requires a confirmed authorized Dispatch Receipt")
    end
  end

  def test_every_source_file_drift_invalidates_preflight
    18.times do |index|
      with_nineteen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }
        preview = preflight_preview
        refute preview.preview_files(*paths), "source #{index} unexpectedly accepted"
      end
    end
  end

  def test_every_declared_source_digest_is_checked
    DIGEST_FIELDS.each do |field|
      with_nineteen_files do |paths|
        mutate_preflight(paths) { |document| document[field] = "f" * 64 }
        assert_invalid(paths, field)
      end
    end
  end

  def test_exact_identity_and_dispatch_bindings_cannot_drift
    {
      "package_id" => "pkg-20260823-999",
      "adapter_dispatch_confirmation_id" => "adapter-dispatch-confirmation-20260823-999",
      "dispatch_destination_ref" => "different-destination",
      "idempotency_key_sha256" => "c" * 64,
      "authorized_effects" => [],
      "cost_ceiling_amount" => "1.00"
    }.each do |field, value|
      with_nineteen_files do |paths|
        mutate_preflight(paths) { |document| document[field] = value }
        assert_invalid(paths, field)
      end
    end
  end

  def test_review_provenance_must_be_concrete
    %w[reviewer_ref evidence_ref].each do |field|
      with_nineteen_files do |paths|
        mutate_preflight(paths) { |document| document[field] = "not_applicable" }
        assert_invalid(paths, "#{field} must identify")
      end
    end
  end

  def test_all_preview_execution_and_external_result_fields_stay_false
    fields = %w[
      runtime_environment_accessed_by_preview credential_accessed_by_preview
      provider_health_check_executed_by_preview destination_check_executed_by_preview
      idempotency_reserved effects_executable adapter_started provider_called
      dispatch_attempted delivery_receipt_present external_write_performed cost_incurred
      high_risk_authorization_inferred contains_personal_data contains_secrets
      credential_material_in_preflight
    ]
    fields.each do |field|
      with_nineteen_files do |paths|
        mutate_preflight(paths) { |document| document[field] = true }
        assert_invalid(paths, field)
      end
    end
  end

  def test_preflight_cannot_downgrade_receipt_classification
    with_nineteen_files(envelope_classification: "internal") do |paths|
      mutate_preflight(paths) { |document| document["data_classification"] = "public" }
      assert_invalid(paths, "data classification cannot downgrade")
    end
  end

  def test_malformed_preflight_is_rejected_without_echoing_source_content
    with_nineteen_files do |paths|
      File.open(paths.fetch(18), "wb") { |file| file.write("active_stop_conditions: [unterminated\n") }
      preview = preflight_preview
      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_copy_is_markdown_safe_and_hides_refs_digests_ids_and_source_content
    with_nineteen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_preflight_</script>" }
      rebuild_after_profile_change(paths)
      preview = preflight_preview
      copy = preview.preview_files(*paths)
      document = preview.execution_preflight

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_preflight\\_&lt;/script&gt;"
      paths.each { |path| refute_includes copy, path }
      %w[dispatch_destination_ref idempotency_key_sha256 reviewer_ref evidence_ref evidence_sha256 adapter_dispatch_execution_preflight_id].each do |field|
        refute_includes copy, document[field]
      end
      DIGEST_FIELDS.each { |field| refute_includes copy, document[field] }
      refute_includes copy, load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_preview_exposes_digest_of_exact_preflight_bytes_loaded
    with_nineteen_files do |paths|
      File.open(paths.fetch(18), "ab") { |file| file.write("# equivalent preflight YAML\n") }
      preview = preflight_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(18)).hexdigest, preview.execution_preflight_file_sha256
    end
  end

  def test_cli_reads_all_nineteen_inputs_without_writing
    with_nineteen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_dispatch_execution_preflight.rb"),
        *paths,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "Service preflight 声明已通过，仍未执行"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_dispatch_execution_preflight.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_nineteen_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-adapter-dispatch-preflight") do |directory|
      yield chain_fixture.write_nineteen_files(directory, envelope_classification: envelope_classification)
    end
  end

  def set_blocked(paths, condition)
    mutate_preflight(paths) do |document|
      yield document
      document["active_stop_conditions"] = [condition]
      document["overall_execution_preflight"] = "blocked"
      document["service_execution_gate_status"] = "blocked"
      document["execution_attempt_reservation_required"] = false
      document["execution_receipt_required"] = false
    end
  end

  def set_profile_effects(paths, true_effects)
    mutate_yaml(paths.fetch(8)) do |profile|
      PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.each do |effect|
        profile.dig("effects")[effect] = true_effects.include?(effect)
      end
      profile.dig("authorization_requirements")["required_effect_authorizations"] = true_effects.dup
      cost_present = true_effects.include?("cost_incurred")
      profile.dig("cost_policy")["can_incur_cost"] = cost_present
      profile.dig("cost_policy")["disclosure_required_before_dispatch"] = cost_present
    end
    rebuild_after_profile_change(paths)
  end

  def rebuild_after_profile_change(paths)
    chain_fixture.refresh_profile_digest(paths)
    chain_fixture.refresh_selection_confirmation_bindings(paths)
    chain_fixture.refresh_payload_data_attestation_bindings(paths)
    chain_fixture.refresh_adapter_effect_authorization_proposal_bindings(paths)
    effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |effect|
      load_yaml(paths.fetch(8)).dig("effects", effect) == true
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

  def mutate_preflight(paths, &block)
    mutate_yaml(paths.fetch(18), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = preflight_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def preflight_preview
    PMind::HandoffAdapterDispatchExecutionPreflightPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
