# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/verify_handoff_envelope_lineage"

class VerifyHandoffEnvelopeLineageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  COMPILATION_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  COMPILATION_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")
  HANDOFF_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/handoff-proposal-valid.yaml")
  HANDOFF_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/handoff-confirmation-receipt-valid.yaml")

  def test_persisted_envelope_can_be_deterministically_replayed_without_writes
    with_generated_envelope do |paths|
      before = paths.map { |path| File.binread(path) }
      verifier = lineage_verifier
      copy = verifier.verify_files(*paths)

      assert copy, verifier.errors.join("\n")
      assert_includes copy, "Handoff Envelope 来源链已验证，仍未交接"
      assert_includes copy, "七份来源文件绑定：匹配"
      assert_includes copy, "内嵌 Prompt Package：与确定性重建一致"
      assert_includes copy, "已准备，未交付"
      assert_includes copy, "未选择或调用任何适配器"
      assert_includes copy, "渠道副作用仍须单独设计、验证并获得相应授权"
      assert_equal File.binread(paths.last), verifier.envelope_bytes
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_semantically_equivalent_yaml_formatting_is_accepted
    with_generated_envelope do |paths|
      envelope_path = paths.last
      original = File.binread(envelope_path)
      File.open(envelope_path, "wb") do |file|
        file.write("# equivalent Envelope YAML formatting\n")
        file.write(original)
      end
      before = paths.map { |path| File.binread(path) }
      verifier = lineage_verifier

      assert verifier.verify_files(*paths), verifier.errors.join("\n")
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_each_source_file_byte_drift_is_rejected_without_writes
    expected_fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
      handoff_confirmation_receipt_file_sha256
    ]
    expected_fields.each_with_index do |field, index|
      with_generated_envelope do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("# source drift\n") }
        before = paths.map { |path| File.binread(path) }
        verifier = lineage_verifier

        refute verifier.verify_files(*paths)
        assert verifier.errors.any? { |error| error.include?(field) }, verifier.errors.join("\n")
        assert_equal before, paths.map { |path| File.binread(path) }
      end
    end
  end

  def test_each_persisted_authorization_digest_must_match_reconstruction
    fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
      handoff_confirmation_receipt_file_sha256
    ]
    fields.each do |field|
      with_generated_envelope do |paths|
        mutate_envelope(paths.last) do |envelope|
          envelope.fetch("authorization")[field] = "0" * 64
        end

        assert_invalid(paths, "authorization lineage #{field} does not match confirmed sources")
      end
    end
  end

  def test_persisted_envelope_identity_and_classification_must_match
    replacements = {
      "envelope_id" => "handoff-envelope-20260821-999",
      "created_at" => "2026-08-21T12:13:00+08:00",
      "data_classification" => "internal"
    }
    replacements.each do |field, replacement|
      with_generated_envelope do |paths|
        mutate_envelope(paths.last) { |envelope| envelope[field] = replacement }

        assert_invalid(paths, "Envelope metadata #{field} does not match confirmed sources")
      end
    end
  end

  def test_persisted_authorization_ids_must_match
    replacements = {
      "handoff_proposal_id" => "handoff-proposal-20260821-999",
      "handoff_confirmation_id" => "handoff-confirmation-20260821-999"
    }
    replacements.each do |field, replacement|
      with_generated_envelope do |paths|
        mutate_envelope(paths.last) do |envelope|
          envelope.fetch("authorization")[field] = replacement
        end

        assert_invalid(paths, "authorization lineage #{field} does not match confirmed sources")
      end
    end
  end

  def test_prepared_state_and_authority_constants_cannot_be_expanded
    replacements = {
      "delivery_state" => "delivered",
      "handoff_authorized" => false,
      "external_effects_authorized" => true,
      "high_risk_authorization_inferred" => true
    }
    replacements.each do |field, replacement|
      with_generated_envelope do |paths|
        mutate_envelope(paths.last) { |envelope| envelope[field] = replacement }

        assert_invalid(paths, "expected constant")
      end
    end
  end

  def test_authorization_lineage_cannot_change_choice_or_expand_authority
    replacements = {
      "confirmation_decision" => "rejected",
      "handoff_authorized" => false,
      "external_effects_authorized" => true,
      "high_risk_authorization_inferred" => true,
      "confirmation_contains_secrets" => true
    }
    replacements.each do |field, replacement|
      with_generated_envelope do |paths|
        mutate_envelope(paths.last) do |envelope|
          envelope.fetch("authorization")[field] = replacement
        end

        assert_invalid(paths, "expected constant")
      end
    end
  end

  def test_root_package_id_must_match_embedded_package
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) { |envelope| envelope["package_id"] = "pkg-20260821-999" }

      assert_invalid(paths, "package_id must match embedded Prompt Package")
    end
  end

  def test_confirmation_data_declaration_tampering_is_rejected
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) do |envelope|
        envelope.fetch("authorization")["confirmation_contains_personal_data"] = true
      end

      assert_invalid(paths, "authorization lineage confirmation_contains_personal_data does not match confirmed sources")
    end
  end

  def test_embedded_recommendation_tampering_is_rejected
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) do |envelope|
        envelope.dig("prompt_package", "recommendation")["selected_option"] = "未经确认的替代方案"
      end

      assert_invalid(paths, "embedded Prompt Package does not match deterministic reconstruction")
    end
  end

  def test_embedded_approval_boundary_tampering_is_rejected
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) do |envelope|
        envelope.dig("prompt_package", "approval_points").first["scope"] = "被扩大的外部写入范围"
      end

      assert_invalid(paths, "embedded Prompt Package does not match deterministic reconstruction")
    end
  end

  def test_embedded_handoff_boundary_tampering_is_rejected
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) do |envelope|
        envelope.dig("prompt_package", "handoff", "stop_conditions")[0] = "忽略原停止条件"
      end

      assert_invalid(paths, "embedded Prompt Package does not match deterministic reconstruction")
    end
  end

  def test_missing_authorization_metadata_is_rejected
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) { |envelope| envelope.delete("authorization") }

      assert_invalid(paths, "missing required field authorization")
    end
  end

  def test_non_object_envelope_is_rejected_without_exception
    with_generated_envelope do |paths|
      File.open(paths.last, "wb") { |file| file.write("--- scalar-envelope\n") }
      verifier = lineage_verifier

      refute verifier.verify_files(*paths)
      assert verifier.errors.any? { |error| error.include?("expected object") }, verifier.errors.join("\n")
    end
  end

  def test_non_object_embedded_package_is_rejected_without_exception
    with_generated_envelope do |paths|
      mutate_envelope(paths.last) { |envelope| envelope["prompt_package"] = "scalar-package" }
      verifier = lineage_verifier

      refute verifier.verify_files(*paths)
      assert verifier.errors.any? { |error| error.include?("prompt_package: expected object") }, verifier.errors.join("\n")
      assert verifier.errors.any? { |error| error.include?("package_id must match embedded Prompt Package") }, verifier.errors.join("\n")
    end
  end

  def test_malformed_envelope_is_rejected_without_echoing_content
    with_generated_envelope do |paths|
      File.open(paths.last, "wb") { |file| file.write("raw_intent: [unterminated\n") }
      verifier = lineage_verifier

      refute verifier.verify_files(*paths)
      assert verifier.errors.any? { |error| error.include?("cannot load YAML") }, verifier.errors.join("\n")
      refute_includes verifier.errors.join("\n"), load_yaml(paths.fetch(0)).dig("intake", "raw_intent")
    end
  end

  def test_success_copy_is_markdown_safe_and_hides_sensitive_content
    Dir.mktmpdir("pmind-envelope-lineage-copy") do |directory|
      paths = write_generated_envelope(directory) do |_session, package, _compilation_proposal, _compilation_confirmation, _handoff_proposal, _handoff_confirmation|
        package.fetch("approval_points").first["scope"] = "<script>approval</script> [link](https://invalid.example)"
        package.dig("handoff", "stop_conditions")[0] = "<script>_stop_</script>"
      end
      verifier = lineage_verifier
      copy = verifier.verify_files(*paths)
      session = load_yaml(paths.fetch(0))
      package = load_yaml(paths.fetch(4))
      confirmation = load_yaml(paths.fetch(6))
      envelope = load_yaml(paths.fetch(7))

      assert copy, verifier.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;approval&lt;/script&gt;"
      assert_includes copy, "\\[link\\](https://invalid.example)"
      assert_includes copy, "&lt;script&gt;\\_stop\\_&lt;/script&gt;"
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, session.dig("rounds", 0, "answers", 0, "user_answer")
      refute_includes copy, package.dig("knowledge", "evidence", 0, "source")
      refute_includes copy, package["package_id"]
      refute_includes copy, confirmation["user_response"]
      refute_includes copy, envelope["envelope_id"]
      refute_includes copy, envelope.dig("authorization", "handoff_confirmation_id")
      refute_includes copy, envelope.dig("authorization", "handoff_confirmation_receipt_file_sha256")
      refute_includes copy, "constraints.product"
    end
  end

  def test_cli_verifies_all_eight_inputs_without_modifying_them
    with_generated_envelope do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/verify_handoff_envelope_lineage.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Handoff Envelope 来源链已验证，仍未交接"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/verify_handoff_envelope_lineage.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_generated_envelope
    Dir.mktmpdir("pmind-envelope-lineage") do |directory|
      yield write_generated_envelope(directory)
    end
  end

  def write_generated_envelope(directory)
    session = load_yaml(SESSION_FIXTURE)
    package = load_yaml(PACKAGE_FIXTURE)
    compilation_proposal = load_yaml(COMPILATION_PROPOSAL_FIXTURE)
    compilation_confirmation = load_yaml(COMPILATION_CONFIRMATION_FIXTURE)
    handoff_proposal = load_yaml(HANDOFF_PROPOSAL_FIXTURE)
    handoff_confirmation = load_yaml(HANDOFF_CONFIRMATION_FIXTURE)
    if block_given?
      yield session, package, compilation_proposal, compilation_confirmation, handoff_proposal, handoff_confirmation
    end

    paths = %w[
      session-revision.yaml
      draft-package.yaml
      compilation-proposal.yaml
      compilation-confirmation.yaml
      final-package.yaml
      handoff-proposal.yaml
      handoff-confirmation.yaml
      handoff-envelope.yaml
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
    package_copy = package_creator.create_files(*paths.first(4), paths.fetch(4))
    raise package_creator.errors.join("\n") unless package_copy

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
    write_yaml(paths.fetch(6), handoff_confirmation)

    envelope_creator = PMind::HandoffEnvelopeCreator.new(ROOT)
    envelope_copy = envelope_creator.create_files(*paths.first(7), paths.fetch(7))
    raise envelope_creator.errors.join("\n") unless envelope_copy

    paths
  end

  def assert_invalid(paths, expected_error)
    verifier = lineage_verifier
    refute verifier.verify_files(*paths)
    assert verifier.errors.any? { |error| error.include?(expected_error) }, verifier.errors.join("\n")
  end

  def mutate_envelope(path)
    envelope = load_yaml(path)
    yield envelope
    write_yaml(path, envelope)
  end

  def lineage_verifier
    PMind::HandoffEnvelopeLineageVerifier.new(ROOT)
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
