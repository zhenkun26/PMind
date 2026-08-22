# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/preview_handoff_adapter_selection"

class PreviewHandoffAdapterSelectionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  COMPILATION_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  COMPILATION_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")
  HANDOFF_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/handoff-proposal-valid.yaml")
  HANDOFF_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/handoff-confirmation-receipt-valid.yaml")
  ADAPTER_PROFILE_FIXTURE = File.join(ROOT, "test/fixtures/handoff-adapter-profile-valid.yaml")
  ADAPTER_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/handoff-adapter-selection-proposal-valid.yaml")

  def test_valid_selection_proposal_previews_profile_without_selecting_or_dispatching
    with_ten_files do |paths|
      preview = adapter_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "Handoff Adapter 选择提案待确认，尚未选择或交付"
      assert_includes copy, "已审查的本地文件候选 Adapter"
      assert_includes copy, "本地摘要回执"
      assert_includes copy, "本地文件写入：未授权"
      assert_includes copy, "Envelope 是否包含个人数据仍未知"
      assert_includes copy, "Envelope 是否包含密钥仍未知"
      assert_includes copy, "Adapter 未选择"
      assert_includes copy, "均未获授权"
    end
  end

  def test_valid_bounded_cost_profile_preserves_explicit_effect_authorizations
    with_ten_files do |paths|
      mutate_yaml(paths.fetch(8)) do |profile|
        profile.fetch("capabilities")["delivery_mode"] = "remote_api"
        profile.fetch("capabilities")["receipt_mode"] = "provider_receipt"
        profile.dig("capabilities", "idempotency")["supported"] = false
        profile.dig("capabilities", "idempotency")["key_source"] = "not_applicable"
        profile.dig("capabilities", "retry")["mode"] = "bounded"
        profile.dig("capabilities", "retry")["maximum_attempts"] = 3
        %w[network_access external_service_write cost_incurred].each do |effect|
          profile.fetch("effects")[effect] = true
          profile.dig("authorization_requirements", "required_effect_authorizations") << effect
        end
        profile.fetch("cost_policy")["can_incur_cost"] = true
        profile.fetch("cost_policy")["disclosure_required_before_dispatch"] = true
      end
      refresh_profile_digest(paths)
      preview = adapter_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "渠道回执"
      assert_includes copy, "重试上限：3 次"
      assert_includes copy, "网络访问：未授权"
      assert_includes copy, "修改外部服务：未授权"
      assert_includes copy, "产生费用：未授权"
    end
  end

  def test_complete_envelope_lineage_is_replayed_before_selection
    digest_fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
      handoff_confirmation_receipt_file_sha256
    ]
    digest_fields.each_with_index do |field, index|
      with_ten_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_exact_envelope_and_profile_bytes_are_bound
    [[7, "handoff_envelope_file_sha256"], [8, "adapter_profile_file_sha256"]].each do |index, field|
      with_ten_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# semantically equivalent drift\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_each_proposal_binding_must_match_exact_inputs
    replacements = {
      "envelope_id" => "handoff-envelope-20260821-999",
      "handoff_envelope_file_sha256" => "1" * 64,
      "envelope_delivery_state" => "delivered",
      "recipient" => "research_agent",
      "adapter_profile_id" => "adapter-profile-20260822-999",
      "adapter_profile_file_sha256" => "2" * 64,
      "adapter_profile_status" => "draft"
    }
    replacements.each do |field, value|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(9)) { |proposal| proposal[field] = value }
        preview = adapter_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") }, preview.errors.join("\n")
      end
    end
  end

  def test_proposal_remains_pending_and_cannot_expand_authority
    replacements = {
      "status" => "confirmed",
      "adapter_selected" => true,
      "dispatch_authorized" => true,
      "external_effects_authorized" => true,
      "high_risk_authorization_inferred" => true
    }
    replacements.each do |field, value|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(9)) { |proposal| proposal.fetch("confirmation")[field] = value }

        assert_invalid(paths, "expected constant")
      end
    end
  end

  def test_only_reviewed_profile_can_enter_selection
    %w[draft retired].each do |status|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(8)) { |profile| profile["status"] = status }
        refresh_profile_digest(paths)

        assert_invalid(paths, "must be reviewed before selection")
      end
    end
  end

  def test_effect_authorizations_exactly_match_true_effects
    with_ten_files do |paths|
      mutate_yaml(paths.fetch(8)) do |profile|
        profile.dig("effects")["network_access"] = true
      end
      refresh_profile_digest(paths)

      assert_invalid(paths, "must exactly match every declared true effect")
    end
  end

  def test_idempotency_contract_rejects_both_inconsistent_directions
    mutations = [
      lambda { |profile| profile.dig("capabilities", "idempotency")["key_source"] = "not_applicable" },
      lambda do |profile|
        profile.dig("capabilities", "idempotency")["supported"] = false
        profile.dig("capabilities", "idempotency")["key_source"] = "provider_key"
      end
    ]
    mutations.each do |mutation|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(8), &mutation)
        refresh_profile_digest(paths)

        assert_invalid(paths, "idempotency")
      end
    end
  end

  def test_retry_contract_covers_none_and_bounded_invalid_transitions
    mutations = [
      lambda { |profile| profile.dig("capabilities", "retry")["maximum_attempts"] = 2 },
      lambda { |profile| profile.dig("capabilities", "retry")["mode"] = "bounded" }
    ]
    mutations.each do |mutation|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(8), &mutation)
        refresh_profile_digest(paths)

        assert_invalid(paths, "retry")
      end
    end
  end

  def test_reviewed_profile_requires_a_receipt
    with_ten_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile.fetch("capabilities")["receipt_mode"] = "none" }
      refresh_profile_digest(paths)

      assert_invalid(paths, "must declare a receipt mode")
    end
  end

  def test_profile_review_cannot_predate_profile_creation
    with_ten_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["reviewed_at"] = "2026-08-22T18:18:59+08:00" }
      refresh_profile_digest(paths)

      assert_invalid(paths, "review cannot predate Profile creation")
    end
  end

  def test_cost_policy_matches_effect_and_requires_disclosure
    mutations = [
      lambda { |profile| profile.fetch("cost_policy")["can_incur_cost"] = true },
      lambda do |profile|
        profile.fetch("effects")["cost_incurred"] = true
        profile.dig("authorization_requirements", "required_effect_authorizations") << "cost_incurred"
        profile.fetch("cost_policy")["can_incur_cost"] = true
      end
    ]
    expected = ["cost policy must match", "requires disclosure"]
    mutations.zip(expected).each do |mutation, error|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(8), &mutation)
        refresh_profile_digest(paths)

        assert_invalid(paths, error)
      end
    end
  end

  def test_profile_and_proposal_cannot_downgrade_envelope_classification
    with_ten_files(envelope_classification: "restricted") do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile.fetch("data_policy")["maximum_data_classification"] = "public" }
      refresh_profile_digest(paths)

      assert_invalid(paths, "does not accept the Envelope classification")
    end
    with_ten_files(envelope_classification: "restricted") do |paths|
      mutate_yaml(paths.fetch(9)) { |proposal| proposal["data_classification"] = "public" }

      assert_invalid(paths, "cannot downgrade the Envelope")
    end
  end

  def test_proposal_cannot_predate_envelope_or_profile
    with_ten_files do |paths|
      mutate_yaml(paths.fetch(9)) { |proposal| proposal["created_at"] = "2026-08-22T18:19:59+08:00" }

      assert_invalid(paths, "cannot predate its Envelope or Profile")
    end
  end

  def test_compatibility_unknowns_cannot_be_claimed_as_compatible
    %w[personal_data secrets].each do |field|
      with_ten_files do |paths|
        mutate_yaml(paths.fetch(9)) { |proposal| proposal.dig("compatibility")[field] = "compatible" }

        assert_invalid(paths, "expected constant \"unknown\"")
      end
    end
  end

  def test_malformed_profile_and_proposal_are_rejected_without_source_echo
    [8, 9].each do |index|
      with_ten_files do |paths|
        File.open(paths.fetch(index), "wb") { |file| file.write("display_name: [unterminated\n") }
        preview = adapter_preview

        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
        refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
      end
    end
  end

  def test_success_copy_is_markdown_safe_and_hides_lineage_content
    with_ten_files do |paths|
      mutate_yaml(paths.fetch(8)) { |profile| profile["display_name"] = "<script>_adapter_</script> [link](https://invalid.example)" }
      refresh_profile_digest(paths)
      preview = adapter_preview
      copy = preview.preview_files(*paths)
      session = load_yaml(paths.fetch(0))
      envelope = load_yaml(paths.fetch(7))
      profile = load_yaml(paths.fetch(8))
      proposal = load_yaml(paths.fetch(9))

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_adapter\\_&lt;/script&gt;"
      assert_includes copy, "\\[link\\](https://invalid.example)"
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, envelope.dig("prompt_package", "knowledge", "evidence", 0, "source")
      refute_includes copy, envelope["envelope_id"]
      refute_includes copy, profile["adapter_profile_id"]
      refute_includes copy, proposal["adapter_selection_proposal_id"]
      refute_includes copy, proposal["handoff_envelope_file_sha256"]
      refute_includes copy, "constraints.product"
    end
  end

  def test_cli_reads_all_ten_inputs_without_writing
    with_ten_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_adapter_selection.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Handoff Adapter 选择提案待确认"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_adapter_selection.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_ten_files(envelope_classification: nil)
    Dir.mktmpdir("pmind-adapter-selection") do |directory|
      yield write_ten_files(directory, envelope_classification: envelope_classification)
    end
  end

  def write_ten_files(directory, envelope_classification: nil)
    documents = [
      SESSION_FIXTURE,
      PACKAGE_FIXTURE,
      COMPILATION_PROPOSAL_FIXTURE,
      COMPILATION_CONFIRMATION_FIXTURE,
      HANDOFF_PROPOSAL_FIXTURE,
      HANDOFF_CONFIRMATION_FIXTURE,
      ADAPTER_PROFILE_FIXTURE,
      ADAPTER_PROPOSAL_FIXTURE
    ].map { |path| load_yaml(path) }
    session, package, compilation_proposal, compilation_confirmation, handoff_proposal, handoff_confirmation, profile, proposal = documents
    paths = %w[
      session-revision.yaml
      draft-package.yaml
      compilation-proposal.yaml
      compilation-confirmation.yaml
      final-package.yaml
      handoff-proposal.yaml
      handoff-confirmation.yaml
      handoff-envelope.yaml
      adapter-profile.yaml
      adapter-selection-proposal.yaml
    ].map { |name| File.join(directory, name) }

    write_yaml(paths.fetch(0), session)
    write_yaml(paths.fetch(1), package)
    compilation_proposal["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    compilation_proposal["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    write_yaml(paths.fetch(2), compilation_proposal)
    compilation_confirmation["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    compilation_confirmation["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    compilation_confirmation["compilation_proposal_file_sha256"] = Digest::SHA256.file(paths.fetch(2)).hexdigest
    write_yaml(paths.fetch(3), compilation_confirmation)

    package_creator = PMind::PromptPackageCreator.new(ROOT)
    raise package_creator.errors.join("\n") unless package_creator.create_files(*paths.first(4), paths.fetch(4))
    final_package = load_yaml(paths.fetch(4))
    handoff_proposal["package_id"] = final_package["package_id"]
    handoff_proposal["final_package_file_sha256"] = Digest::SHA256.file(paths.fetch(4)).hexdigest
    handoff_proposal["package_handoff_ready"] = final_package.dig("handoff", "ready")
    handoff_proposal["recipient"] = final_package.dig("handoff", "recipient")
    write_yaml(paths.fetch(5), handoff_proposal)

    digest_fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
    ]
    paths.first(6).zip(digest_fields).each do |source_path, field|
      handoff_confirmation[field] = Digest::SHA256.file(source_path).hexdigest
    end
    handoff_confirmation["package_id"] = final_package["package_id"]
    handoff_confirmation["handoff_proposal_id"] = handoff_proposal["handoff_proposal_id"]
    handoff_confirmation["package_handoff_ready"] = final_package.dig("handoff", "ready")
    handoff_confirmation["recipient"] = final_package.dig("handoff", "recipient")
    handoff_confirmation["handoff_proposal_status"] = handoff_proposal.dig("confirmation", "status")
    handoff_confirmation["data_classification"] = envelope_classification if envelope_classification
    write_yaml(paths.fetch(6), handoff_confirmation)

    envelope_creator = PMind::HandoffEnvelopeCreator.new(ROOT)
    raise envelope_creator.errors.join("\n") unless envelope_creator.create_files(*paths.first(7), paths.fetch(7))
    write_yaml(paths.fetch(8), profile)
    write_yaml(paths.fetch(9), proposal)
    refresh_proposal_bindings(paths)
    paths
  end

  def refresh_proposal_bindings(paths)
    envelope = load_yaml(paths.fetch(7))
    profile = load_yaml(paths.fetch(8))
    proposal = load_yaml(paths.fetch(9))
    proposal["envelope_id"] = envelope["envelope_id"]
    proposal["handoff_envelope_file_sha256"] = Digest::SHA256.file(paths.fetch(7)).hexdigest
    proposal["envelope_delivery_state"] = envelope["delivery_state"]
    proposal["recipient"] = envelope["recipient"]
    proposal["adapter_profile_id"] = profile["adapter_profile_id"]
    proposal["adapter_profile_file_sha256"] = Digest::SHA256.file(paths.fetch(8)).hexdigest
    proposal["data_classification"] = envelope["data_classification"]
    write_yaml(paths.fetch(9), proposal)
  end

  def refresh_profile_digest(paths)
    proposal = load_yaml(paths.fetch(9))
    proposal["adapter_profile_file_sha256"] = Digest::SHA256.file(paths.fetch(8)).hexdigest
    write_yaml(paths.fetch(9), proposal)
  end

  def mutate_yaml(path)
    document = load_yaml(path)
    yield document
    write_yaml(path, document)
  end

  def assert_invalid(paths, expected_error)
    preview = adapter_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def adapter_preview
    PMind::HandoffAdapterSelectionPreview.new(ROOT)
  end

  def write_yaml(path, document)
    File.open(path, "wb", 0o600) { |file| file.write(YAML.dump(document)) }
  end

  def load_yaml(path)
    YAML.safe_load(
      File.read(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end
end
