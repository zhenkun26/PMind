# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_payload_data_attestation"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffPayloadDataAttestationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ATTESTATION_FIXTURE = File.join(ROOT, "test/fixtures/handoff-payload-data-attestation-valid.yaml")
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
  ].freeze

  def test_payload_without_personal_data_or_secrets_is_compatible_but_not_dispatchable
    with_twelve_files do |paths|
      preview = attestation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Payload 数据审核已通过，仍未授权 dispatch"
      assert_includes copy, "已审查的本地文件候选 Adapter"
      assert_includes copy, "审核范围：完整 Handoff Envelope payload"
      assert_includes copy, "个人数据：未发现"
      assert_includes copy, "密钥：未发现"
      assert_includes copy, "数据兼容性：已通过"
      assert_includes copy, "本地文件写入：未授权"
      assert_includes copy, "Adapter Effect Authorization Proposal"
    end
  end

  def test_personal_data_is_compatible_only_when_selected_profile_allows_it
    with_twelve_files do |paths|
      allow_profile_personal_data(paths)
      set_payload_facts(paths, personal_categories: ["contact"])
      preview = attestation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "个人数据：已发现；所选 Adapter Profile 允许处理"
      assert_includes copy, "数据兼容性：已通过"
      assert_includes copy, "dispatch：未授权"
    end
  end

  def test_personal_data_forbidden_by_selected_profile_blocks_dispatch
    with_twelve_files do |paths|
      set_payload_facts(paths, personal_categories: ["contact"])
      preview = attestation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Payload 数据与所选 Adapter 不兼容，dispatch 已阻断"
      assert_includes copy, "个人数据：已发现；所选 Adapter Profile 禁止处理"
      assert_includes copy, "不得 dispatch"
    end
  end

  def test_any_payload_secret_is_incompatible_with_selected_profile
    with_twelve_files do |paths|
      set_payload_facts(paths, secret_categories: ["api_key"])
      preview = attestation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Payload 数据与所选 Adapter 不兼容，dispatch 已阻断"
      assert_includes copy, "密钥：已发现；所选 Adapter Profile 禁止处理"
      refute_includes copy, "api_key"
    end
  end

  def test_each_compatibility_result_must_be_derived_from_facts_and_profile_policy
    %w[personal_data_compatibility secret_compatibility data_classification_compatibility overall_data_compatibility].each do |field|
      with_twelve_files do |paths|
        mutate_attestation(paths) { |document| document[field] = "incompatible" }

        assert_invalid(paths, "#{field} must be derived")
      end
    end
  end

  def test_classification_above_selected_profile_maximum_blocks_dispatch
    with_twelve_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile.dig("data_policy")["maximum_data_classification"] = "public" }
      chain_fixture.refresh_profile_digest(paths)
      chain_fixture.refresh_selection_confirmation_bindings(paths)
      refresh_attestation_bindings(paths)
      mutate_attestation(paths) do |document|
        document["data_classification"] = "internal"
        document["data_classification_compatibility"] = "incompatible"
        document["overall_data_compatibility"] = "incompatible"
      end
      preview = attestation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Payload 数据与所选 Adapter 不兼容，dispatch 已阻断"
      assert_includes copy, "数据分类：超出所选 Adapter Profile 可接受的最高级别"
    end
  end

  def test_attestation_requires_a_confirmed_adapter_selection
    %w[modify_requested rejected].each do |decision|
      with_twelve_files do |paths|
        set_selection_choice(paths, decision, false)

        assert_invalid(paths, "requires a confirmed Adapter selection")
      end
    end
  end

  def test_complete_eleven_file_selection_chain_is_replayed
    DIGEST_FIELDS.each_with_index do |field, index|
      with_twelve_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_each_declared_source_digest_must_match_same_replay_inputs
    DIGEST_FIELDS.each do |field|
      with_twelve_files do |paths|
        mutate_attestation(paths) { |document| document[field] = "0" * 64 }

        assert_invalid(paths, "#{field} does not match its attested source")
      end
    end
  end

  def test_identity_state_and_selected_profile_policy_must_match
    replacements = {
      "package_id" => "pkg-20260821-999",
      "envelope_id" => "handoff-envelope-20260821-999",
      "adapter_profile_id" => "adapter-profile-20260822-999",
      "adapter_selection_proposal_id" => "adapter-selection-proposal-20260822-999",
      "adapter_selection_confirmation_id" => "adapter-selection-confirmation-20260822-999",
      "envelope_delivery_state" => "delivered",
      "adapter_profile_status" => "draft",
      "adapter_selection_proposal_status" => "confirmed",
      "selection_confirmation_decision" => "rejected",
      "adapter_selected" => false,
      "recipient" => "research_agent",
      "adapter_maximum_data_classification" => "public",
      "adapter_personal_data_handling" => "allowed",
      "adapter_secret_handling" => "allowed"
    }
    replacements.each do |field, value|
      with_twelve_files do |paths|
        mutate_attestation(paths) { |document| document[field] = value }
        preview = attestation_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") || error.include?("expected one of") }, preview.errors.join("\n")
      end
    end
  end

  def test_manual_automated_and_hybrid_review_provenance_are_accepted
    variants = [
      ["manual", "reviewer:001", "not_applicable", "not_applicable"],
      ["automated", "not_applicable", "scanner:pii-secret", "1.2.3"],
      ["hybrid", "reviewer:001", "scanner:pii-secret", "1.2.3"]
    ]
    variants.each do |method, reviewer, scanner, version|
      with_twelve_files do |paths|
        mutate_attestation(paths) do |document|
          document["review_method"] = method
          document["reviewer_ref"] = reviewer
          document["scanner_ref"] = scanner
          document["scanner_version"] = version
        end

        assert attestation_preview.preview_files(*paths), method
      end
    end
  end

  def test_incomplete_review_provenance_is_rejected_for_each_method
    variants = [
      ["manual", "not_applicable", "not_applicable", "not_applicable"],
      ["automated", "not_applicable", "not_applicable", "not_applicable"],
      ["hybrid", "reviewer:001", "not_applicable", "not_applicable"]
    ]
    variants.each do |method, reviewer, scanner, version|
      with_twelve_files do |paths|
        mutate_attestation(paths) do |document|
          document["review_method"] = method
          document["reviewer_ref"] = reviewer
          document["scanner_ref"] = scanner
          document["scanner_version"] = version
        end

        assert_invalid(paths, "review provenance must match")
      end
    end
  end

  def test_presence_flags_and_category_lists_must_agree
    variants = [
      ["payload_contains_personal_data", false, "personal_data_categories", ["contact"]],
      ["payload_contains_personal_data", true, "personal_data_categories", []],
      ["payload_contains_secrets", false, "secret_categories", ["api_key"]],
      ["payload_contains_secrets", true, "secret_categories", []]
    ]
    variants.each do |flag, flag_value, categories, category_values|
      with_twelve_files do |paths|
        mutate_attestation(paths) do |document|
          document[flag] = flag_value
          document[categories] = category_values
          document["data_classification"] = "internal" if flag_value || !category_values.empty?
        end

        assert_invalid(paths, "#{categories} must be non-empty exactly when #{flag} is true")
      end
    end
  end

  def test_attestation_never_authorizes_dispatch_external_effects_or_high_risk_actions
    %w[dispatch_authorized external_effects_authorized high_risk_authorization_inferred].each do |field|
      with_twelve_files do |paths|
        mutate_attestation(paths) { |document| document[field] = true }

        assert_invalid(paths, "expected constant false")
      end
    end
  end

  def test_attestation_cannot_grant_profile_effect_authorizations
    with_twelve_files do |paths|
      mutate_attestation(paths) { |document| document["effect_authorizations_granted"] = ["local_file_write"] }

      assert_invalid(paths, "allows at most 0 items")
    end
  end

  def test_attestation_cannot_predate_adapter_selection_confirmation
    with_twelve_files do |paths|
      mutate_attestation(paths) { |document| document["reviewed_at"] = "2026-08-22T18:21:59+08:00" }

      assert_invalid(paths, "cannot predate Adapter selection confirmation")
    end
  end

  def test_attestation_cannot_downgrade_envelope_or_selection_classification
    with_twelve_files(envelope_classification: "restricted") do |paths|
      mutate_attestation(paths) { |document| document["data_classification"] = "public" }

      assert_invalid(paths, "data classification cannot downgrade its sources")
    end
  end

  def test_sensitive_payload_cannot_use_public_classification
    with_twelve_files do |paths|
      allow_profile_personal_data(paths)
      set_payload_facts(paths, personal_categories: ["contact"])
      mutate_attestation(paths) { |document| document["data_classification"] = "public" }

      assert_invalid(paths, "sensitive payload or attestation metadata cannot use public classification")
    end
  end

  def test_personal_attestation_metadata_cannot_use_public_classification
    with_twelve_files do |paths|
      mutate_attestation(paths) { |document| document["attestation_contains_personal_data"] = true }

      assert_invalid(paths, "sensitive payload or attestation metadata cannot use public classification")
    end
  end

  def test_attestation_document_cannot_contain_secrets
    with_twelve_files do |paths|
      mutate_attestation(paths) { |document| document["attestation_contains_secrets"] = true }

      assert_invalid(paths, "expected constant false")
    end
  end

  def test_malformed_attestation_is_rejected_without_echoing_source_content
    with_twelve_files do |paths|
      File.open(paths.fetch(11), "wb") { |file| file.write("overall_data_compatibility: [unterminated\n") }
      preview = attestation_preview

      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_compatible_copy_is_markdown_safe
    with_twelve_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_adapter_</script> [link](https://invalid.example)" }
      chain_fixture.refresh_profile_digest(paths)
      chain_fixture.refresh_selection_confirmation_bindings(paths)
      refresh_attestation_bindings(paths)
      preview = attestation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_adapter\\_&lt;/script&gt;"
      assert_includes copy, "\\[link\\](https://invalid.example)"
    end
  end

  def test_success_copy_hides_paths_digests_ids_source_content_and_review_provenance
    with_twelve_files do |paths|
      preview = attestation_preview
      copy = preview.preview_files(*paths)
      session = load_yaml(paths.fetch(0))
      envelope = load_yaml(paths.fetch(7))
      confirmation = load_yaml(paths.fetch(10))
      attestation = load_yaml(paths.fetch(11))

      assert copy, preview.errors.join("\n")
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, envelope.dig("prompt_package", "knowledge", "evidence", 0, "source")
      refute_includes copy, envelope["envelope_id"]
      refute_includes copy, confirmation["adapter_selection_confirmation_id"]
      refute_includes copy, attestation["payload_data_attestation_id"]
      refute_includes copy, attestation["reviewer_ref"]
      refute_includes copy, "constraints.product"
    end
  end

  def test_preview_exposes_digest_of_exact_attestation_bytes_loaded
    with_twelve_files do |paths|
      File.open(paths.fetch(11), "ab") { |file| file.write("# equivalent attestation YAML\n") }
      preview = attestation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(11)).hexdigest, preview.attestation_file_sha256
    end
  end

  def test_cli_reads_all_twelve_inputs_without_writing
    with_twelve_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_payload_data_attestation.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Payload 数据审核已通过，仍未授权 dispatch"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_payload_data_attestation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_twelve_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-payload-data-attestation") do |directory|
      paths = chain_fixture.write_eleven_files(directory, envelope_classification: envelope_classification)
      attestation_path = File.join(directory, "payload-data-attestation.yaml")
      chain_fixture.write_yaml(attestation_path, load_yaml(ATTESTATION_FIXTURE))
      paths << attestation_path
      refresh_attestation_bindings(paths)
      yield paths
    end
  end

  def refresh_attestation_bindings(paths)
    preview = PMind::HandoffAdapterSelectionConfirmationPreview.new(ROOT)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(11))

    document = load_yaml(paths.fetch(11))
    preview.input_digests.each { |field, digest_value| document[field] = digest_value }
    document["adapter_selection_confirmation_receipt_file_sha256"] = preview.confirmation_file_sha256
    document["package_id"] = preview.envelope["package_id"]
    document["envelope_id"] = preview.envelope["envelope_id"]
    document["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    document["adapter_selection_proposal_id"] = preview.proposal["adapter_selection_proposal_id"]
    document["adapter_selection_confirmation_id"] = preview.confirmation["adapter_selection_confirmation_id"]
    document["envelope_delivery_state"] = preview.envelope["delivery_state"]
    document["adapter_profile_status"] = preview.profile["status"]
    document["adapter_selection_proposal_status"] = preview.proposal.dig("confirmation", "status")
    document["selection_confirmation_decision"] = preview.confirmation["confirmation_decision"]
    document["adapter_selected"] = preview.confirmation["adapter_selected"]
    document["recipient"] = preview.envelope["recipient"]
    document["adapter_maximum_data_classification"] = preview.profile.dig("data_policy", "maximum_data_classification")
    document["adapter_personal_data_handling"] = preview.profile.dig("data_policy", "personal_data_handling")
    document["adapter_secret_handling"] = preview.profile.dig("data_policy", "secret_handling")
    document["data_classification"] = preview.confirmation["data_classification"]
    chain_fixture.write_yaml(paths.fetch(11), document)
  end

  def allow_profile_personal_data(paths)
    mutate_yaml(paths.fetch(8)) { |profile| profile.dig("data_policy")["personal_data_handling"] = "allowed" }
    chain_fixture.refresh_profile_digest(paths)
    chain_fixture.refresh_selection_confirmation_bindings(paths)
    refresh_attestation_bindings(paths)
  end

  def set_payload_facts(paths, personal_categories: [], secret_categories: [])
    profile = load_yaml(paths.fetch(8))
    mutate_attestation(paths) do |document|
      document["payload_contains_personal_data"] = !personal_categories.empty?
      document["personal_data_categories"] = personal_categories
      document["payload_contains_secrets"] = !secret_categories.empty?
      document["secret_categories"] = secret_categories
      personal_compatible = personal_categories.empty? || profile.dig("data_policy", "personal_data_handling") == "allowed"
      secret_compatible = secret_categories.empty?
      document["personal_data_compatibility"] = personal_compatible ? "compatible" : "incompatible"
      document["secret_compatibility"] = secret_compatible ? "compatible" : "incompatible"
      document["data_classification"] = "internal" unless personal_categories.empty? && secret_categories.empty?
      attestation_rank = PMind::HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK.fetch(document["data_classification"])
      profile_rank = PMind::HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK.fetch(profile.dig("data_policy", "maximum_data_classification"))
      classification_compatible = attestation_rank <= profile_rank
      document["data_classification_compatibility"] = classification_compatible ? "compatible" : "incompatible"
      document["overall_data_compatibility"] = personal_compatible && secret_compatible && classification_compatible ? "compatible" : "incompatible"
    end
  end

  def set_selection_choice(paths, decision, selected)
    mutate_yaml(paths.fetch(10)) do |receipt|
      response = "#{decision} Adapter selection for attestation test."
      receipt["confirmation_decision"] = decision
      receipt["adapter_selected"] = selected
      receipt["user_response"] = response
      receipt["user_response_sha256"] = Digest::SHA256.hexdigest(response)
    end
  end

  def mutate_attestation(paths, &block)
    mutate_yaml(paths.fetch(11), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = attestation_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def attestation_preview
    PMind::HandoffPayloadDataAttestationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
