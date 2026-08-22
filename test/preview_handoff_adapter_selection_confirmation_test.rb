# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/preview_handoff_adapter_selection_confirmation"
require_relative "support/handoff_adapter_chain_fixture"

class PreviewHandoffAdapterSelectionConfirmationTest < Minitest::Test
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
  ].freeze

  def test_confirmed_receipt_records_selection_without_dispatch_or_effect_authority
    with_eleven_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已记录 Adapter 选择，尚未 dispatch"
      assert_includes copy, "已审查的本地文件候选 Adapter"
      assert_includes copy, "Adapter 选择：已记录"
      assert_includes copy, "dispatch：未授权"
      assert_includes copy, "本地文件写入：未授权"
      assert_includes copy, "个人数据兼容性：未知"
      assert_includes copy, "密钥兼容性：未知"
      assert_includes copy, "Payload Data Attestation"
    end
  end

  def test_modify_requested_is_legal_only_without_adapter_selection
    with_eleven_files do |paths|
      set_choice(paths, "modify_requested", false, "请修改候选 Adapter Profile。")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已收到 Adapter 选择修改请求，当前未选择"
      assert_includes copy, "Handoff Envelope 保持不变"
      assert_includes copy, "不会 dispatch"
    end
  end

  def test_rejected_is_legal_only_without_adapter_selection
    with_eleven_files do |paths|
      set_choice(paths, "rejected", false, "拒绝当前候选 Adapter。")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已拒绝当前 Adapter 候选"
      assert_includes copy, "没有 Adapter 被选择"
      assert_includes copy, "不会产生渠道副作用"
    end
  end

  def test_each_illegal_choice_selection_transition_is_rejected
    [
      ["confirmed", false],
      ["modify_requested", true],
      ["rejected", true]
    ].each do |decision, selected|
      with_eleven_files do |paths|
        set_choice(paths, decision, selected, "状态矩阵测试。")

        assert_invalid(paths, "adapter_selected must be true only for confirmed")
      end
    end
  end

  def test_receipt_never_authorizes_dispatch_external_effects_or_high_risk_actions
    %w[dispatch_authorized external_effects_authorized high_risk_authorization_inferred].each do |field|
      with_eleven_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = true }

        assert_invalid(paths, "expected constant false")
      end
    end
  end

  def test_receipt_cannot_grant_any_profile_effect_authorization
    with_eleven_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["effect_authorizations_granted"] = ["local_file_write"] }

      assert_invalid(paths, "allows at most 0 items")
    end
  end

  def test_payload_attestation_and_compatibility_unknowns_cannot_be_bypassed
    replacements = {
      "payload_data_attestation_required" => false,
      "personal_data_compatibility" => "compatible",
      "secret_compatibility" => "compatible"
    }
    replacements.each do |field, value|
      with_eleven_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = value }

        assert_invalid(paths, "expected constant")
      end
    end
  end

  def test_complete_ten_file_selection_chain_is_replayed
    DIGEST_FIELDS.each_with_index do |field, index|
      with_eleven_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_each_declared_source_digest_must_match_same_replay_inputs
    DIGEST_FIELDS.each do |field|
      with_eleven_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = "0" * 64 }

        assert_invalid(paths, "#{field} does not match its confirmed source")
      end
    end
  end

  def test_identity_recipient_and_pending_states_must_match
    replacements = {
      "envelope_id" => "handoff-envelope-20260821-999",
      "adapter_profile_id" => "adapter-profile-20260822-999",
      "adapter_selection_proposal_id" => "adapter-selection-proposal-20260822-999",
      "envelope_delivery_state" => "delivered",
      "adapter_profile_status" => "draft",
      "adapter_selection_proposal_status" => "confirmed",
      "recipient" => "research_agent"
    }
    replacements.each do |field, value|
      with_eleven_files do |paths|
        mutate_receipt(paths) { |receipt| receipt[field] = value }
        preview = confirmation_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") }, preview.errors.join("\n")
      end
    end
  end

  def test_user_response_digest_must_match_without_echoing_response
    with_eleven_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["user_response_sha256"] = "0" * 64 }

      assert_invalid(paths, "user response digest does not match")
    end
  end

  def test_confirmation_cannot_predate_selection_proposal
    with_eleven_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["captured_at"] = "2026-08-22T18:20:59+08:00" }

      assert_invalid(paths, "cannot predate its Proposal")
    end
  end

  def test_confirmation_cannot_downgrade_envelope_or_proposal_classification
    with_eleven_files(envelope_classification: "restricted") do |paths|
      mutate_receipt(paths) { |receipt| receipt["data_classification"] = "public" }

      assert_invalid(paths, "data classification cannot downgrade its sources")
    end
  end

  def test_personal_user_response_cannot_use_public_classification
    with_eleven_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["contains_personal_data"] = true }

      assert_invalid(paths, "personal data cannot use public classification")
    end
  end

  def test_receipt_cannot_contain_secrets
    with_eleven_files do |paths|
      mutate_receipt(paths) { |receipt| receipt["contains_secrets"] = true }

      assert_invalid(paths, "expected constant false")
    end
  end

  def test_malformed_receipt_is_rejected_without_echoing_source_content
    with_eleven_files do |paths|
      File.open(paths.fetch(10), "wb") { |file| file.write("confirmation_decision: [unterminated\n") }
      preview = confirmation_preview

      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_confirmed_copy_is_markdown_safe
    with_eleven_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_adapter_</script> [link](https://invalid.example)" }
      chain_fixture.refresh_profile_digest(paths)
      refresh_confirmation_bindings(paths)
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_adapter\\_&lt;/script&gt;"
      assert_includes copy, "\\[link\\](https://invalid.example)"
    end
  end

  def test_success_copy_hides_paths_digests_ids_source_content_and_user_response
    with_eleven_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)
      session = load_yaml(paths.fetch(0))
      envelope = load_yaml(paths.fetch(7))
      profile = load_yaml(paths.fetch(8))
      proposal = load_yaml(paths.fetch(9))
      confirmation = load_yaml(paths.fetch(10))

      assert copy, preview.errors.join("\n")
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, envelope.dig("prompt_package", "knowledge", "evidence", 0, "source")
      refute_includes copy, envelope["envelope_id"]
      refute_includes copy, profile["adapter_profile_id"]
      refute_includes copy, profile["reviewer_ref"]
      refute_includes copy, proposal["adapter_selection_proposal_id"]
      refute_includes copy, confirmation["adapter_selection_confirmation_id"]
      refute_includes copy, confirmation["user_response"]
      refute_includes copy, confirmation["user_response_sha256"]
      refute_includes copy, "constraints.product"
    end
  end

  def test_preview_exposes_digest_of_exact_confirmation_bytes_loaded
    with_eleven_files do |paths|
      File.open(paths.fetch(10), "ab") { |file| file.write("# equivalent receipt YAML\n") }
      preview = confirmation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(10)).hexdigest, preview.confirmation_file_sha256
    end
  end

  def test_cli_reads_all_eleven_inputs_without_writing
    with_eleven_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_selection_confirmation.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "已记录 Adapter 选择，尚未 dispatch"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_selection_confirmation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_eleven_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-adapter-selection-confirmation") do |directory|
      paths = chain_fixture.write_eleven_files(directory, envelope_classification: envelope_classification)
      yield paths
    end
  end

  def refresh_confirmation_bindings(paths)
    chain_fixture.refresh_selection_confirmation_bindings(paths)
  end

  def set_choice(paths, decision, selected, response)
    mutate_receipt(paths) do |receipt|
      receipt["confirmation_decision"] = decision
      receipt["adapter_selected"] = selected
      receipt["user_response"] = response
      receipt["user_response_sha256"] = Digest::SHA256.hexdigest(response)
    end
  end

  def mutate_receipt(paths, &block)
    mutate_yaml(paths.fetch(10), &block)
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
    PMind::HandoffAdapterSelectionConfirmationPreview.new(ROOT)
  end

  def load_yaml(path)
    chain_fixture.load_yaml(path)
  end

  def chain_fixture
    @chain_fixture ||= HandoffAdapterChainFixture.new(ROOT)
  end
end
