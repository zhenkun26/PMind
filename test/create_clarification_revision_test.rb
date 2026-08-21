# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/create_clarification_revision"

class CreateClarificationRevisionTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-gap-scan.yaml")
  RECEIPT_FIXTURE = File.join(ROOT, "test/fixtures/clarification-answer-receipt-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/clarification-revision-proposal-valid.yaml")
  CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-confirmation-receipt-valid.yaml")

  def test_confirmed_receipt_creates_a_valid_new_revision_without_modifying_inputs
    before = input_paths.map { |path| File.binread(path) }

    Dir.mktmpdir("pmind-revision-create") do |directory|
      output = File.join(directory, "session-revision-001.yaml")
      creator = revision_creator
      copy = creator.create_files(*input_paths, output)

      assert copy, creator.errors.join("\n")
      assert_includes copy, "Session revision 已创建"
      assert_includes copy, "原 Session 未修改"
      assert File.file?(output)
      assert_equal 0o600, File.stat(output).mode & 0o777

      revision = load_yaml(output)
      validator = PMind::ClarificationSessionValidator.new(ROOT)
      assert validator.validate(revision, output), validator.errors.join("\n")
      assert_equal "ready_to_compile", revision["status"]
      assert_equal "只有具有 export_users 权限的角色。", revision.dig("rounds", 0, "answers", 0, "user_answer")
      assert_equal 1, revision.dig("revision", "revision_number")
      assert_equal "confirmed", revision.dig("revision", "confirmation_decision")
      assert_equal false, revision.dig("revision", "high_risk_authorization_inferred")
      assert_equal Digest::SHA256.file(SESSION_FIXTURE).hexdigest, revision.dig("revision", "source_session_file_sha256")
      assert_equal Digest::SHA256.file(RECEIPT_FIXTURE).hexdigest, revision.dig("revision", "answer_receipt_file_sha256")
      assert_equal Digest::SHA256.file(PROPOSAL_FIXTURE).hexdigest, revision.dig("revision", "proposal_file_sha256")
      assert_equal Digest::SHA256.file(CONFIRMATION_FIXTURE).hexdigest, revision.dig("revision", "confirmation_receipt_file_sha256")
      assert_equal before, input_paths.map { |path| File.binread(path) }
      refute load_yaml(SESSION_FIXTURE).key?("revision")
    end
  end

  def test_creation_is_deterministic_for_the_same_confirmed_inputs
    Dir.mktmpdir("pmind-revision-deterministic") do |directory|
      first = File.join(directory, "first.yaml")
      second = File.join(directory, "second.yaml")

      assert revision_creator.create_files(*input_paths, first)
      assert revision_creator.create_files(*input_paths, second)
      assert_equal File.binread(first), File.binread(second)
    end
  end

  def test_existing_output_is_never_overwritten
    Dir.mktmpdir("pmind-revision-existing") do |directory|
      output = File.join(directory, "existing.yaml")
      File.open(output, "wb") { |file| file.write("sentinel\n") }
      creator = revision_creator

      refute creator.create_files(*input_paths, output)
      assert_includes creator.errors.join("\n"), "refusing to overwrite"
      assert_equal "sentinel\n", File.binread(output)
    end
  end

  def test_modify_requested_never_creates_an_output
    assert_non_creation_choice("modify_requested", false, "请修改权限名称。")
  end

  def test_rejected_never_creates_an_output
    assert_non_creation_choice("rejected", false, "拒绝应用。")
  end

  def test_stale_source_file_digest_causes_zero_writes
    Dir.mktmpdir("pmind-revision-stale") do |directory|
      changed_session = File.join(directory, "changed-session.yaml")
      File.open(changed_session, "wb") do |file|
        file.write(File.binread(SESSION_FIXTURE))
        file.write("\n")
      end
      output = File.join(directory, "must-not-exist.yaml")
      creator = revision_creator

      refute creator.create_files(changed_session, RECEIPT_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE, output)
      assert_includes creator.errors.join("\n"), "source_session_file_sha256"
      refute File.exist?(output)
    end
  end

  def test_missing_output_directory_causes_zero_persisted_files
    Dir.mktmpdir("pmind-revision-missing-dir") do |directory|
      output = File.join(directory, "missing", "revision.yaml")
      creator = revision_creator

      refute creator.create_files(*input_paths, output)
      assert_includes creator.errors.join("\n"), "cannot create revision"
      refute File.exist?(output)
    end
  end

  def test_success_copy_does_not_leak_confirmation_or_internal_lineage
    Dir.mktmpdir("pmind-revision-copy") do |directory|
      output = File.join(directory, "revision.yaml")
      copy = revision_creator.create_files(*input_paths, output)
      confirmation = load_yaml(CONFIRMATION_FIXTURE)

      refute_includes copy, confirmation["user_response"]
      refute_includes copy, confirmation["user_response_sha256"]
      refute_includes copy, confirmation["confirmation_id"]
      refute_includes copy, confirmation["proposal_id"]
      refute_includes copy, "product-owner-test"
      refute_includes copy, "constraints.product"
    end
  end

  def test_cli_creates_and_validates_a_revision
    Dir.mktmpdir("pmind-revision-cli") do |directory|
      output = File.join(directory, "revision.yaml")
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/create_clarification_revision.rb"),
        *input_paths,
        output,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "Session revision 已创建"
      assert_equal "", stderr
      assert File.file?(output)

      validation_stdout, validation_stderr, validation_status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/validate_clarification_session.rb"),
        output,
        chdir: ROOT
      )
      assert validation_status.success?, validation_stderr
      assert_includes validation_stdout, "PMIND_CLARIFICATION_SESSION_VALIDATION_PASS"
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/create_clarification_revision.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def assert_non_creation_choice(decision, authorized, response)
    Dir.mktmpdir("pmind-revision-choice") do |directory|
      confirmation_path = File.join(directory, "confirmation.yaml")
      output = File.join(directory, "must-not-exist.yaml")
      document = load_yaml(CONFIRMATION_FIXTURE)
      document["confirmation_decision"] = decision
      document["revision_creation_authorized"] = authorized
      document["user_response"] = response
      document["user_response_sha256"] = Digest::SHA256.hexdigest(response)
      File.open(confirmation_path, "wb", 0o600) { |file| file.write(YAML.dump(document)) }

      creator = revision_creator
      refute creator.create_files(SESSION_FIXTURE, RECEIPT_FIXTURE, PROPOSAL_FIXTURE, confirmation_path, output)
      assert_includes creator.errors.join("\n"), "does not authorize revision creation"
      refute File.exist?(output)
    end
  end

  def revision_creator
    PMind::ClarificationRevisionCreator.new(ROOT)
  end

  def input_paths
    [SESSION_FIXTURE, RECEIPT_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE]
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
