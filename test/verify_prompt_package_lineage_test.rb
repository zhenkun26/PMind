# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/verify_prompt_package_lineage"

class VerifyPromptPackageLineageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")

  def test_persisted_package_can_be_deterministically_replayed_without_writes
    with_generated_package do |paths|
      before = paths.map { |path| File.binread(path) }
      verifier = lineage_verifier
      copy = verifier.verify_files(*paths)

      assert copy, verifier.errors.join("\n")
      assert_includes copy, "Prompt Package 来源链已验证"
      assert_includes copy, "Package 内容：与确定性重建一致"
      assert_includes copy, "可以进入受控 Handoff 决策"
      assert_includes copy, "不执行或授权 Handoff"
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_semantically_equivalent_yaml_formatting_is_accepted
    with_generated_package do |paths|
      package_path = paths.last
      original = File.binread(package_path)
      File.open(package_path, "wb") do |file|
        file.write("# equivalent YAML formatting\n")
        file.write(original)
      end
      before = paths.map { |path| File.binread(path) }

      verifier = lineage_verifier
      assert verifier.verify_files(*paths), verifier.errors.join("\n")
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_each_source_file_byte_drift_is_rejected
    expected_fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
    ]
    expected_fields.each_with_index do |field, index|
      with_generated_package do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("\n") }
        verifier = lineage_verifier

        refute verifier.verify_files(*paths)
        assert verifier.errors.any? { |error| error.include?(field) }, verifier.errors.join("\n")
      end
    end
  end

  def test_each_persisted_lineage_digest_must_match_reconstruction
    fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
    ]
    fields.each do |field|
      with_generated_package do |paths|
        mutate_package(paths.last) { |package| package.fetch("compilation")[field] = "0" * 64 }

        assert_invalid(paths, "compilation lineage #{field} does not match confirmed sources")
      end
    end
  end

  def test_each_persisted_lineage_identity_must_match_reconstruction
    replacements = {
      "created_at" => "2026-08-21T12:07:00+08:00",
      "source_session_id" => "session-20260821-999",
      "source_session_revision_number" => 2,
      "compilation_proposal_id" => "compile-proposal-20260821-999",
      "compilation_confirmation_id" => "compile-confirmation-20260821-999"
    }
    replacements.each do |field, replacement|
      with_generated_package do |paths|
        mutate_package(paths.last) { |package| package.fetch("compilation")[field] = replacement }

        assert_invalid(paths, "compilation lineage #{field} does not match confirmed sources")
      end
    end
  end

  def test_recommendation_tampering_is_rejected
    with_generated_package do |paths|
      mutate_package(paths.last) do |package|
        package.fetch("recommendation")["selected_option"] = "未经确认的替代方案"
      end

      assert_invalid(paths, "persisted Package content does not match deterministic reconstruction")
    end
  end

  def test_approval_boundary_tampering_is_rejected
    with_generated_package do |paths|
      mutate_package(paths.last) do |package|
        package.fetch("approval_points").first["scope"] = "被扩大的外部写入范围"
      end

      assert_invalid(paths, "persisted Package content does not match deterministic reconstruction")
    end
  end

  def test_handoff_boundary_tampering_is_rejected
    with_generated_package do |paths|
      mutate_package(paths.last) do |package|
        package.dig("handoff", "stop_conditions")[0] = "忽略原停止条件"
      end

      assert_invalid(paths, "persisted Package content does not match deterministic reconstruction")
    end
  end

  def test_missing_compilation_metadata_is_rejected
    with_generated_package do |paths|
      mutate_package(paths.last) { |package| package.delete("compilation") }

      assert_invalid(paths, "persisted Package is missing compilation lineage metadata")
    end
  end

  def test_inferred_handoff_authorization_is_rejected
    with_generated_package do |paths|
      mutate_package(paths.last) do |package|
        package.fetch("compilation")["handoff_authorization_inferred"] = true
      end

      assert_invalid(paths, "expected constant false")
    end
  end

  def test_malformed_persisted_package_is_rejected_without_echoing_content
    with_generated_package do |paths|
      File.open(paths.last, "wb") { |file| file.write("raw_intent: [unterminated\n") }
      verifier = lineage_verifier

      refute verifier.verify_files(*paths)
      assert verifier.errors.any? { |error| error.include?("cannot load YAML") }, verifier.errors.join("\n")
      refute_includes verifier.errors.join("\n"), load_yaml(SESSION_FIXTURE).dig("intake", "raw_intent")
    end
  end

  def test_success_copy_is_markdown_safe_and_hides_internal_lineage
    Dir.mktmpdir("pmind-package-lineage-copy") do |directory|
      paths = write_generated_package(directory) do |_session, package, _proposal, _confirmation|
        package.fetch("approval_points").first["scope"] = "仅限 <script>x</script> [链接](https://invalid.example)"
      end
      copy = lineage_verifier.verify_files(*paths)
      confirmation = load_yaml(paths.fetch(3))

      assert_includes copy, "&lt;script&gt;x&lt;/script&gt;"
      assert_includes copy, "\\[链接\\](https://invalid.example)"
      refute_includes copy, confirmation["user_response"]
      refute_includes copy, confirmation["user_response_sha256"]
      refute_includes copy, confirmation["compilation_confirmation_id"]
      refute_includes copy, confirmation["compilation_proposal_id"]
      refute_includes copy, confirmation["source_session_file_sha256"]
      refute_includes copy, "product-owner-test"
      refute_includes copy, "constraints.product"
    end
  end

  def test_cli_verifies_a_persisted_package_without_modifying_it
    with_generated_package do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/verify_prompt_package_lineage.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Prompt Package 来源链已验证"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/verify_prompt_package_lineage.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_generated_package
    Dir.mktmpdir("pmind-package-lineage") do |directory|
      yield write_generated_package(directory)
    end
  end

  def write_generated_package(directory)
    session = load_yaml(SESSION_FIXTURE)
    package = load_yaml(PACKAGE_FIXTURE)
    proposal = load_yaml(PROPOSAL_FIXTURE)
    confirmation = load_yaml(CONFIRMATION_FIXTURE)
    yield session, package, proposal, confirmation if block_given?

    session_path = File.join(directory, "session-revision.yaml")
    package_path = File.join(directory, "draft-package.yaml")
    proposal_path = File.join(directory, "compilation-proposal.yaml")
    confirmation_path = File.join(directory, "compilation-confirmation.yaml")
    final_path = File.join(directory, "final-package.yaml")
    write_yaml(session_path, session)
    write_yaml(package_path, package)

    proposal["source_session_file_sha256"] = Digest::SHA256.file(session_path).hexdigest
    proposal["draft_package_file_sha256"] = Digest::SHA256.file(package_path).hexdigest
    write_yaml(proposal_path, proposal)

    confirmation["source_session_file_sha256"] = Digest::SHA256.file(session_path).hexdigest
    confirmation["draft_package_file_sha256"] = Digest::SHA256.file(package_path).hexdigest
    confirmation["compilation_proposal_file_sha256"] = Digest::SHA256.file(proposal_path).hexdigest
    write_yaml(confirmation_path, confirmation)

    creator = PMind::PromptPackageCreator.new(ROOT)
    created = creator.create_files(session_path, package_path, proposal_path, confirmation_path, final_path)
    raise creator.errors.join("\n") unless created

    [session_path, package_path, proposal_path, confirmation_path, final_path]
  end

  def assert_invalid(paths, expected_error)
    verifier = lineage_verifier
    refute verifier.verify_files(*paths)
    assert verifier.errors.any? { |error| error.include?(expected_error) }, verifier.errors.join("\n")
  end

  def mutate_package(path)
    package = load_yaml(path)
    yield package
    write_yaml(path, package)
  end

  def lineage_verifier
    PMind::PromptPackageLineageVerifier.new(ROOT)
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
