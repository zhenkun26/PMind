# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_implementation_attestation"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterImplementationAttestationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DIGEST_FIELDS = %w[
    source_session_file_sha256
    draft_package_file_sha256
    compilation_proposal_file_sha256
    compilation_confirmation_receipt_file_sha256
    final_package_file_sha256
    handoff_proposal_file_sha256
    handoff_confirmation_receipt_file_sha256
    handoff_envelope_file_sha256
    adapter_profile_file_sha256
    adapter_selection_proposal_file_sha256
    adapter_selection_confirmation_receipt_file_sha256
    payload_data_attestation_file_sha256
    adapter_effect_authorization_proposal_file_sha256
    adapter_effect_authorization_confirmation_receipt_file_sha256
  ].freeze
  COVERAGE_FIELDS = PMind::HandoffAdapterImplementationAttestationPreview::COVERAGE_FIELDS

  def test_compatible_attestation_is_read_only_evidence_not_runtime_readiness
    with_fifteen_files do |paths|
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Adapter 实现声明符合 Profile，仍未达到运行时就绪"
      assert_includes copy, "PMind 预演没有装载实现，也没有运行该测试套件"
      assert_includes copy, "本地文件写入：实现声明符合且已具名授权；仍不可执行"
      assert_includes copy, "provider 凭据：未核验"
      assert_includes copy, "当前 dispatch：未授权"
    end
  end

  def test_zero_effect_implementation_can_be_compatible_but_not_executable
    with_fifteen_files do |paths|
      set_profile_effects(paths, [])
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "零副作用集合：符合；仍不可执行"
      assert_equal "compatible", preview.implementation_attestation["overall_implementation_compatibility"]
    end
  end

  def test_all_known_effects_can_be_attested_without_becoming_executable
    with_fifteen_files do |paths|
      effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS
      set_profile_effects(paths, effects)
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      effects.each do |effect|
        assert_includes copy, PMind::HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)
      end
      assert_equal false, preview.implementation_attestation["effects_executable"]
      assert_equal false, preview.implementation_attestation["dispatch_authorized"]
    end
  end

  def test_missing_declared_effect_is_a_valid_nonconformant_blocker
    with_fifteen_files do |paths|
      set_observed_effects(paths, [])
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "实现声明不符合要求，运行时路径已阻断"
      assert_includes copy, "缺少 Profile 声明的具名副作用实现"
      refute_includes copy, "Runtime Readiness Attestation"
    end
  end

  def test_undeclared_known_effect_is_a_valid_nonconformant_blocker
    with_fifteen_files do |paths|
      set_observed_effects(paths, %w[local_file_write network_access])
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "发现 Profile 未声明的实现副作用"
      assert_equal ["network_access"], preview.implementation_attestation["undeclared_effects_detected"]
    end
  end

  def test_other_effect_is_a_valid_nonconformant_blocker
    with_fifteen_files do |paths|
      set_observed_effects(paths, %w[local_file_write other])
      preview = implementation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal ["other"], preview.implementation_attestation["undeclared_effects_detected"]
      assert_equal "incompatible", preview.implementation_attestation["overall_implementation_compatibility"]
    end
  end

  def test_failed_contract_test_is_a_valid_incompatible_attestation
    with_fifteen_files do |paths|
      mutate_attestation(paths) do |document|
        document["contract_test_status"] = "failed"
        document["provider_contract_compatibility"] = "incompatible"
        document["overall_implementation_compatibility"] = "incompatible"
      end
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "provider contract-test 证据声明失败"
    end
  end

  def test_each_incomplete_contract_coverage_is_a_valid_blocker
    COVERAGE_FIELDS.each do |field|
      with_fifteen_files do |paths|
        mutate_attestation(paths) do |document|
          document[field] = false
          document["provider_contract_compatibility"] = "incompatible"
          document["overall_implementation_compatibility"] = "incompatible"
        end
        preview = implementation_preview
        copy = preview.preview_files(*paths)

        assert copy, "#{field}: #{preview.errors.join("\n")}"
        assert_includes copy, PMind::HandoffAdapterImplementationAttestationPreview::COVERAGE_COPY.fetch(field)
      end
    end
  end

  def test_missing_and_undeclared_effect_arrays_are_derived_exactly
    with_fifteen_files do |paths|
      set_observed_effects(paths, [])
      mutate_attestation(paths) { |document| document["missing_declared_effects"] = [] }

      assert_invalid(paths, "missing_declared_effects")
    end
    with_fifteen_files do |paths|
      set_observed_effects(paths, %w[local_file_write network_access])
      mutate_attestation(paths) { |document| document["undeclared_effects_detected"] = [] }

      assert_invalid(paths, "undeclared_effects_detected")
    end
  end

  def test_effect_conformance_is_derived_from_observed_effects
    with_fifteen_files do |paths|
      set_observed_effects(paths, [])
      mutate_attestation(paths) { |document| document["profile_effect_conformance"] = "conformant" }

      assert_invalid(paths, "profile_effect_conformance")
    end
  end

  def test_contract_compatibility_is_derived_from_status_and_all_coverage
    with_fifteen_files do |paths|
      mutate_attestation(paths) do |document|
        document["contract_test_status"] = "failed"
        document["provider_contract_compatibility"] = "compatible"
      end

      assert_invalid(paths, "provider_contract_compatibility")
    end
  end

  def test_overall_compatibility_combines_effect_and_contract_results
    with_fifteen_files do |paths|
      mutate_attestation(paths) { |document| document["overall_implementation_compatibility"] = "incompatible" }

      assert_invalid(paths, "overall_implementation_compatibility")
    end
  end

  def test_observed_effects_require_canonical_order
    with_fifteen_files do |paths|
      mutate_attestation(paths) do |document|
        document["implementation_observed_effects"] = %w[network_access local_file_write]
        document["undeclared_effects_detected"] = ["network_access"]
        document["profile_effect_conformance"] = "nonconformant"
        document["overall_implementation_compatibility"] = "incompatible"
      end

      assert_invalid(paths, "canonical Profile order")
    end
  end

  def test_manual_automated_and_hybrid_review_provenance_are_legal
    variants = {
      "manual" => ["reviewer-001", "not_applicable", "not_applicable"],
      "automated" => ["not_applicable", "scanner-001", "v1.0.0"],
      "hybrid" => ["reviewer-001", "scanner-001", "v1.0.0"]
    }
    variants.each do |method, refs|
      with_fifteen_files do |paths|
        mutate_attestation(paths) do |document|
          document["review_method"] = method
          document["reviewer_ref"], document["scanner_ref"], document["scanner_version"] = refs
        end

        preview = implementation_preview
        assert preview.preview_files(*paths), "#{method}: #{preview.errors.join("\n")}"
      end
    end
  end

  def test_review_provenance_must_match_method
    with_fifteen_files do |paths|
      mutate_attestation(paths) do |document|
        document["review_method"] = "manual"
        document["scanner_ref"] = "scanner-001"
        document["scanner_version"] = "v1.0.0"
      end

      assert_invalid(paths, "review provenance")
    end
  end

  def test_modify_or_reject_effect_receipt_cannot_enter_implementation_attestation
    %w[modify_requested rejected].each do |decision|
      with_fifteen_files do |paths|
        mutate_yaml(paths.fetch(13)) do |receipt|
          receipt["confirmation_decision"] = decision
          receipt["effect_authorization_confirmed"] = false
          receipt["effect_authorizations_granted"] = []
          receipt["all_requested_effects_authorized"] = false
          receipt["cost_effect_authorized"] = false
          receipt["production_data_access_authorized"] = false
          receipt["user_response"] = "请停止当前实现证明。"
          receipt["user_response_sha256"] = Digest::SHA256.hexdigest(receipt["user_response"])
        end

        assert_invalid(paths, "requires confirmed exact effect authorization")
      end
    end
  end

  def test_complete_fourteen_file_authorization_chain_is_replayed
    DIGEST_FIELDS.each_with_index do |field, index|
      with_fifteen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_each_declared_source_digest_must_match_same_replay_inputs
    DIGEST_FIELDS.each do |field|
      with_fifteen_files do |paths|
        mutate_attestation(paths) { |document| document[field] = "0" * 64 }

        assert_invalid(paths, "#{field} does not match its attested source")
      end
    end
  end

  def test_identity_recipient_and_upstream_states_must_match
    replacements = {
      "package_id" => "pkg-20260821-999",
      "envelope_id" => "handoff-envelope-20260821-999",
      "adapter_profile_id" => "adapter-profile-20260822-999",
      "adapter_selection_proposal_id" => "adapter-selection-proposal-20260822-999",
      "adapter_selection_confirmation_id" => "adapter-selection-confirmation-20260822-999",
      "payload_data_attestation_id" => "payload-data-attestation-20260822-999",
      "adapter_effect_authorization_proposal_id" => "adapter-effect-authorization-proposal-20260822-999",
      "adapter_effect_authorization_confirmation_id" => "adapter-effect-authorization-confirmation-20260822-999",
      "envelope_delivery_state" => "delivered",
      "adapter_profile_status" => "draft",
      "adapter_selection_proposal_status" => "confirmed",
      "selection_confirmation_decision" => "rejected",
      "adapter_selected" => false,
      "payload_data_attestation_completed" => false,
      "overall_data_compatibility" => "incompatible",
      "adapter_effect_authorization_proposal_status" => "confirmed",
      "effect_authorization_confirmation_decision" => "rejected",
      "effect_authorization_confirmed" => false,
      "all_requested_effects_authorized" => false,
      "recipient" => "research_agent"
    }
    replacements.each do |field, value|
      with_fifteen_files do |paths|
        mutate_attestation(paths) { |document| document[field] = value }
        preview = implementation_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") }, preview.errors.join("\n")
      end
    end
  end

  def test_profile_declared_and_authorized_effects_must_match_sources
    %w[profile_declared_effects authorized_effects].each do |field|
      with_fifteen_files do |paths|
        mutate_attestation(paths) { |document| document[field] = [] }

        assert_invalid(paths, field)
      end
    end
  end

  def test_runtime_and_authority_gates_cannot_be_bypassed
    false_fields = %w[
      provider_contract_test_executed_by_preview
      implementation_artifact_loaded_by_preview
      provider_credentials_verified
      provider_health_verified
      runtime_readiness_verified
      effects_executable
      dispatch_authorized
      high_risk_authorization_inferred
      attestation_contains_personal_data
      attestation_contains_secrets
      credential_material_in_attestation
    ]
    false_fields.each do |field|
      with_fifteen_files do |paths|
        mutate_attestation(paths) { |document| document[field] = true }

        assert_invalid(paths, field)
      end
    end
  end

  def test_completed_evidence_and_future_gates_remain_required
    true_fields = %w[
      adapter_implementation_attestation_completed
      provider_contract_test_evidence_reviewed
      runtime_readiness_attestation_required
      dispatch_confirmation_required
    ]
    true_fields.each do |field|
      with_fifteen_files do |paths|
        mutate_attestation(paths) { |document| document[field] = false }

        assert_invalid(paths, field)
      end
    end
  end

  def test_retention_export_purpose_gap_cannot_be_overclaimed
    with_fifteen_files do |paths|
      mutate_attestation(paths) { |document| document["retention_export_purpose_compatibility"] = "compatible" }

      assert_invalid(paths, "retention_export_purpose_compatibility")
    end
  end

  def test_attestation_cannot_predate_effect_confirmation
    with_fifteen_files do |paths|
      mutate_attestation(paths) { |document| document["reviewed_at"] = "2026-08-22T20:19:59+08:00" }

      assert_invalid(paths, "cannot predate effect authorization confirmation")
    end
  end

  def test_attestation_cannot_downgrade_source_classification
    with_fifteen_files do |paths|
      mutate_yaml(paths.fetch(13)) { |receipt| receipt["data_classification"] = "internal" }
      chain_fixture.refresh_adapter_implementation_attestation_bindings(paths)
      mutate_attestation(paths) { |document| document["data_classification"] = "public" }

      assert_invalid(paths, "data classification cannot downgrade its source")
    end
  end

  def test_malformed_attestation_is_rejected_without_echoing_source_content
    with_fifteen_files do |paths|
      File.open(paths.fetch(14), "wb") { |file| file.write("review_method: [unterminated\n") }
      preview = implementation_preview

      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_success_copy_is_markdown_safe
    with_fifteen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_adapter_</script>" }
      rebuild_after_profile_change(paths)
      preview = implementation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_adapter\\_&lt;/script&gt;"
    end
  end

  def test_success_copy_hides_paths_digests_ids_source_content_and_provenance
    with_fifteen_files do |paths|
      preview = implementation_preview
      copy = preview.preview_files(*paths)
      document = load_yaml(paths.fetch(14))

      assert copy, preview.errors.join("\n")
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
      refute_includes copy, document["implementation_ref"]
      refute_includes copy, document["reviewer_ref"]
      refute_includes copy, document["adapter_implementation_attestation_id"]
      DIGEST_FIELDS.each { |field| refute_includes copy, document[field] }
    end
  end

  def test_preview_exposes_digest_of_exact_attestation_bytes_loaded
    with_fifteen_files do |paths|
      File.open(paths.fetch(14), "ab") { |file| file.write("# equivalent attestation YAML\n") }
      preview = implementation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(14)).hexdigest, preview.implementation_attestation_file_sha256
    end
  end

  def test_cli_reads_all_fifteen_inputs_without_writing
    with_fifteen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_implementation_attestation.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Adapter 实现声明符合 Profile，仍未达到运行时就绪"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_implementation_attestation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_fifteen_files
    Dir.mktmpdir("pmind-adapter-implementation-attestation") do |directory|
      yield chain_fixture.write_fifteen_files(directory)
    end
  end

  def set_profile_effects(paths, true_effects)
    mutate_yaml(paths.fetch(8)) do |profile|
      PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.each do |effect|
        profile.dig("effects")[effect] = true_effects.include?(effect)
      end
      profile.dig("authorization_requirements")["required_effect_authorizations"] = true_effects
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
      proposal["requested_effect_authorizations"] = effects
      cost_present = effects.include?("cost_incurred")
      proposal["cost_effect_present"] = cost_present
      proposal["cost_disclosure_required"] = cost_present
      proposal["cost_estimate_status"] = cost_present ? "not_estimated" : "not_applicable"
      proposal["production_data_access_disclosure_required"] = effects.include?("production_data_access")
    end
    chain_fixture.refresh_effect_authorization_confirmation_bindings(paths)
    mutate_yaml(paths.fetch(13)) do |receipt|
      receipt["effect_authorizations_granted"] = effects
      receipt["cost_effect_authorized"] = effects.include?("cost_incurred")
      receipt["production_data_access_authorized"] = effects.include?("production_data_access")
    end
    chain_fixture.refresh_adapter_implementation_attestation_bindings(paths)
  end

  def set_observed_effects(paths, effects)
    declared = load_yaml(paths.fetch(14))["profile_declared_effects"]
    missing = declared.reject { |effect| effects.include?(effect) }
    undeclared = effects.reject { |effect| declared.include?(effect) }
    conformant = missing.empty? && undeclared.empty?
    mutate_attestation(paths) do |document|
      document["implementation_observed_effects"] = effects
      document["missing_declared_effects"] = missing
      document["undeclared_effects_detected"] = undeclared
      document["profile_effect_conformance"] = conformant ? "conformant" : "nonconformant"
      document["overall_implementation_compatibility"] = conformant ? "compatible" : "incompatible"
    end
  end

  def mutate_attestation(paths, &block)
    mutate_yaml(paths.fetch(14), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = implementation_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def implementation_preview
    PMind::HandoffAdapterImplementationAttestationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
