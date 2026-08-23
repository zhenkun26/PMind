# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_dispatch_proposal"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterDispatchProposalTest < Minitest::Test
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
  ].freeze

  def test_valid_proposal_is_pending_zero_dispatch_and_asks_for_independent_choice
    with_seventeen_files do |paths|
      preview = dispatch_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Adapter dispatch 提案待确认，尚未调用 provider"
      assert_includes copy, "用户选择：尚未保存"
      assert_includes copy, "本地文件写入：已具名授权；仍不可执行"
      assert_includes copy, "provider 已调用：否"
      assert_includes copy, "dispatch：未授权且未尝试"
      assert_includes copy, "创建独立 Dispatch Confirmation Receipt"
    end
  end

  def test_zero_effect_set_still_requires_dispatch_confirmation
    with_seventeen_files do |paths|
      set_profile_effects(paths, [])
      preview = dispatch_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "零 effect 集合；dispatch 仍需确认"
      assert_equal false, preview.dispatch_proposal["dispatch_authorized"]
    end
  end

  def test_all_effects_have_exact_conditional_stops_and_remain_non_executable
    with_seventeen_files do |paths|
      effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS
      set_profile_effects(paths, effects)
      preview = dispatch_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      effects.each { |effect| assert_includes copy, PMind::HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect) }
      %w[credential_not_ready provider_health_not_current cost_ceiling_would_be_exceeded receipt_failure].each do |condition|
        assert_includes preview.dispatch_proposal["stop_conditions"], condition
      end
      assert_equal false, preview.dispatch_proposal["effects_executable"]
    end
  end

  def test_cost_effect_requires_positive_fixed_point_ceiling_and_pending_authorization
    with_seventeen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      preview = dispatch_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "费用上限：10.00 USD；仍待本次 dispatch 独立确认"
      assert_equal true, preview.dispatch_proposal["cost_ceiling_required"]
      assert_equal "pending_confirmation", preview.dispatch_proposal["cost_limit_authorization_status"]
      assert_equal false, preview.dispatch_proposal["cost_limit_authorized"]
    end
  end

  def test_legal_fixed_point_cost_ceiling_forms_are_accepted_without_float_arithmetic
    %w[0.0001 10 999999999.9999].each do |amount|
      with_seventeen_files do |paths|
        set_profile_effects(paths, ["cost_incurred"])
        mutate_proposal(paths) { |document| document["cost_ceiling_amount"] = amount }
        refresh_key(paths)
        preview = dispatch_preview
        assert preview.preview_files(*paths), "#{amount}: #{preview.errors.join("\n")}"
      end
    end
  end

  def test_invalid_or_missing_cost_ceiling_is_rejected
    %w[0 0.0000 -1 1.00001 1000000000 1e3 not_applicable].each do |amount|
      with_seventeen_files do |paths|
        set_profile_effects(paths, ["cost_incurred"])
        mutate_proposal(paths) { |document| document["cost_ceiling_amount"] = amount }
        preview = dispatch_preview
        refute preview.preview_files(*paths), amount
      end
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["cost_ceiling_required"] = true }
      assert_invalid(paths, "cost_ceiling_required must be derived")
    end
  end

  def test_non_cost_dispatch_requires_all_cost_fields_not_applicable
    %w[cost_ceiling_amount cost_ceiling_currency cost_limit_authorization_status].each do |field|
      with_seventeen_files do |paths|
        mutate_proposal(paths) { |document| document[field] = field == "cost_ceiling_amount" ? "1.00" : field == "cost_ceiling_currency" ? "USD" : "pending_confirmation" }
        refresh_key(paths) if %w[cost_ceiling_amount cost_ceiling_currency].include?(field)
        assert_invalid(paths, "no-cost dispatch ceiling fields must be not_applicable")
      end
    end
  end

  def test_idempotency_key_is_deterministically_bound_to_exact_dispatch
    with_seventeen_files do |paths|
      document = load_yaml(paths.fetch(16))
      assert_equal PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(document), document["idempotency_key_sha256"]
      mutate_proposal(paths) { |proposal| proposal["dispatch_destination_ref"] = "synthetic-other-destination" }
      assert_invalid(paths, "idempotency_key_sha256 must be derived")
    end
  end

  def test_adapter_without_idempotency_support_cannot_enter_proposal
    with_seventeen_files do |paths|
      mutate_yaml(paths.fetch(8)) do |profile|
        profile.dig("capabilities", "idempotency")["supported"] = false
        profile.dig("capabilities", "idempotency")["key_source"] = "not_applicable"
      end
      rebuild_after_profile_change(paths, refresh_dispatch: false)
      assert_invalid(paths, "requires Adapter idempotency support")
    end
  end

  def test_destination_kind_is_derived_and_destination_ref_is_required
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_destination_kind"] = "provider_endpoint" }
      assert_invalid(paths, "dispatch_destination_kind must match")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_destination_ref"] = "not_applicable" }
      assert_invalid(paths, "dispatch_destination_ref must identify")
    end
  end

  def test_bounded_retry_can_choose_a_limit_within_profile_capability
    with_seventeen_files do |paths|
      mutate_yaml(paths.fetch(8)) do |profile|
        profile.dig("capabilities", "retry")["mode"] = "bounded"
        profile.dig("capabilities", "retry")["maximum_attempts"] = 3
      end
      rebuild_after_profile_change(paths)
      mutate_proposal(paths) { |document| document["dispatch_attempt_limit"] = 3 }
      refresh_key(paths)
      preview = dispatch_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
    end
  end

  def test_attempt_limit_cannot_exceed_profile_or_invent_retry
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_attempt_limit"] = 2 }
      refresh_key(paths)
      assert_invalid(paths, "cannot exceed Adapter retry capability")
    end
    with_seventeen_files do |paths|
      mutate_yaml(paths.fetch(8)) do |profile|
        profile.dig("capabilities", "retry")["mode"] = "bounded"
        profile.dig("capabilities", "retry")["maximum_attempts"] = 2
      end
      rebuild_after_profile_change(paths)
      mutate_proposal(paths) { |document| document["dispatch_attempt_limit"] = 3 }
      refresh_key(paths)
      assert_invalid(paths, "cannot exceed Adapter retry capability")
    end
  end

  def test_time_window_is_ordered_and_validity_is_derived
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["proposed_at"] = "2026-08-23T09:59:59+08:00" }
      assert_invalid(paths, "cannot predate Runtime Readiness Attestation")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["not_before"] = "2026-08-23T10:14:59+08:00" }
      assert_invalid(paths, "not_before cannot predate proposed_at")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["not_before"] = "2026-08-23T10:45:00+08:00" }
      assert_invalid(paths, "not_before must predate expires_at")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["validity_seconds"] = 1799 }
      assert_invalid(paths, "validity_seconds must equal")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["expires_at"] = "2026-08-23T10:45:00.500+08:00" }
      assert_invalid(paths, "validity_seconds must equal")
    end
  end

  def test_attempt_timeout_budget_must_fit_inside_available_window
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_timeout_seconds"] = 1801 }
      refresh_key(paths)
      assert_invalid(paths, "attempt budget cannot exceed the available validity window")
    end
  end

  def test_health_evidence_must_be_current_for_network_dispatch
    with_seventeen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      preview = dispatch_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal "current", preview.dispatch_proposal["provider_health_evidence_freshness"]
    end
    with_seventeen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      mutate_proposal(paths) { |document| document["maximum_health_evidence_age_seconds"] = 60 }
      assert_invalid(paths, "provider health evidence must remain current")
    end
    with_seventeen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      mutate_proposal(paths) { |document| document["not_before"] = "2026-08-23T10:31:00+08:00" }
      refresh_key(paths)
      assert_invalid(paths, "provider health evidence must remain current at not_before")
    end
  end

  def test_health_freshness_requirement_cannot_be_downgraded_or_invented
    with_seventeen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      mutate_proposal(paths) { |document| document["provider_health_freshness_requirement"] = "not_required" }
      assert_invalid(paths, "freshness requirement must match")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) do |document|
        document["maximum_health_evidence_age_seconds"] = 60
        document["provider_health_evidence_freshness"] = "current"
      end
      assert_invalid(paths, "non-required provider health freshness must be not_applicable")
    end
  end

  def test_stop_conditions_are_complete_canonical_and_effect_derived
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["stop_conditions"].delete("source_bytes_changed") }
      assert_invalid(paths, "stop_conditions must be the canonical complete set")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["stop_conditions"] << "provider_health_not_current" }
      assert_invalid(paths, "stop_conditions must be the canonical complete set")
    end
  end

  def test_blocked_runtime_cannot_enter_dispatch_proposal
    with_seventeen_files do |paths|
      mutate_yaml(paths.fetch(15)) do |document|
        document["delivery_configuration_compatibility"] = "incompatible"
        document["runtime_configuration_compatibility"] = "incompatible"
        document["overall_runtime_readiness"] = "blocked"
      end
      assert_invalid(paths, "requires a ready completed Runtime Readiness Attestation")
    end
  end

  def test_every_source_file_drift_invalidates_the_proposal
    16.times do |index|
      with_seventeen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }
        preview = dispatch_preview
        refute preview.preview_files(*paths), "source #{index} unexpectedly accepted"
      end
    end
  end

  def test_every_declared_source_digest_is_checked
    DIGEST_FIELDS.each do |field|
      with_seventeen_files do |paths|
        mutate_proposal(paths) { |document| document[field] = "f" * 64 }
        assert_invalid(paths, field)
      end
    end
  end

  def test_source_identity_state_capability_and_runtime_identity_are_exact
    {
      "package_id" => "pkg-20260823-999",
      "adapter_key" => "tampered_adapter",
      "runtime_environment_ref" => "tampered-runtime",
      "delivery_mode" => "remote_api",
      "authorized_effects" => []
    }.each do |field, value|
      with_seventeen_files do |paths|
        mutate_proposal(paths) { |document| document[field] = value }
        assert_invalid(paths, field)
      end
    end
  end

  def test_payload_digest_is_exact_handoff_envelope_digest
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_payload_file_sha256"] = "e" * 64 }
      assert_invalid(paths, "dispatch_payload_file_sha256")
    end
  end

  def test_proposal_cannot_downgrade_runtime_classification
    with_seventeen_files(envelope_classification: "internal") do |paths|
      mutate_proposal(paths) { |document| document["data_classification"] = "public" }
      assert_invalid(paths, "data classification cannot downgrade")
    end
  end

  def test_all_execution_authority_external_effect_and_sensitive_content_fields_stay_false
    fields = %w[
      dispatch_choice_saved dispatch_confirmation_receipt_present
      runtime_environment_accessed_by_preview credential_accessed_by_preview
      provider_health_check_executed_by_preview effects_executable adapter_started
      provider_called dispatch_authorized dispatch_attempted delivery_receipt_present
      external_write_performed cost_incurred high_risk_authorization_inferred
      proposal_contains_personal_data proposal_contains_secrets credential_material_in_proposal
    ]
    fields.each do |field|
      with_seventeen_files do |paths|
        mutate_proposal(paths) { |document| document[field] = true }
        assert_invalid(paths, field)
      end
    end
  end

  def test_dispatch_confirmation_remains_required_and_status_pending
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_confirmation_required"] = false }
      assert_invalid(paths, "dispatch_confirmation_required")
    end
    with_seventeen_files do |paths|
      mutate_proposal(paths) { |document| document["dispatch_proposal_status"] = "confirmed" }
      assert_invalid(paths, "dispatch_proposal_status")
    end
  end

  def test_malformed_proposal_is_rejected_without_echoing_source_content
    with_seventeen_files do |paths|
      File.open(paths.fetch(16), "wb") { |file| file.write("stop_conditions: [unterminated\n") }
      preview = dispatch_preview
      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_copy_is_markdown_safe_and_hides_refs_digests_ids_key_and_source_content
    with_seventeen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_dispatch_</script>" }
      rebuild_after_profile_change(paths)
      preview = dispatch_preview
      copy = preview.preview_files(*paths)
      document = load_yaml(paths.fetch(16))

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_dispatch\\_&lt;/script&gt;"
      paths.each { |path| refute_includes copy, path }
      %w[dispatch_destination_ref implementation_ref runtime_environment_ref adapter_dispatch_proposal_id idempotency_key_sha256].each do |field|
        refute_includes copy, document[field]
      end
      DIGEST_FIELDS.each { |field| refute_includes copy, document[field] }
      refute_includes copy, load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_preview_exposes_digest_of_exact_proposal_bytes_loaded
    with_seventeen_files do |paths|
      File.open(paths.fetch(16), "ab") { |file| file.write("# equivalent Proposal YAML\n") }
      preview = dispatch_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(16)).hexdigest, preview.dispatch_proposal_file_sha256
    end
  end

  def test_cli_reads_all_seventeen_inputs_without_writing
    with_seventeen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_dispatch_proposal.rb"),
        *paths,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "Adapter dispatch 提案待确认，尚未调用 provider"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_dispatch_proposal.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_seventeen_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-adapter-dispatch-proposal") do |directory|
      yield chain_fixture.write_seventeen_files(directory, envelope_classification: envelope_classification)
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

  def rebuild_after_profile_change(paths, refresh_dispatch: true)
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
    chain_fixture.refresh_adapter_dispatch_proposal_bindings(paths) if refresh_dispatch
  end

  def refresh_key(paths)
    mutate_proposal(paths) do |document|
      document["idempotency_key_sha256"] = PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(document)
    end
  end

  def mutate_proposal(paths, &block)
    mutate_yaml(paths.fetch(16), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = dispatch_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def dispatch_preview
    PMind::HandoffAdapterDispatchProposalPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
