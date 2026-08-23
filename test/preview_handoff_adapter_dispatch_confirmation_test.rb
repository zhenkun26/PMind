# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_dispatch_confirmation"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterDispatchConfirmationTest < Minitest::Test
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
  ].freeze

  def test_confirmed_receipt_authorizes_only_exact_dispatch_and_does_not_execute
    with_eighteen_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已记录 Adapter dispatch 确认，尚未执行"
      assert_includes copy, "dispatch 授权：已记录；仅限当前 exact Proposal"
      assert_includes copy, "effects executable：否"
      assert_includes copy, "provider 已调用：否"
      assert_includes copy, "dispatch 已尝试：否"
      assert_includes copy, "Service execution request / preflight"
      assert_equal true, preview.dispatch_confirmation["dispatch_authorized"]
      assert_equal false, preview.dispatch_confirmation["effects_executable"]
    end
  end

  def test_modify_request_records_no_dispatch_or_cost_authorization
    with_eighteen_files do |paths|
      set_decision(paths, "modify_requested")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "dispatch 修改请求，当前未授权"
      assert_equal false, preview.dispatch_confirmation["dispatch_authorized"]
      assert_equal false, preview.dispatch_confirmation["cost_limit_authorized"]
      assert_equal false, preview.dispatch_confirmation["service_execution_request_required"]
      assert_equal false, preview.dispatch_confirmation["execution_receipt_required"]
    end
  end

  def test_rejection_stops_before_execution_request
    with_eighteen_files do |paths|
      set_decision(paths, "rejected")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已拒绝当前 Adapter dispatch"
      assert_includes copy, "执行请求之前停止"
      assert_equal false, preview.dispatch_confirmation["dispatch_authorized"]
      assert_equal false, preview.dispatch_confirmation["service_execution_request_required"]
    end
  end

  def test_choice_state_machine_cannot_be_forged
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["dispatch_authorized"] = false }
      assert_invalid(paths, "dispatch_authorized must be true only for confirmed")
    end
    with_eighteen_files do |paths|
      set_decision(paths, "rejected")
      mutate_receipt(paths) { |document| document["dispatch_authorized"] = true }
      assert_invalid(paths, "dispatch_authorized must be true only for confirmed")
    end
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["cost_limit_authorized"] = true }
      assert_invalid(paths, "cost_limit_authorized must be true only")
    end
  end

  def test_cost_bearing_confirmation_authorizes_only_exact_fixed_point_ceiling
    with_eighteen_files do |paths|
      set_profile_effects(paths, ["cost_incurred"])
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "费用上限：10.00 USD；已随本次 exact dispatch 确认"
      assert_equal true, preview.dispatch_confirmation["cost_limit_authorized"]
      assert_equal false, preview.dispatch_confirmation["cost_incurred"]
    end
  end

  def test_modify_or_reject_never_authorizes_cost_ceiling
    %w[modify_requested rejected].each do |decision|
      with_eighteen_files do |paths|
        set_profile_effects(paths, ["cost_incurred"])
        set_decision(paths, decision)
        preview = confirmation_preview
        assert preview.preview_files(*paths), "#{decision}: #{preview.errors.join("\n")}"
        assert_equal false, preview.dispatch_confirmation["cost_limit_authorized"]
      end
    end
  end

  def test_no_cost_effect_cannot_claim_cost_authorization
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["cost_limit_authorized"] = true }
      assert_invalid(paths, "cost_limit_authorized must be true only")
    end
  end

  def test_zero_effect_confirmation_is_legal_but_still_not_executable
    with_eighteen_files do |paths|
      set_profile_effects(paths, [])
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "零 effect 集合"
      assert_equal [], preview.dispatch_confirmation["authorized_effects"]
      assert_equal false, preview.dispatch_confirmation["effects_executable"]
    end
  end

  def test_all_effects_remain_named_and_non_executable_after_confirmation
    with_eighteen_files do |paths|
      effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS
      set_profile_effects(paths, effects)
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      effects.each { |effect| assert_includes copy, PMind::HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect) }
      assert_equal effects, preview.dispatch_confirmation["authorized_effects"]
      assert_equal false, preview.dispatch_confirmation["effects_executable"]
    end
  end

  def test_confirmation_time_must_follow_proposal_and_confirm_before_expiry
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["captured_at"] = "2026-08-23T10:14:59+08:00" }
      assert_invalid(paths, "cannot predate its Proposal")
    end
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["captured_at"] = "2026-08-23T10:45:00+08:00" }
      assert_invalid(paths, "must be captured before Proposal expiry")
    end
  end

  def test_modify_or_reject_can_record_an_expired_proposal_without_authorizing_it
    %w[modify_requested rejected].each do |decision|
      with_eighteen_files do |paths|
        set_decision(paths, decision)
        mutate_receipt(paths) { |document| document["captured_at"] = "2026-08-23T10:45:01+08:00" }
        preview = confirmation_preview
        assert preview.preview_files(*paths), "#{decision}: #{preview.errors.join("\n")}"
        assert_equal false, preview.dispatch_confirmation["dispatch_authorized"]
      end
    end
  end

  def test_scheduled_dispatch_can_be_confirmed_before_not_before
    with_eighteen_files do |paths|
      mutate_yaml(paths.fetch(16)) do |proposal|
        proposal["not_before"] = "2026-08-23T10:30:00+08:00"
        proposal["idempotency_key_sha256"] = PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(proposal)
      end
      chain_fixture.refresh_adapter_dispatch_confirmation_bindings(paths)
      preview = confirmation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_operator Time.iso8601(preview.dispatch_confirmation["captured_at"]), :<,
                      Time.iso8601(preview.dispatch_confirmation["not_before"])
    end
  end

  def test_every_source_file_drift_invalidates_the_receipt
    17.times do |index|
      with_eighteen_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }
        preview = confirmation_preview
        refute preview.preview_files(*paths), "source #{index} unexpectedly accepted"
      end
    end
  end

  def test_every_declared_source_digest_is_checked
    DIGEST_FIELDS.each do |field|
      with_eighteen_files do |paths|
        mutate_receipt(paths) { |document| document[field] = "f" * 64 }
        assert_invalid(paths, field)
      end
    end
  end

  def test_all_stable_id_and_source_state_bindings_are_exact
    {
      "package_id" => "pkg-20260823-999",
      "adapter_profile_id" => "adapter-profile-20260823-999",
      "adapter_dispatch_proposal_id" => "adapter-dispatch-proposal-20260823-999",
      "overall_runtime_readiness" => "blocked",
      "dispatch_proposal_status" => "confirmed",
      "adapter_key" => "tampered_adapter"
    }.each do |field, value|
      with_eighteen_files do |paths|
        mutate_receipt(paths) { |document| document[field] = value }
        assert_invalid(paths, field)
      end
    end
  end

  def test_exact_dispatch_fields_cannot_drift_from_proposal
    {
      "dispatch_payload_file_sha256" => "e" * 64,
      "delivery_mode" => "remote_api",
      "dispatch_destination_ref" => "different-destination",
      "idempotency_key_sha256" => "d" * 64,
      "not_before" => "2026-08-23T10:16:00+08:00",
      "dispatch_attempt_limit" => 2,
      "dispatch_timeout_seconds" => 301,
      "authorized_effects" => [],
      "stop_conditions" => ["source_bytes_changed"],
      "cost_ceiling_amount" => "1.00"
    }.each do |field, value|
      with_eighteen_files do |paths|
        mutate_receipt(paths) { |document| document[field] = value }
        assert_invalid(paths, field)
      end
    end
  end

  def test_invalid_dispatch_proposal_cannot_be_confirmed
    with_eighteen_files do |paths|
      mutate_yaml(paths.fetch(16)) { |proposal| proposal["dispatch_authorized"] = true }
      assert_invalid(paths, "dispatch_authorized")
    end
  end

  def test_user_response_digest_is_exact_and_response_is_not_rendered
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["user_response"] = "different response" }
      assert_invalid(paths, "user response digest does not match")
    end
    with_eighteen_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)
      assert copy, preview.errors.join("\n")
      refute_includes copy, preview.dispatch_confirmation["user_response"]
    end
  end

  def test_receipt_cannot_downgrade_classification_or_mark_public_personal_data
    with_eighteen_files(envelope_classification: "internal") do |paths|
      mutate_receipt(paths) { |document| document["data_classification"] = "public" }
      assert_invalid(paths, "data classification cannot downgrade")
    end
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["contains_personal_data"] = true }
      assert_invalid(paths, "personal data cannot use public classification")
    end
  end

  def test_all_execution_and_external_result_fields_stay_false
    fields = %w[
      effects_executable adapter_started provider_called dispatch_attempted
      delivery_receipt_present external_write_performed cost_incurred
      high_risk_authorization_inferred contains_secrets credential_material_in_receipt
    ]
    fields.each do |field|
      with_eighteen_files do |paths|
        mutate_receipt(paths) { |document| document[field] = true }
        assert_invalid(paths, field)
      end
    end
  end

  def test_confirmed_requires_future_execution_request_and_receipt
    %w[service_execution_request_required execution_receipt_required].each do |field|
      with_eighteen_files do |paths|
        mutate_receipt(paths) { |document| document[field] = false }
        assert_invalid(paths, "#{field} must be true only for confirmed")
      end
    end
  end

  def test_non_confirmed_choice_cannot_require_future_execution_path
    %w[modify_requested rejected].each do |decision|
      %w[service_execution_request_required execution_receipt_required].each do |field|
        with_eighteen_files do |paths|
          set_decision(paths, decision)
          mutate_receipt(paths) { |document| document[field] = true }
          assert_invalid(paths, "#{field} must be true only for confirmed")
        end
      end
    end
  end

  def test_confirmation_receipt_presence_is_always_recorded
    with_eighteen_files do |paths|
      mutate_receipt(paths) { |document| document["dispatch_confirmation_recorded"] = false }
      assert_invalid(paths, "dispatch_confirmation_recorded")
    end
  end

  def test_malformed_receipt_is_rejected_without_echoing_source_content
    with_eighteen_files do |paths|
      File.open(paths.fetch(17), "wb") { |file| file.write("authorized_effects: [unterminated\n") }
      preview = confirmation_preview
      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_copy_is_markdown_safe_and_hides_sensitive_bindings
    with_eighteen_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_confirm_</script>" }
      rebuild_after_profile_change(paths)
      preview = confirmation_preview
      copy = preview.preview_files(*paths)
      document = preview.dispatch_confirmation

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_confirm\\_&lt;/script&gt;"
      paths.each { |path| refute_includes copy, path }
      %w[dispatch_destination_ref idempotency_key_sha256 adapter_dispatch_confirmation_id user_response].each do |field|
        refute_includes copy, document[field]
      end
      DIGEST_FIELDS.each { |field| refute_includes copy, document[field] }
      refute_includes copy, load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_preview_exposes_digest_of_exact_receipt_bytes_loaded
    with_eighteen_files do |paths|
      File.open(paths.fetch(17), "ab") { |file| file.write("# equivalent Receipt YAML\n") }
      preview = confirmation_preview
      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(17)).hexdigest,
                   preview.dispatch_confirmation_file_sha256
    end
  end

  def test_cli_reads_all_eighteen_inputs_without_writing
    with_eighteen_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_dispatch_confirmation.rb"),
        *paths,
        chdir: ROOT
      )
      assert status.success?, stderr
      assert_includes stdout, "已记录 Adapter dispatch 确认，尚未执行"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_dispatch_confirmation.rb"),
      chdir: ROOT
    )
    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_eighteen_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-adapter-dispatch-confirmation") do |directory|
      yield chain_fixture.write_eighteen_files(directory, envelope_classification: envelope_classification)
    end
  end

  def set_decision(paths, decision)
    mutate_receipt(paths) do |document|
      document["confirmation_decision"] = decision
      confirmed = decision == "confirmed"
      document["dispatch_authorized"] = confirmed
      document["cost_limit_authorized"] = confirmed && document["cost_ceiling_required"] == true
      document["service_execution_request_required"] = confirmed
      document["execution_receipt_required"] = confirmed
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
  end

  def mutate_receipt(paths, &block)
    mutate_yaml(paths.fetch(17), &block)
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
    PMind::HandoffAdapterDispatchConfirmationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
