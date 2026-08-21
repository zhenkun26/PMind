# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/preview_clarification_confirmation"

class PreviewClarificationConfirmationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-gap-scan.yaml")
  RECEIPT_FIXTURE = File.join(ROOT, "test/fixtures/clarification-answer-receipt-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/clarification-revision-proposal-valid.yaml")
  CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-confirmation-receipt-valid.yaml")

  def test_confirmed_choice_is_valid_but_does_not_create_revision
    preview = previewer
    copy = preview.preview(source_session, answer_receipt, revision_proposal, confirmation_receipt, input_digests)

    assert copy, preview.errors.join("\n")
    assert_includes copy, "已收到修订确认，尚未创建 revision"
    assert_includes copy, "此确认不授权任何高风险动作"
    assert_equal "ready_to_compile", preview.candidate_session["status"]
  end

  def test_modify_requested_is_a_valid_non_creation_choice
    document = confirmation_for("modify_requested", false, "权限名需要改成 export_admins。")
    copy = assert_preview(document)

    assert_includes copy, "当前 Proposal 不会应用"
    assert_includes copy, "形成新的 Proposal"
  end

  def test_rejected_is_a_valid_non_creation_choice
    document = confirmation_for("rejected", false, "拒绝，不要应用。")
    copy = assert_preview(document)

    assert_includes copy, "原 Session 保持不变"
    assert_includes copy, "不会创建 revision"
  end

  def test_all_illegal_choice_authorization_combinations_are_rejected
    [
      ["confirmed", false],
      ["modify_requested", true],
      ["rejected", true]
    ].each do |decision, authorized|
      document = confirmation_for(decision, authorized, "合成确认选择")
      assert_invalid(document, "revision_creation_authorized must be true only for confirmed")
    end
  end

  def test_all_source_bindings_must_match
    mutations = {
      "session_id" => "session-20260821-999",
      "source_session_status" => "clarifying",
      "answer_receipt_id" => "receipt-20260821-999",
      "proposal_id" => "proposal-20260821-999",
      "round_number" => 2,
      "target_revision_number" => 2,
      "target_session_status" => "blocked"
    }

    mutations.each do |field, value|
      document = confirmation_receipt
      document[field] = value
      assert_invalid(document, "#{field} does not match its confirmed source")
    end
  end

  def test_each_exact_input_file_digest_must_match
    fields = %w[
      source_session_file_sha256
      answer_receipt_file_sha256
      proposal_file_sha256
    ]
    fields.each do |field|
      document = confirmation_receipt
      document[field] = "0" * 64
      assert_invalid(document, "#{field} does not match its confirmed source")
    end
  end

  def test_semantically_equivalent_byte_drift_invalidates_confirmation
    source_paths = [SESSION_FIXTURE, RECEIPT_FIXTURE, PROPOSAL_FIXTURE]
    expected_fields = %w[source_session_file_sha256 answer_receipt_file_sha256 proposal_file_sha256]

    source_paths.each_with_index do |_source, changed_index|
      Dir.mktmpdir("pmind-confirmation-drift") do |directory|
        copied = source_paths.map do |path|
          target = File.join(directory, File.basename(path))
          FileUtils.cp(path, target)
          target
        end
        File.open(copied.fetch(changed_index), "ab") { |file| file.write("\n") }

        preview = previewer
        result = preview.preview_files(*copied, CONFIRMATION_FIXTURE)
        refute result
        assert preview.errors.any? { |error| error.include?(expected_fields.fetch(changed_index)) }, preview.errors.join("\n")
      end
    end
  end

  def test_user_response_digest_must_match_exact_text
    document = confirmation_receipt
    document["user_response"] << "篡改"

    assert_invalid(document, "user response digest does not match")
  end

  def test_confirmation_cannot_predate_proposal
    document = confirmation_receipt
    document["captured_at"] = "2026-08-21T11:05:00+08:00"

    assert_invalid(document, "cannot predate its Proposal")
  end

  def test_confirmation_data_classification_cannot_downgrade_sources
    session = source_session
    receipt = answer_receipt
    session["intake"]["data_classification"] = "confidential"
    receipt["data_classification"] = "confidential"

    assert_invalid(confirmation_receipt, "cannot downgrade its sources", session, receipt)
  end

  def test_personal_confirmation_data_cannot_be_public
    document = confirmation_receipt
    document["contains_personal_data"] = true

    assert_invalid(document, "personal data cannot use public classification")
  end

  def test_secret_declaration_is_rejected_by_schema
    document = confirmation_receipt
    document["contains_secrets"] = true

    assert_invalid(document, "expected constant false")
  end

  def test_confirmation_copy_does_not_leak_raw_or_internal_fields
    document = confirmation_receipt
    copy = assert_preview(document)

    refute_includes copy, document["user_response"]
    refute_includes copy, document["user_response_sha256"]
    refute_includes copy, document["confirmation_id"]
    refute_includes copy, document["proposal_id"]
    refute_includes copy, document["answer_receipt_id"]
    refute_includes copy, document["session_id"]
    refute_includes copy, "product-owner-test"
    refute_includes copy, "constraints.product"
    refute_includes copy, "source_refs"
  end

  def test_dynamic_risk_copy_is_markdown_safe
    session = source_session
    proposal = revision_proposal
    dangerous = "<script>_risk_"
    session.dig("compile_gate", "high_risk_actions", 0)["description"] = dangerous
    proposal.dig("patch", "compile_gate_after", "high_risk_actions", 0)["description"] = dangerous

    copy = assert_preview(confirmation_receipt, session, answer_receipt, proposal)

    refute_includes copy, "<script>"
    assert_includes copy, "&lt;script&gt;\\_risk\\_"
  end

  def test_cli_is_read_only_for_all_four_inputs
    paths = [SESSION_FIXTURE, RECEIPT_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE]
    before = paths.map { |path| File.binread(path) }
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_confirmation.rb"),
      *paths,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "尚未创建 revision"
    assert_equal "", stderr
    assert_equal before, paths.map { |path| File.binread(path) }
  end

  def test_cli_rejects_missing_input_without_echoing_confirmation
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_confirmation.rb"),
      SESSION_FIXTURE,
      RECEIPT_FIXTURE,
      PROPOSAL_FIXTURE,
      "missing-confirmation.yaml",
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "cannot load YAML"
    refute_includes stderr, confirmation_receipt["user_response"]
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_clarification_confirmation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def assert_preview(document, session = source_session, receipt = answer_receipt, proposal = revision_proposal)
    preview = previewer
    copy = preview.preview(session, receipt, proposal, document, input_digests)
    assert copy, preview.errors.join("\n")
    copy
  end

  def assert_invalid(document, expected_error, session = source_session, receipt = answer_receipt, proposal = revision_proposal)
    preview = previewer
    refute preview.preview(session, receipt, proposal, document, input_digests)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
    refute preview.errors.join("\n").include?(document["user_response"].to_s)
  end

  def previewer
    PMind::ClarificationConfirmationPreview.new(ROOT)
  end

  def source_session
    load_yaml(SESSION_FIXTURE)
  end

  def answer_receipt
    load_yaml(RECEIPT_FIXTURE)
  end

  def revision_proposal
    load_yaml(PROPOSAL_FIXTURE)
  end

  def confirmation_receipt
    load_yaml(CONFIRMATION_FIXTURE)
  end

  def confirmation_for(decision, authorized, response)
    document = confirmation_receipt
    document["confirmation_decision"] = decision
    document["revision_creation_authorized"] = authorized
    document["user_response"] = response
    document["user_response_sha256"] = Digest::SHA256.hexdigest(response)
    document
  end

  def input_digests
    {
      "source_session_file_sha256" => Digest::SHA256.file(SESSION_FIXTURE).hexdigest,
      "answer_receipt_file_sha256" => Digest::SHA256.file(RECEIPT_FIXTURE).hexdigest,
      "proposal_file_sha256" => Digest::SHA256.file(PROPOSAL_FIXTURE).hexdigest,
      "confirmation_receipt_file_sha256" => Digest::SHA256.file(CONFIRMATION_FIXTURE).hexdigest
    }
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
