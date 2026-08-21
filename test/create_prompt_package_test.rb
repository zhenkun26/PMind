# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/create_prompt_package"

class CreatePromptPackageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")

  def test_confirmed_ready_receipt_creates_a_valid_final_package_without_modifying_inputs
    before = input_paths.map { |path| File.binread(path) }

    Dir.mktmpdir("pmind-package-create") do |directory|
      output = File.join(directory, "final-package.yaml")
      creator = package_creator
      copy = creator.create_files(*input_paths, output)

      assert copy, creator.errors.join("\n")
      assert_includes copy, "最终 Prompt Package 已创建"
      assert_includes copy, "候选源文件保持不变"
      assert_includes copy, "尚未 Handoff"
      assert File.file?(output)
      assert_equal 0o600, File.stat(output).mode & 0o777

      final_package = load_yaml(output)
      validator = PMind::PromptPackageValidator.new(ROOT)
      assert validator.validate(final_package, output), validator.errors.join("\n")
      lineage_validator = PMind::ClarificationSessionValidator.new(ROOT)
      assert lineage_validator.validate_pair(load_yaml(SESSION_FIXTURE), final_package), lineage_validator.errors.join("\n")
      assert_equal true, final_package.dig("handoff", "ready")
      assert_equal false, final_package.dig("compilation", "handoff_authorization_inferred")
      assert_equal false, final_package.dig("compilation", "high_risk_authorization_inferred")
      assert_equal Digest::SHA256.file(SESSION_FIXTURE).hexdigest, final_package.dig("compilation", "source_session_file_sha256")
      assert_equal Digest::SHA256.file(PACKAGE_FIXTURE).hexdigest, final_package.dig("compilation", "draft_package_file_sha256")
      assert_equal Digest::SHA256.file(PROPOSAL_FIXTURE).hexdigest, final_package.dig("compilation", "compilation_proposal_file_sha256")
      assert_equal Digest::SHA256.file(CONFIRMATION_FIXTURE).hexdigest,
                   final_package.dig("compilation", "compilation_confirmation_receipt_file_sha256")
      business_content = deep_copy(final_package)
      business_content.delete("compilation")
      assert_equal load_yaml(PACKAGE_FIXTURE), business_content
      assert_equal before, input_paths.map { |path| File.binread(path) }
    end
  end

  def test_creation_is_deterministic_for_the_same_confirmed_inputs
    Dir.mktmpdir("pmind-package-deterministic") do |directory|
      first = File.join(directory, "first.yaml")
      second = File.join(directory, "second.yaml")

      assert package_creator.create_files(*input_paths, first)
      assert package_creator.create_files(*input_paths, second)
      assert_equal File.binread(first), File.binread(second)
    end
  end

  def test_existing_output_is_never_overwritten
    Dir.mktmpdir("pmind-package-existing") do |directory|
      output = File.join(directory, "existing.yaml")
      File.open(output, "wb") { |file| file.write("sentinel\n") }
      creator = package_creator

      refute creator.create_files(*input_paths, output)
      assert_includes creator.errors.join("\n"), "refusing to overwrite"
      assert_equal "sentinel\n", File.binread(output)
    end
  end

  def test_modify_requested_never_creates_an_output
    assert_non_creation_choice("modify_requested", "请修改候选内容。")
  end

  def test_rejected_never_creates_an_output
    assert_non_creation_choice("rejected", "拒绝本次编译。")
  end

  def test_confirmed_not_ready_draft_never_creates_an_output
    Dir.mktmpdir("pmind-package-not-ready") do |directory|
      paths = write_bound_chain(directory) do |package, proposal, confirmation|
        package.fetch("handoff")["ready"] = false
        proposal["draft_package_handoff_ready"] = false
        confirmation["draft_package_handoff_ready"] = false
        confirmation["package_creation_authorized"] = false
      end
      output = File.join(directory, "must-not-exist.yaml")
      creator = package_creator

      refute creator.create_files(*paths, output)
      assert_includes creator.errors.join("\n"), "does not authorize final Package creation"
      refute File.exist?(output)
    end
  end

  def test_stale_source_file_digest_causes_zero_writes
    Dir.mktmpdir("pmind-package-stale") do |directory|
      changed_package = File.join(directory, "changed-package.yaml")
      File.open(changed_package, "wb", 0o600) do |file|
        file.write(File.binread(PACKAGE_FIXTURE))
        file.write("\n")
      end
      output = File.join(directory, "must-not-exist.yaml")
      creator = package_creator

      refute creator.create_files(SESSION_FIXTURE, changed_package, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE, output)
      assert_includes creator.errors.join("\n"), "draft_package_file_sha256"
      refute File.exist?(output)
    end
  end

  def test_missing_output_directory_causes_zero_persisted_files
    Dir.mktmpdir("pmind-package-missing-dir") do |directory|
      output = File.join(directory, "missing", "final-package.yaml")
      creator = package_creator

      refute creator.create_files(*input_paths, output)
      assert_includes creator.errors.join("\n"), "cannot create final Package"
      refute File.exist?(output)
    end
  end

  def test_success_copy_is_markdown_safe_and_does_not_leak_internal_lineage
    Dir.mktmpdir("pmind-package-copy") do |directory|
      paths = write_bound_chain(directory) do |package, _proposal, _confirmation|
        package.fetch("approval_points").first["scope"] = "仅限 <script>x</script> [链接](https://invalid.example)"
      end
      output = File.join(directory, "final-package.yaml")
      copy = package_creator.create_files(*paths, output)
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

  def test_cli_creates_and_validates_a_final_package
    Dir.mktmpdir("pmind-package-cli") do |directory|
      output = File.join(directory, "final-package.yaml")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/create_prompt_package.rb"),
        *input_paths,
        output,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "最终 Prompt Package 已创建"
      assert_equal "", stderr
      assert File.file?(output)

      validation_stdout, validation_stderr, validation_status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/validate_prompt_package.rb"),
        output,
        chdir: ROOT
      )
      assert validation_status.success?, validation_stderr
      assert_includes validation_stdout, "PMIND_PROMPT_PACKAGE_VALIDATION_PASS"
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/create_prompt_package.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def assert_non_creation_choice(decision, response)
    Dir.mktmpdir("pmind-package-choice") do |directory|
      paths = write_bound_chain(directory) do |_package, _proposal, confirmation|
        confirmation["confirmation_decision"] = decision
        confirmation["package_creation_authorized"] = false
        confirmation["user_response"] = response
        confirmation["user_response_sha256"] = Digest::SHA256.hexdigest(response)
      end
      output = File.join(directory, "must-not-exist.yaml")
      creator = package_creator

      refute creator.create_files(*paths, output)
      assert_includes creator.errors.join("\n"), "does not authorize final Package creation"
      refute File.exist?(output)
    end
  end

  def write_bound_chain(directory)
    package = load_yaml(PACKAGE_FIXTURE)
    proposal = load_yaml(PROPOSAL_FIXTURE)
    confirmation = load_yaml(CONFIRMATION_FIXTURE)
    yield package, proposal, confirmation

    package_path = File.join(directory, "draft-package.yaml")
    write_yaml(package_path, package)
    proposal["draft_package_file_sha256"] = Digest::SHA256.file(package_path).hexdigest
    proposal_path = File.join(directory, "proposal.yaml")
    write_yaml(proposal_path, proposal)
    confirmation["draft_package_file_sha256"] = Digest::SHA256.file(package_path).hexdigest
    confirmation["compilation_proposal_file_sha256"] = Digest::SHA256.file(proposal_path).hexdigest
    confirmation_path = File.join(directory, "confirmation.yaml")
    write_yaml(confirmation_path, confirmation)

    [SESSION_FIXTURE, package_path, proposal_path, confirmation_path]
  end

  def write_yaml(path, document)
    File.open(path, "wb", 0o600) { |file| file.write(YAML.dump(document)) }
  end

  def package_creator
    PMind::PromptPackageCreator.new(ROOT)
  end

  def input_paths
    [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE]
  end

  def load_yaml(path)
    YAML.safe_load(
      File.read(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
