# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/create_handoff_envelope"

class CreateHandoffEnvelopeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  COMPILATION_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  COMPILATION_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")
  HANDOFF_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/handoff-proposal-valid.yaml")
  HANDOFF_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/handoff-confirmation-receipt-valid.yaml")

  def test_confirmed_receipt_creates_valid_prepared_envelope_without_modifying_sources
    with_chain do |paths, directory|
      before = paths.map { |path| File.binread(path) }
      output = File.join(directory, "handoff-envelope.yaml")
      creator = envelope_creator
      copy = creator.create_files(*paths, output)

      assert copy, creator.errors.join("\n")
      assert_includes copy, "Handoff Envelope 已创建，尚未交接"
      assert_includes copy, "已准备，未交付"
      assert_includes copy, "未启动 Downstream Executor"
      assert_includes copy, "Handoff Envelope lineage verifier"
      assert_includes copy, "Adapter 契约探索"
      assert_includes copy, "任何真实交付或外部效果仍需"
      refute_includes copy, "尚未实现"
      assert File.file?(output)
      assert_equal 0o600, File.stat(output).mode & 0o777

      envelope = load_yaml(output)
      assert_valid_envelope(envelope, output)
      assert_equal "handoff-envelope-20260821-001", envelope["envelope_id"]
      assert_equal "2026-08-21T12:12:00+08:00", envelope["created_at"]
      assert_equal "prepared", envelope["delivery_state"]
      assert_equal true, envelope["handoff_authorized"]
      assert_equal false, envelope["external_effects_authorized"]
      assert_equal false, envelope["high_risk_authorization_inferred"]
      assert_equal "handoff-proposal-20260821-001", envelope.dig("authorization", "handoff_proposal_id")
      assert_equal "handoff-confirmation-20260821-001", envelope.dig("authorization", "handoff_confirmation_id")
      assert_equal load_yaml(paths.fetch(4)), envelope["prompt_package"]

      digest_fields = %w[
        source_session_file_sha256
        draft_package_file_sha256
        compilation_proposal_file_sha256
        compilation_confirmation_receipt_file_sha256
        final_package_file_sha256
        handoff_proposal_file_sha256
        handoff_confirmation_receipt_file_sha256
      ]
      paths.zip(digest_fields).each do |source_path, field|
        assert_equal Digest::SHA256.file(source_path).hexdigest, envelope.dig("authorization", field)
      end
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_creation_is_deterministic_for_same_confirmed_inputs
    with_chain do |paths, directory|
      first = File.join(directory, "first-envelope.yaml")
      second = File.join(directory, "second-envelope.yaml")

      assert envelope_creator.create_files(*paths, first)
      assert envelope_creator.create_files(*paths, second)
      assert_equal File.binread(first), File.binread(second)
    end
  end

  def test_existing_output_is_never_overwritten
    with_chain do |paths, directory|
      output = File.join(directory, "existing.yaml")
      File.open(output, "wb") { |file| file.write("sentinel\n") }
      creator = envelope_creator

      refute creator.create_files(*paths, output)
      assert_includes creator.errors.join("\n"), "refusing to overwrite"
      assert_equal "sentinel\n", File.binread(output)
    end
  end

  def test_modify_requested_never_creates_envelope
    assert_non_creation_choice("modify_requested", "请修改交接范围。")
  end

  def test_rejected_never_creates_envelope
    assert_non_creation_choice("rejected", "拒绝本次交接。")
  end

  def test_stale_source_causes_zero_writes
    with_chain do |paths, directory|
      File.open(paths.fetch(4), "ab") { |file| file.write("# stale final Package\n") }
      output = File.join(directory, "must-not-exist.yaml")
      creator = envelope_creator

      refute creator.create_files(*paths, output)
      assert creator.errors.any? { |error| error.include?("final_package_file_sha256") }, creator.errors.join("\n")
      refute File.exist?(output)
    end
  end

  def test_envelope_binds_exact_confirmation_receipt_bytes
    with_chain do |paths, directory|
      File.open(paths.fetch(6), "ab") { |file| file.write("# equivalent receipt YAML\n") }
      output = File.join(directory, "handoff-envelope.yaml")
      creator = envelope_creator

      assert creator.create_files(*paths, output), creator.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(6)).hexdigest,
                   load_yaml(output).dig("authorization", "handoff_confirmation_receipt_file_sha256")
    end
  end

  def test_data_declarations_are_preserved_without_raw_confirmation_response
    with_chain do |paths, directory|
      receipt = load_yaml(paths.fetch(6))
      receipt["data_classification"] = "confidential"
      receipt["contains_personal_data"] = true
      write_yaml(paths.fetch(6), receipt)
      output = File.join(directory, "handoff-envelope.yaml")
      creator = envelope_creator

      assert creator.create_files(*paths, output), creator.errors.join("\n")
      envelope = load_yaml(output)
      assert_equal "confidential", envelope["data_classification"]
      assert_equal true, envelope.dig("authorization", "confirmation_contains_personal_data")
      assert_equal false, envelope.dig("authorization", "confirmation_contains_secrets")
      refute envelope.key?("contains_personal_data")
      refute_includes YAML.dump(envelope), receipt["user_response"]
    end
  end

  def test_missing_output_directory_leaves_no_artifact
    with_chain do |paths, directory|
      output = File.join(directory, "missing", "handoff-envelope.yaml")
      creator = envelope_creator

      refute creator.create_files(*paths, output)
      assert_includes creator.errors.join("\n"), "cannot create Handoff Envelope"
      refute File.exist?(output)
    end
  end

  def test_success_copy_is_markdown_safe_and_hides_sensitive_content
    with_chain do |paths, directory|
      rebuild_chain(paths) do |_session, package, _compilation_proposal, _compilation_confirmation, _handoff_proposal, _handoff_confirmation|
        package.fetch("approval_points").first["scope"] = "<script>approval</script> [link](https://invalid.example)"
        package.dig("handoff", "stop_conditions")[0] = "<script>_stop_</script>"
      end
      output = File.join(directory, "handoff-envelope.yaml")
      creator = envelope_creator
      copy = creator.create_files(*paths, output)
      session = load_yaml(paths.fetch(0))
      package = load_yaml(paths.fetch(4))
      confirmation = load_yaml(paths.fetch(6))

      assert copy, creator.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;approval&lt;/script&gt;"
      assert_includes copy, "\\[link\\](https://invalid.example)"
      assert_includes copy, "&lt;script&gt;\\_stop\\_&lt;/script&gt;"
      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, session.dig("rounds", 0, "answers", 0, "user_answer")
      refute_includes copy, package.dig("knowledge", "evidence", 0, "source")
      refute_includes copy, package["package_id"]
      refute_includes copy, confirmation["handoff_confirmation_id"]
      refute_includes copy, confirmation["user_response"]
      refute_includes copy, confirmation["user_response_sha256"]
      refute_includes copy, "constraints.product"
    end
  end

  def test_cli_creates_valid_envelope_without_delivering_it
    with_chain do |paths, directory|
      output = File.join(directory, "handoff-envelope.yaml")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/create_handoff_envelope.rb"),
        *paths,
        output,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Handoff Envelope 已创建，尚未交接"
      assert_includes stdout, "已准备，未交付"
      refute_includes stdout, "已交付"
      assert_equal "", stderr
      assert_valid_envelope(load_yaml(output), output)
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/create_handoff_envelope.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_chain
    Dir.mktmpdir("pmind-handoff-envelope") do |directory|
      paths = write_chain(directory)
      yield paths, directory
    end
  end

  def write_chain(directory)
    paths = %w[
      session-revision.yaml
      draft-package.yaml
      compilation-proposal.yaml
      compilation-confirmation.yaml
      final-package.yaml
      handoff-proposal.yaml
      handoff-confirmation.yaml
    ].map { |name| File.join(directory, name) }
    sources = [
      SESSION_FIXTURE,
      PACKAGE_FIXTURE,
      COMPILATION_PROPOSAL_FIXTURE,
      COMPILATION_CONFIRMATION_FIXTURE,
      HANDOFF_PROPOSAL_FIXTURE,
      HANDOFF_CONFIRMATION_FIXTURE
    ]
    source_targets = [paths.fetch(0), paths.fetch(1), paths.fetch(2), paths.fetch(3), paths.fetch(5), paths.fetch(6)]
    sources.zip(source_targets).each { |source, target| FileUtils.cp(source, target) }
    create_final_package(paths)
    refresh_handoff_proposal(paths)
    refresh_handoff_confirmation(paths)
    paths
  end

  def rebuild_chain(paths)
    session = load_yaml(paths.fetch(0))
    package = load_yaml(paths.fetch(1))
    compilation_proposal = load_yaml(paths.fetch(2))
    compilation_confirmation = load_yaml(paths.fetch(3))
    handoff_proposal = load_yaml(paths.fetch(5))
    handoff_confirmation = load_yaml(paths.fetch(6))
    yield session, package, compilation_proposal, compilation_confirmation, handoff_proposal, handoff_confirmation

    write_yaml(paths.fetch(0), session)
    write_yaml(paths.fetch(1), package)
    compilation_proposal["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    compilation_proposal["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    write_yaml(paths.fetch(2), compilation_proposal)
    compilation_confirmation["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    compilation_confirmation["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    compilation_confirmation["compilation_proposal_file_sha256"] = Digest::SHA256.file(paths.fetch(2)).hexdigest
    write_yaml(paths.fetch(3), compilation_confirmation)
    File.delete(paths.fetch(4)) if File.exist?(paths.fetch(4))
    create_final_package(paths)
    write_yaml(paths.fetch(5), handoff_proposal)
    refresh_handoff_proposal(paths)
    write_yaml(paths.fetch(6), handoff_confirmation)
    refresh_handoff_confirmation(paths)
  end

  def create_final_package(paths)
    creator = PMind::PromptPackageCreator.new(ROOT)
    copy = creator.create_files(*paths.first(4), paths.fetch(4))
    raise creator.errors.join("\n") unless copy
  end

  def refresh_handoff_proposal(paths)
    proposal = load_yaml(paths.fetch(5))
    package = load_yaml(paths.fetch(4))
    proposal["package_id"] = package["package_id"]
    proposal["final_package_file_sha256"] = Digest::SHA256.file(paths.fetch(4)).hexdigest
    proposal["package_handoff_ready"] = package.dig("handoff", "ready")
    proposal["recipient"] = package.dig("handoff", "recipient")
    write_yaml(paths.fetch(5), proposal)
  end

  def refresh_handoff_confirmation(paths)
    receipt = load_yaml(paths.fetch(6))
    package = load_yaml(paths.fetch(4))
    proposal = load_yaml(paths.fetch(5))
    fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
    ]
    paths.first(6).zip(fields).each do |source_path, field|
      receipt[field] = Digest::SHA256.file(source_path).hexdigest
    end
    receipt["package_id"] = package["package_id"]
    receipt["handoff_proposal_id"] = proposal["handoff_proposal_id"]
    receipt["package_handoff_ready"] = package.dig("handoff", "ready")
    receipt["recipient"] = package.dig("handoff", "recipient")
    receipt["handoff_proposal_status"] = proposal.dig("confirmation", "status")
    write_yaml(paths.fetch(6), receipt)
  end

  def assert_non_creation_choice(decision, response)
    with_chain do |paths, directory|
      receipt = load_yaml(paths.fetch(6))
      receipt["confirmation_decision"] = decision
      receipt["handoff_authorized"] = false
      receipt["user_response"] = response
      receipt["user_response_sha256"] = Digest::SHA256.hexdigest(response)
      write_yaml(paths.fetch(6), receipt)
      output = File.join(directory, "must-not-exist.yaml")
      creator = envelope_creator

      refute creator.create_files(*paths, output)
      assert_includes creator.errors.join("\n"), "does not authorize Handoff Envelope creation"
      refute File.exist?(output)
    end
  end

  def assert_valid_envelope(envelope, path)
    validator = PMind::EvalValidator.new(ROOT)
    schema = validator.load_yaml("schemas/handoff-envelope-v0.yaml")
    validator.validate_document(schema, envelope, path, schema)
    assert_empty validator.errors, validator.errors.join("\n")

    package_validator = PMind::PromptPackageValidator.new(ROOT)
    assert package_validator.validate(envelope["prompt_package"], "#{path}.prompt_package"), package_validator.errors.join("\n")
  end

  def envelope_creator
    PMind::HandoffEnvelopeCreator.new(ROOT)
  end

  def load_yaml(path)
    YAML.safe_load(
      File.read(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def write_yaml(path, document)
    File.open(path, "wb", 0o600) { |file| file.write(YAML.dump(document)) }
  end
end
