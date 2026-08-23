# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_runtime_readiness_attestation"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterRuntimeReadinessAttestationTest < Minitest::Test
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
  ].freeze
  CONFIGURATION_FIELDS = PMind::HandoffAdapterRuntimeReadinessAttestationPreview::CONFIGURATION_FIELDS
  LIFECYCLE_FIELDS = PMind::HandoffAdapterRuntimeReadinessAttestationPreview::LIFECYCLE_FIELDS

  def test_ready_attestation_is_a_reviewed_declaration_not_dispatch_authority
    with_sixteen_files do |paths|
      preview = runtime_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Adapter 运行时就绪声明已通过，仍未授权 dispatch"
      assert_includes copy, "PMind 预演没有访问运行环境或凭据，也没有执行 provider 健康检查"
      assert_includes copy, "本地文件写入：实现、授权和运行配置声明已齐；仍不可执行"
      assert_includes copy, "Adapter Dispatch Proposal：必需且尚未建立"
      assert_includes copy, "当前 dispatch：未授权"
    end
  end

  def test_every_configuration_dimension_can_create_a_valid_blocker
    CONFIGURATION_FIELDS.each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) do |document|
          document[field] = "incompatible"
          document["runtime_configuration_compatibility"] = "incompatible"
          document["overall_runtime_readiness"] = "blocked"
        end
        preview = runtime_preview
        copy = preview.preview_files(*paths)

        assert copy, "#{field}: #{preview.errors.join("\n")}"
        assert_includes copy, "运行时就绪声明未通过"
        assert_includes copy, PMind::HandoffAdapterRuntimeReadinessAttestationPreview::CONFIGURATION_COPY.fetch(field)
      end
    end
  end

  def test_configuration_and_overall_results_must_be_derived
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["runtime_configuration_compatibility"] = "incompatible" }
      assert_invalid(paths, "runtime_configuration_compatibility must be derived")
    end
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["overall_runtime_readiness"] = "blocked" }
      assert_invalid(paths, "overall_runtime_readiness must combine")
    end
  end

  def test_required_credential_evidence_can_be_ready_or_a_valid_blocker
    with_sixteen_files do |paths|
      set_required_credentials(paths)
      preview = runtime_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "凭据引用证据：声明就绪"
    end

    %w[missing expired unknown incompatible].each do |condition|
      with_sixteen_files do |paths|
        set_required_credentials(paths)
        mutate_runtime(paths) do |document|
          case condition
          when "missing"
            document["credential_reference_status"] = "missing"
          when "expired", "unknown"
            document["credential_expiry_status"] = condition
          when "incompatible"
            document["credential_scope_compatibility"] = "incompatible"
          end
          document["credential_readiness"] = "blocked"
          document["overall_runtime_readiness"] = "blocked"
        end
        preview = runtime_preview
        copy = preview.preview_files(*paths)
        assert copy, "#{condition}: #{preview.errors.join("\n")}"
        assert_includes copy, "凭据引用、范围或有效期声明未就绪"
      end
    end
  end

  def test_credential_state_matrix_and_remote_effect_requirement_cannot_be_bypassed
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["credential_ref"] = "synthetic-ref" }
      assert_invalid(paths, "not-required credential evidence must be entirely not_applicable")
    end
    with_sixteen_files do |paths|
      set_profile_effects(paths, ["external_service_write"])
      mutate_runtime(paths) do |document|
        document["credential_requirement"] = "not_required"
        document["credential_reference_status"] = "not_applicable"
        document["credential_ref"] = "not_applicable"
        document["credential_scope_compatibility"] = "not_applicable"
        document["credential_expiry_status"] = "not_applicable"
        document["credential_readiness"] = "not_applicable"
      end
      assert_invalid(paths, "require credential evidence")
    end
  end

  def test_required_health_evidence_can_be_ready_or_a_valid_blocker
    with_sixteen_files do |paths|
      set_required_health(paths)
      preview = runtime_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      assert_includes copy, "provider 健康证据：声明健康"
    end

    %w[unhealthy unknown].each do |status|
      with_sixteen_files do |paths|
        set_required_health(paths)
        mutate_runtime(paths) do |document|
          document["provider_health_evidence_status"] = status
          document["provider_health_readiness"] = "blocked"
          document["overall_runtime_readiness"] = "blocked"
        end
        preview = runtime_preview
        copy = preview.preview_files(*paths)
        assert copy, preview.errors.join("\n")
        assert_includes copy, "provider 健康证据声明未就绪"
      end
    end
  end

  def test_health_state_matrix_and_network_effect_requirement_cannot_be_bypassed
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["provider_health_evidence_ref"] = "synthetic-health" }
      assert_invalid(paths, "not-required provider-health evidence must be entirely not_applicable")
    end
    with_sixteen_files do |paths|
      set_profile_effects(paths, ["network_access"])
      mutate_runtime(paths) do |document|
        document["provider_health_check_requirement"] = "not_required"
        document["provider_health_evidence_status"] = "not_applicable"
        document["provider_health_evidence_ref"] = "not_applicable"
        document["provider_health_evidence_sha256"] = "not_applicable"
        document["provider_health_checked_at"] = "not_applicable"
        document["provider_health_readiness"] = "not_applicable"
      end
      assert_invalid(paths, "require submitted provider-health evidence")
    end
  end

  def test_each_lifecycle_dimension_can_create_a_valid_blocker
    LIFECYCLE_FIELDS.each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) do |document|
          document[field] = "incompatible"
          document["retention_export_purpose_compatibility"] = "incompatible"
          document["overall_runtime_readiness"] = "blocked"
        end
        preview = runtime_preview
        copy = preview.preview_files(*paths)
        assert copy, preview.errors.join("\n")
        assert_includes copy, PMind::HandoffAdapterRuntimeReadinessAttestationPreview::LIFECYCLE_COPY.fetch(field)
      end
    end
  end

  def test_lifecycle_combination_must_be_derived
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["retention_export_purpose_compatibility"] = "incompatible" }
      assert_invalid(paths, "retention_export_purpose_compatibility must combine")
    end
  end

  def test_cost_effect_preserves_an_independent_pending_cost_gate
    with_sixteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      preview = runtime_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_equal "ready", preview.runtime_attestation["overall_runtime_readiness"]
      assert_equal true, preview.runtime_attestation["cost_limit_authorization_required"]
      assert_equal false, preview.runtime_attestation["cost_limit_authorized"]
      assert_includes copy, "费用上限授权：仍待独立确认"
    end
  end

  def test_cost_gate_must_be_derived_from_exact_effect_set
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["cost_limit_authorization_required"] = true }
      assert_invalid(paths, "cost_limit_authorization_required must be derived")
    end
  end

  def test_manual_automated_and_hybrid_review_provenance_are_legal
    {
      "manual" => ["synthetic-reviewer", "not_applicable", "not_applicable"],
      "automated" => ["not_applicable", "synthetic-scanner", "v1.0"],
      "hybrid" => ["synthetic-reviewer", "synthetic-scanner", "v1.0"]
    }.each do |method, refs|
      with_sixteen_files do |paths|
        mutate_runtime(paths) do |document|
          document["review_method"] = method
          document["reviewer_ref"], document["scanner_ref"], document["scanner_version"] = refs
        end
        preview = runtime_preview
        assert preview.preview_files(*paths), "#{method}: #{preview.errors.join("\n")}"
      end
    end
  end

  def test_review_provenance_must_match_method
    with_sixteen_files do |paths|
      mutate_runtime(paths) do |document|
        document["review_method"] = "automated"
        document["reviewer_ref"] = "synthetic-reviewer"
      end
      assert_invalid(paths, "runtime review provenance must match")
    end
  end

  def test_runtime_and_lifecycle_evidence_references_are_required
    %w[runtime_environment_ref retention_policy_ref export_policy_ref purpose_binding_ref].each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) { |document| document[field] = "not_applicable" }
        assert_invalid(paths, field)
      end
    end
  end

  def test_required_health_timestamp_must_be_iso8601
    with_sixteen_files do |paths|
      set_required_health(paths)
      mutate_runtime(paths) do |document|
        document["provider_health_checked_at"] = "not-a-timestamp"
        document["provider_health_readiness"] = "blocked"
        document["overall_runtime_readiness"] = "blocked"
      end
      assert_invalid(paths, "must be an ISO-8601 timestamp")
    end
  end

  def test_incompatible_implementation_cannot_enter_runtime_readiness
    with_sixteen_files do |paths|
      mutate_yaml(paths.fetch(14)) do |document|
        document["contract_test_status"] = "failed"
        document["provider_contract_compatibility"] = "incompatible"
        document["overall_implementation_compatibility"] = "incompatible"
      end
      assert_invalid(paths, "requires a compatible completed implementation attestation")
    end
  end

  def test_every_source_file_drift_invalidates_the_attestation
    15.times do |index|
      with_sixteen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }
        preview = runtime_preview
        refute preview.preview_files(*paths), "source #{index} unexpectedly accepted"
      end
    end
  end

  def test_every_declared_source_digest_is_checked
    DIGEST_FIELDS.each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) { |document| document[field] = "f" * 64 }
        assert_invalid(paths, field)
      end
    end
  end

  def test_source_identity_state_and_implementation_identity_are_exact
    %w[package_id adapter_profile_id overall_implementation_compatibility implementation_ref authorized_effects].each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) do |document|
          document[field] = field == "authorized_effects" ? [] :
                            field == "overall_implementation_compatibility" ? "incompatible" : "tampered-value"
        end
        assert_invalid(paths, field)
      end
    end
  end

  def test_review_and_health_evidence_time_order_is_enforced
    with_sixteen_files do |paths|
      mutate_runtime(paths) { |document| document["reviewed_at"] = "2026-08-23T08:59:59+08:00" }
      assert_invalid(paths, "cannot predate Implementation Attestation")
    end
    with_sixteen_files do |paths|
      set_required_health(paths)
      mutate_runtime(paths) { |document| document["provider_health_checked_at"] = "2026-08-23T08:59:59+08:00" }
      assert_invalid(paths, "health evidence cannot predate")
    end
    with_sixteen_files do |paths|
      set_required_health(paths)
      mutate_runtime(paths) { |document| document["provider_health_checked_at"] = "2026-08-23T10:00:01+08:00" }
      assert_invalid(paths, "health evidence cannot postdate")
    end
  end

  def test_attestation_cannot_downgrade_source_classification
    with_sixteen_files(envelope_classification: "internal") do |paths|
      mutate_runtime(paths) { |document| document["data_classification"] = "public" }
      assert_invalid(paths, "data classification cannot downgrade")
    end
  end

  def test_runtime_access_execution_authority_and_sensitive_content_stay_false
    fields = %w[
      runtime_environment_accessed_by_preview provider_health_check_executed_by_preview
      credential_accessed_by_preview provider_credentials_verified_by_preview
      provider_health_verified_by_preview effects_executable dispatch_authorized
      high_risk_authorization_inferred attestation_contains_personal_data
      attestation_contains_secrets credential_material_in_attestation
    ]
    fields.each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) { |document| document[field] = true }
        assert_invalid(paths, field)
      end
    end
  end

  def test_dispatch_proposal_and_confirmation_remain_required
    %w[adapter_dispatch_proposal_required dispatch_confirmation_required].each do |field|
      with_sixteen_files do |paths|
        mutate_runtime(paths) { |document| document[field] = false }
        assert_invalid(paths, field)
      end
    end
  end

  def test_malformed_attestation_is_rejected_without_echoing_source_content
    with_sixteen_files do |paths|
      File.open(paths.fetch(15), "wb") { |file| file.write("review_method: [unterminated\n") }
      preview = runtime_preview
      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_copy_is_markdown_safe_and_hides_refs_digests_ids_and_source_content
    with_sixteen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_runtime_</script>" }
      rebuild_after_profile_change(paths)
      preview = runtime_preview
      copy = preview.preview_files(*paths)
      document = load_yaml(paths.fetch(15))

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_runtime\\_&lt;/script&gt;"
      paths.each { |path| refute_includes copy, path }
      %w[runtime_environment_ref credential_ref provider_health_evidence_ref reviewer_ref adapter_runtime_readiness_attestation_id].each do |field|
        refute_includes copy, document[field]
      end
      DIGEST_FIELDS.each { |field| refute_includes copy, document[field] }
      refute_includes copy, load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_preview_exposes_digest_of_exact_attestation_bytes_loaded
    with_sixteen_files do |paths|
      File.open(paths.fetch(15), "ab") { |file| file.write("# equivalent runtime attestation YAML\n") }
      preview = runtime_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(15)).hexdigest, preview.runtime_attestation_file_sha256
    end
  end

  def test_cli_reads_all_sixteen_inputs_without_writing
    with_sixteen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_runtime_readiness_attestation.rb"),
        *paths,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "Adapter 运行时就绪声明已通过，仍未授权 dispatch"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_runtime_readiness_attestation.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_sixteen_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-adapter-runtime-readiness") do |directory|
      yield chain_fixture.write_sixteen_files(directory, envelope_classification: envelope_classification)
    end
  end

  def set_required_credentials(paths)
    mutate_runtime(paths) do |document|
      document["credential_requirement"] = "required"
      document["credential_reference_status"] = "available"
      document["credential_ref"] = "synthetic-secret-manager-ref-001"
      document["credential_scope_compatibility"] = "compatible"
      document["credential_expiry_status"] = "valid"
      document["credential_readiness"] = "ready"
    end
  end

  def set_required_health(paths)
    mutate_runtime(paths) do |document|
      document["provider_health_check_requirement"] = "required"
      document["provider_health_evidence_status"] = "healthy"
      document["provider_health_evidence_ref"] = "synthetic-health-evidence-001"
      document["provider_health_evidence_sha256"] = "c" * 64
      document["provider_health_checked_at"] = "2026-08-23T09:30:00+08:00"
      document["provider_health_readiness"] = "ready"
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
  end

  def mutate_runtime(paths, &block)
    mutate_yaml(paths.fetch(15), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = runtime_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def runtime_preview
    PMind::HandoffAdapterRuntimeReadinessAttestationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
