# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_effect_authorization_confirmation"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterEffectAuthorizationConfirmationTest < Minitest::Test
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
  ].freeze

  def test_confirmed_receipt_grants_exact_named_effects_but_not_dispatch
    with_fourteen_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已记录 Adapter 副作用授权，仍未授权 dispatch"
      assert_includes copy, "本地文件写入：已记录授权；尚不可执行"
      assert_includes copy, "当前 effects executable：否"
      assert_includes copy, "当前 dispatch：未授权"
      assert_includes copy, "Adapter Implementation Attestation"
    end
  end

  def test_modify_requested_is_legal_only_with_zero_grants
    with_fourteen_files do |paths|
      set_choice(paths, "modify_requested", false, [], false, false, "请修改副作用范围。")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已收到 Adapter 副作用授权修改请求，当前零授权"
      assert_includes copy, "不会执行任何副作用"
    end
  end

  def test_rejected_is_legal_only_with_zero_grants
    with_fourteen_files do |paths|
      set_choice(paths, "rejected", false, [], false, false, "拒绝当前副作用请求。")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已拒绝当前 Adapter 副作用请求"
      assert_includes copy, "没有副作用获授权"
    end
  end

  def test_zero_effect_confirmation_is_legal_without_granting_an_effect
    with_fourteen_files do |paths|
      set_profile_effects(paths, [])
      refresh_effect_proposal(paths, [])
      chain_fixture.refresh_effect_authorization_confirmation_bindings(paths)
      mutate_receipt(paths) { |receipt| receipt["effect_authorizations_granted"] = [] }
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已确认零效果集合"
      assert_equal [], preview.confirmation["effect_authorizations_granted"]
      assert_equal true, preview.confirmation["all_requested_effects_authorized"]
    end
  end

  def test_all_effects_can_be_confirmed_exactly_without_execution
    with_fourteen_files do |paths|
      effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS
      set_profile_effects(paths, effects)
      refresh_effect_proposal(paths, effects)
      chain_fixture.refresh_effect_authorization_confirmation_bindings(paths)
      mutate_receipt(paths) do |receipt|
        receipt["effect_authorizations_granted"] = effects
        receipt["cost_effect_authorized"] = true
        receipt["production_data_access_authorized"] = true
      end
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      effects.each { |effect| assert_includes copy, PMind::HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect) }
      assert_includes copy, "金额与上限未授权"
      assert_includes copy, "只适用于精确 Payload，尚不可执行"
    end
  end

  def test_each_illegal_decision_confirmation_transition_is_rejected
    variants = [
      ["confirmed", false, ["local_file_write"], true],
      ["modify_requested", true, [], false],
      ["rejected", true, [], false]
    ]
    variants.each do |decision, confirmed, grants, all_authorized|
      with_fourteen_files do |paths|
        set_choice(paths, decision, confirmed, grants, all_authorized, false, "非法状态矩阵。")

        assert_invalid(paths, "true only for confirmed")
      end
    end
  end

  def test_all_requested_effects_authorized_flag_must_follow_each_decision
    [
      ["confirmed", false],
      ["modify_requested", true],
      ["rejected", true]
    ].each do |decision, all_authorized|
      with_fourteen_files do |paths|
        confirmed = decision == "confirmed"
        grants = confirmed ? ["local_file_write"] : []
        set_choice(paths, decision, confirmed, grants, all_authorized, false, "all-effects 状态测试。")

        assert_invalid(paths, "all_requested_effects_authorized must be true only for confirmed")
      end
    end
  end

  def test_confirmed_must_grant_all_and_only_requested_effects
    [[], %w[local_file_write network_access]].each do |grants|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt["effect_authorizations_granted"] = grants }

        assert_invalid(paths, "must equal all requested effects only for confirmed")
      end
    end
  end

  def test_modify_and_reject_cannot_grant_any_effect
    %w[modify_requested rejected].each do |decision|
      with_fourteen_files do |paths|
        set_choice(paths, decision, false, ["local_file_write"], false, false, "非法非确认授权。")

        assert_invalid(paths, "must equal all requested effects only for confirmed")
      end
    end
  end

  def test_cost_and_production_authorizations_are_derived_from_confirmed_effects
    variants = {
      "cost_effect_authorized" => true,
      "production_data_access_authorized" => true
    }
    variants.each do |field, value|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = value }

        assert_invalid(paths, field)
      end
    end
  end

  def test_cost_limit_is_never_authorized_by_effect_confirmation
    with_fourteen_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["cost_limit_authorized"] = true }

      assert_invalid(paths, "cost_limit_authorized")
    end
  end

  def test_implementation_contract_and_dispatch_gates_cannot_be_bypassed
    %w[adapter_implementation_attestation_required provider_contract_test_required dispatch_confirmation_required].each do |field|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = false }

        assert_invalid(paths, field)
      end
    end
  end

  def test_receipt_never_makes_effects_executable_or_authorizes_dispatch_or_inferred_high_risk_actions
    %w[effects_executable dispatch_authorized high_risk_authorization_inferred].each do |field|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = true }

        assert_invalid(paths, field)
      end
    end
  end

  def test_complete_thirteen_file_proposal_chain_is_replayed
    DIGEST_FIELDS.each_with_index do |field, index|
      with_fourteen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_each_declared_source_digest_must_match_same_replay_inputs
    DIGEST_FIELDS.each do |field|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = "0" * 64 }

        assert_invalid(paths, "#{field} does not match its confirmed source")
      end
    end
  end

  def test_identity_recipient_and_source_states_must_match
    replacements = {
      "package_id" => "pkg-20260821-999",
      "envelope_id" => "handoff-envelope-20260821-999",
      "adapter_profile_id" => "adapter-profile-20260822-999",
      "adapter_selection_proposal_id" => "adapter-selection-proposal-20260822-999",
      "adapter_selection_confirmation_id" => "adapter-selection-confirmation-20260822-999",
      "payload_data_attestation_id" => "payload-data-attestation-20260822-999",
      "adapter_effect_authorization_proposal_id" => "adapter-effect-authorization-proposal-20260822-999",
      "envelope_delivery_state" => "delivered",
      "adapter_profile_status" => "draft",
      "adapter_selection_proposal_status" => "confirmed",
      "selection_confirmation_decision" => "rejected",
      "adapter_selected" => false,
      "payload_data_attestation_completed" => false,
      "overall_data_compatibility" => "incompatible",
      "adapter_effect_authorization_proposal_status" => "confirmed",
      "recipient" => "research_agent"
    }
    replacements.each do |field, value|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = value }
        preview = confirmation_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") }, preview.errors.join("\n")
      end
    end
  end

  def test_requested_effects_cost_disclosure_and_known_data_gap_must_match_proposal
    replacements = {
      "requested_effect_authorizations" => [],
      "cost_disclosure_before_dispatch_required" => true,
      "retention_export_purpose_compatibility" => "compatible"
    }
    replacements.each do |field, value|
      with_fourteen_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = value }

        assert_invalid(paths, field)
      end
    end
  end

  def test_user_response_digest_must_match_without_echoing_response
    with_fourteen_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["user_response_sha256"] = "0" * 64 }

      assert_invalid(paths, "user response digest does not match")
    end
  end

  def test_confirmation_cannot_predate_effect_proposal
    with_fourteen_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["captured_at"] = "2026-08-22T18:23:59+08:00" }

      assert_invalid(paths, "cannot predate its Proposal")
    end
  end

  def test_confirmation_cannot_downgrade_proposal_classification
    with_fourteen_files do |paths|
      mutate_yaml(paths.fetch(12)) { |proposal| proposal["data_classification"] = "internal" }
      chain_fixture.refresh_effect_authorization_confirmation_bindings(paths)
      mutate_receipt(paths) { |receipt| receipt["data_classification"] = "public" }

      assert_invalid(paths, "data classification cannot downgrade its source")
    end
  end

  def test_personal_user_response_cannot_use_public_classification
    with_fourteen_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["contains_personal_data"] = true }

      assert_invalid(paths, "personal data cannot use public classification")
    end
  end

  def test_receipt_cannot_contain_secrets
    with_fourteen_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["contains_secrets"] = true }

      assert_invalid(paths, "contains_secrets")
    end
  end

  def test_malformed_receipt_is_rejected_without_echoing_source_or_response
    with_fourteen_files do |paths|
      response = load_yaml(paths.fetch(13))["user_response"]
      File.open(paths.fetch(13), "wb") { |file| file.write("confirmation_decision: [unterminated\n") }
      preview = confirmation_preview

      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
      refute_includes preview.errors.join("\n"), response
    end
  end

  def test_confirmed_copy_is_markdown_safe
    with_fourteen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_adapter_</script>" }
      rebuild_after_profile_change(paths)
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_adapter\\_&lt;/script&gt;"
    end
  end

  def test_success_copy_hides_paths_digests_ids_source_content_provenance_and_user_response
    with_fourteen_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)
      session = load_yaml(paths.fetch(0))
      attestation = load_yaml(paths.fetch(11))
      receipt = load_yaml(paths.fetch(13))

      assert copy, preview.errors.join("\n")
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, attestation["reviewer_ref"]
      refute_includes copy, receipt["adapter_effect_authorization_confirmation_id"]
      refute_includes copy, receipt["user_response"]
      DIGEST_FIELDS.each { |field| refute_includes copy, receipt[field] }
    end
  end

  def test_preview_exposes_digest_of_exact_receipt_bytes_loaded
    with_fourteen_files do |paths|
      File.open(paths.fetch(13), "ab") { |file| file.write("# equivalent receipt YAML\n") }
      preview = confirmation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(13)).hexdigest, preview.confirmation_file_sha256
    end
  end

  def test_cli_reads_all_fourteen_inputs_without_writing
    with_fourteen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_effect_authorization_confirmation.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "已记录 Adapter 副作用授权，仍未授权 dispatch"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_effect_authorization_confirmation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_fourteen_files
    Dir.mktmpdir("pmind-adapter-effect-authorization-confirmation") do |directory|
      yield chain_fixture.write_fourteen_files(directory)
    end
  end

  def set_choice(paths, decision, confirmed, grants, all_authorized, cost_authorized, response)
    mutate_receipt(paths) do |receipt|
      receipt["confirmation_decision"] = decision
      receipt["effect_authorization_confirmed"] = confirmed
      receipt["effect_authorizations_granted"] = grants
      receipt["all_requested_effects_authorized"] = all_authorized
      receipt["cost_effect_authorized"] = cost_authorized
      receipt["production_data_access_authorized"] = false
      receipt["user_response"] = response
      receipt["user_response_sha256"] = Digest::SHA256.hexdigest(response)
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
    chain_fixture.refresh_profile_digest(paths)
    chain_fixture.refresh_selection_confirmation_bindings(paths)
    chain_fixture.refresh_payload_data_attestation_bindings(paths)
  end

  def refresh_effect_proposal(paths, effects)
    chain_fixture.refresh_adapter_effect_authorization_proposal_bindings(paths)
    mutate_yaml(paths.fetch(12)) do |proposal|
      proposal["requested_effect_authorizations"] = effects
      cost_present = effects.include?("cost_incurred")
      proposal["cost_effect_present"] = cost_present
      proposal["cost_disclosure_required"] = cost_present
      proposal["cost_estimate_status"] = cost_present ? "not_estimated" : "not_applicable"
      proposal["production_data_access_disclosure_required"] = effects.include?("production_data_access")
    end
  end

  def rebuild_after_profile_change(paths)
    effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |effect|
      load_yaml(paths.fetch(8)).dig("effects", effect) == true
    end
    chain_fixture.refresh_profile_digest(paths)
    chain_fixture.refresh_selection_confirmation_bindings(paths)
    chain_fixture.refresh_payload_data_attestation_bindings(paths)
    refresh_effect_proposal(paths, effects)
    chain_fixture.refresh_effect_authorization_confirmation_bindings(paths)
  end

  def mutate_receipt(paths, &block)
    mutate_yaml(paths.fetch(13), &block)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    chain_fixture.write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = confirmation_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def confirmation_preview
    PMind::HandoffAdapterEffectAuthorizationConfirmationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
