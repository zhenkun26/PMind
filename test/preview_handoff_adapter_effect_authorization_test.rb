# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_effect_authorization"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterEffectAuthorizationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/handoff-adapter-effect-authorization-proposal-valid.yaml")
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
  ].freeze

  def test_single_effect_proposal_is_pending_and_grants_nothing
    with_thirteen_files do |paths|
      preview = effect_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Adapter 副作用授权提案待确认，当前零授权"
      assert_includes copy, "本地文件写入：待单独授权"
      assert_includes copy, "用户选择：尚未记录"
      assert_includes copy, "已授予的副作用授权：无"
      assert_includes copy, "dispatch：未授权"
      assert_includes copy, "独立 Adapter Effect Authorization Confirmation Receipt"
    end
  end

  def test_zero_effect_profile_has_a_legal_acknowledgement_path_but_no_dispatch
    with_thirteen_files do |paths|
      set_profile_effects(paths, [])
      refresh_effect_proposal_bindings(paths)
      mutate_effect_proposal(paths) { |proposal| proposal["requested_effect_authorizations"] = [] }
      preview = effect_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "未声明 true 副作用"
      assert_includes copy, "不能跳过未来 dispatch 确认"
    end
  end

  def test_all_profile_effects_can_be_disclosed_without_authorization
    with_thirteen_files do |paths|
      effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS
      set_profile_effects(paths, effects)
      refresh_effect_proposal_bindings(paths)
      mutate_effect_proposal(paths) do |proposal|
        proposal["requested_effect_authorizations"] = effects
        proposal["cost_effect_present"] = true
        proposal["cost_disclosure_required"] = true
        proposal["cost_estimate_status"] = "not_estimated"
        proposal["production_data_access_disclosure_required"] = true
      end
      preview = effect_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      effects.each { |effect| assert_includes copy, PMind::HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect) }
      assert_includes copy, "可能产生费用；当前未估算"
      assert_includes copy, "会访问生产数据，当前未授权"
    end
  end

  def test_missing_or_extra_requested_effect_is_rejected
    [[], ["local_file_write", "network_access"]].each do |requested|
      with_thirteen_files do |paths|
        mutate_effect_proposal(paths) { |proposal| proposal["requested_effect_authorizations"] = requested }

        assert_invalid(paths, "must exactly match the selected Profile true effects")
      end
    end
  end

  def test_incompatible_attestation_blocks_before_effect_proposal
    with_thirteen_files do |paths|
      mutate_yaml(paths.fetch(11)) do |attestation|
        attestation["payload_contains_personal_data"] = true
        attestation["personal_data_categories"] = ["contact"]
        attestation["data_classification"] = "internal"
        attestation["personal_data_compatibility"] = "incompatible"
        attestation["overall_data_compatibility"] = "incompatible"
      end

      assert_invalid(paths, "requires a compatible completed Payload Data Attestation")
    end
  end

  def test_complete_twelve_file_chain_is_replayed
    DIGEST_FIELDS.each_with_index do |field, index|
      with_thirteen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_each_declared_source_digest_must_match_the_same_replay
    DIGEST_FIELDS.each do |field|
      with_thirteen_files do |paths|
        mutate_effect_proposal(paths) { |proposal| proposal[field] = "0" * 64 }

        assert_invalid(paths, "#{field} does not match its attested source")
      end
    end
  end

  def test_identity_and_state_bindings_must_match
    replacements = {
      "package_id" => "pkg-20260821-999",
      "envelope_id" => "handoff-envelope-20260821-999",
      "adapter_profile_id" => "adapter-profile-20260822-999",
      "adapter_selection_proposal_id" => "adapter-selection-proposal-20260822-999",
      "adapter_selection_confirmation_id" => "adapter-selection-confirmation-20260822-999",
      "payload_data_attestation_id" => "payload-data-attestation-20260822-999",
      "envelope_delivery_state" => "delivered",
      "adapter_profile_status" => "draft",
      "adapter_selection_proposal_status" => "confirmed",
      "selection_confirmation_decision" => "rejected",
      "adapter_selected" => false,
      "payload_data_attestation_completed" => false,
      "overall_data_compatibility" => "incompatible",
      "recipient" => "research_agent"
    }
    replacements.each do |field, value|
      with_thirteen_files do |paths|
        mutate_effect_proposal(paths) { |proposal| proposal[field] = value }
        preview = effect_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") }, preview.errors.join("\n")
      end
    end
  end

  def test_cost_disclosure_must_match_no_cost_profile
    variants = {
      "cost_effect_present" => true,
      "cost_disclosure_required" => true,
      "cost_estimate_status" => "not_estimated"
    }
    variants.each do |field, value|
      with_thirteen_files do |paths|
        mutate_effect_proposal(paths) { |proposal| proposal[field] = value }

        assert_invalid(paths, field)
      end
    end
  end

  def test_cost_effect_requires_explicit_unestimated_disclosure
    with_thirteen_files do |paths|
      set_profile_effects(paths, %w[local_file_write cost_incurred])
      refresh_effect_proposal_bindings(paths)
      mutate_effect_proposal(paths) do |proposal|
        proposal["requested_effect_authorizations"] = %w[local_file_write cost_incurred]
        proposal["cost_effect_present"] = true
        proposal["cost_disclosure_required"] = true
        proposal["cost_estimate_status"] = "not_estimated"
      end

      assert effect_preview.preview_files(*paths)
    end
  end

  def test_selected_profile_cannot_require_cost_disclosure_without_a_cost_effect
    with_thirteen_files do |paths|
      mutate_yaml(paths.fetch(8)) do |profile|
        profile.dig("cost_policy")["disclosure_required_before_dispatch"] = true
      end
      rebuild_after_profile_change(paths)

      assert_invalid(paths, "selected Profile cost disclosure policy must match its cost effect")
    end
  end

  def test_production_data_disclosure_must_match_profile
    with_thirteen_files do |paths|
      set_profile_effects(paths, %w[local_file_write production_data_access])
      refresh_effect_proposal_bindings(paths)
      mutate_effect_proposal(paths) do |proposal|
        proposal["requested_effect_authorizations"] = %w[local_file_write production_data_access]
      end

      assert_invalid(paths, "production_data_access_disclosure_required")
    end
  end

  def test_proposal_never_records_choice_or_grants_effects_dispatch_or_high_risk_authority
    replacements = {
      "proposal_status" => "confirmed",
      "user_choice_status" => "confirmed",
      "effect_authorizations_granted" => ["local_file_write"],
      "dispatch_authorized" => true,
      "external_effects_authorized" => true,
      "high_risk_authorization_inferred" => true
    }
    replacements.each do |field, value|
      with_thirteen_files do |paths|
        mutate_effect_proposal(paths) { |proposal| proposal[field] = value }

        assert_invalid(paths, field)
      end
    end
  end

  def test_proposal_cannot_predate_attestation
    with_thirteen_files do |paths|
      mutate_effect_proposal(paths) { |proposal| proposal["created_at"] = "2026-08-22T18:22:59+08:00" }

      assert_invalid(paths, "cannot predate Payload Data Attestation")
    end
  end

  def test_proposal_cannot_downgrade_attestation_classification
    with_thirteen_files do |paths|
      mutate_yaml(paths.fetch(11)) { |attestation| attestation["data_classification"] = "internal" }
      refresh_effect_proposal_bindings(paths)
      mutate_effect_proposal(paths) { |proposal| proposal["data_classification"] = "public" }

      assert_invalid(paths, "data classification cannot downgrade its source")
    end
  end

  def test_known_retention_export_and_purpose_gap_cannot_be_claimed_as_attested
    with_thirteen_files do |paths|
      mutate_effect_proposal(paths) { |proposal| proposal["retention_export_purpose_compatibility"] = "compatible" }

      assert_invalid(paths, "retention_export_purpose_compatibility")
    end
  end

  def test_proposal_cannot_contain_personal_data_or_secrets
    %w[proposal_contains_personal_data proposal_contains_secrets].each do |field|
      with_thirteen_files do |paths|
        mutate_effect_proposal(paths) { |proposal| proposal[field] = true }

        assert_invalid(paths, field)
      end
    end
  end

  def test_malformed_proposal_is_rejected_without_echoing_source_content
    with_thirteen_files do |paths|
      File.open(paths.fetch(12), "wb") { |file| file.write("proposal_status: [unterminated\n") }
      preview = effect_preview

      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_copy_is_markdown_safe
    with_thirteen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_adapter_</script>" }
      rebuild_after_profile_change(paths)
      preview = effect_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_adapter\\_&lt;/script&gt;"
    end
  end

  def test_success_copy_hides_paths_digests_ids_source_content_and_review_provenance
    with_thirteen_files do |paths|
      preview = effect_preview
      copy = preview.preview_files(*paths)
      session = load_yaml(paths.fetch(0))
      attestation = load_yaml(paths.fetch(11))
      proposal = load_yaml(paths.fetch(12))

      assert copy, preview.errors.join("\n")
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, attestation["reviewer_ref"]
      refute_includes copy, attestation["payload_data_attestation_id"]
      refute_includes copy, proposal["adapter_effect_authorization_proposal_id"]
      DIGEST_FIELDS.each { |field| refute_includes copy, proposal[field] }
    end
  end

  def test_preview_exposes_digest_of_exact_proposal_bytes_loaded
    with_thirteen_files do |paths|
      File.open(paths.fetch(12), "ab") { |file| file.write("# equivalent proposal YAML\n") }
      preview = effect_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(12)).hexdigest, preview.effect_proposal_file_sha256
    end
  end

  def test_cli_reads_all_thirteen_inputs_without_writing
    with_thirteen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_effect_authorization.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Adapter 副作用授权提案待确认，当前零授权"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_effect_authorization.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_thirteen_files
    Dir.mktmpdir("pmind-adapter-effect-authorization") do |directory|
      paths = chain_fixture.write_twelve_files(directory)
      proposal_path = File.join(directory, "adapter-effect-authorization-proposal.yaml")
      chain_fixture.write_yaml(proposal_path, load_yaml(PROPOSAL_FIXTURE))
      paths << proposal_path
      refresh_effect_proposal_bindings(paths)
      yield paths
    end
  end

  def refresh_effect_proposal_bindings(paths)
    preview = PMind::HandoffPayloadDataAttestationPreview.new(ROOT)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(12))

    proposal = load_yaml(paths.fetch(12))
    preview.input_digests.each { |field, digest_value| proposal[field] = digest_value }
    proposal["payload_data_attestation_file_sha256"] = preview.attestation_file_sha256
    proposal["package_id"] = preview.envelope["package_id"]
    proposal["envelope_id"] = preview.envelope["envelope_id"]
    proposal["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    proposal["adapter_selection_proposal_id"] = preview.proposal["adapter_selection_proposal_id"]
    proposal["adapter_selection_confirmation_id"] = preview.selection_confirmation["adapter_selection_confirmation_id"]
    proposal["payload_data_attestation_id"] = preview.attestation["payload_data_attestation_id"]
    proposal["envelope_delivery_state"] = preview.envelope["delivery_state"]
    proposal["adapter_profile_status"] = preview.profile["status"]
    proposal["adapter_selection_proposal_status"] = preview.proposal.dig("confirmation", "status")
    proposal["selection_confirmation_decision"] = preview.selection_confirmation["confirmation_decision"]
    proposal["adapter_selected"] = preview.selection_confirmation["adapter_selected"]
    proposal["payload_data_attestation_completed"] = preview.attestation["payload_data_attestation_completed"]
    proposal["overall_data_compatibility"] = preview.attestation["overall_data_compatibility"]
    proposal["recipient"] = preview.envelope["recipient"]
    proposal["data_classification"] = preview.attestation["data_classification"]
    chain_fixture.write_yaml(paths.fetch(12), proposal)
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
    refresh_effect_proposal_bindings(paths)
  end

  def mutate_effect_proposal(paths, &block)
    mutate_yaml(paths.fetch(12), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = effect_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def effect_preview
    PMind::HandoffAdapterEffectAuthorizationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
