# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/preview_prompt_package_compilation_confirmation"

class PreviewPromptPackageCompilationConfirmationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")

  def test_confirmed_ready_choice_is_valid_but_does_not_create_or_handoff
    preview = previewer
    copy = preview.preview(source_session, draft_package, compilation_proposal, confirmation_receipt, input_digests)

    assert copy, preview.errors.join("\n")
    assert_includes copy, "已收到 Package 创建确认，尚未创建最终 Package"
    assert_includes copy, "不允许自动 Handoff"
    assert_includes copy, "仍待单独审批"
    assert_includes copy, "不授权 Handoff"
  end

  def test_confirmed_not_ready_choice_is_valid_without_creation_authorization
    package = draft_package
    proposal = compilation_proposal
    confirmation = confirmation_receipt
    package.fetch("handoff")["ready"] = false
    proposal["draft_package_handoff_ready"] = false
    confirmation["draft_package_handoff_ready"] = false
    confirmation["package_creation_authorized"] = false

    copy = assert_preview(confirmation, source_session, package, proposal)

    assert_includes copy, "候选 Package 尚未就绪"
    assert_includes copy, "不会授权创建可交接 Package"
    assert_includes copy, "新的 Compilation Proposal 和 Confirmation Receipt"
  end

  def test_modify_requested_is_a_valid_non_creation_choice
    document = confirmation_for("modify_requested", false, "范围需要移除批量导出。")
    copy = assert_preview(document)

    assert_includes copy, "当前编译提案不会继续"
    assert_includes copy, "重新校验并形成新的 Compilation Proposal"
  end

  def test_rejected_is_a_valid_non_creation_choice
    document = confirmation_for("rejected", false, "拒绝本次编译。")
    copy = assert_preview(document)

    assert_includes copy, "已拒绝本次 Package 编译"
    assert_includes copy, "不会发生 Handoff"
  end

  def test_modify_and_reject_remain_valid_for_not_ready_draft
    {
      "modify_requested" => "当前编译提案不会继续",
      "rejected" => "已拒绝本次 Package 编译"
    }.each do |decision, expected_copy|
      package = draft_package
      proposal = compilation_proposal
      confirmation = confirmation_for(decision, false, "合成未就绪选择")
      package.fetch("handoff")["ready"] = false
      proposal["draft_package_handoff_ready"] = false
      confirmation["draft_package_handoff_ready"] = false

      copy = assert_preview(confirmation, source_session, package, proposal)
      assert_includes copy, expected_copy
    end
  end

  def test_all_illegal_choice_authorization_combinations_are_rejected
    [
      ["confirmed", false],
      ["modify_requested", true],
      ["rejected", true]
    ].each do |decision, authorized|
      document = confirmation_for(decision, authorized, "合成确认选择")
      assert_invalid(document, "package_creation_authorized must be true only")
    end

    package = draft_package
    proposal = compilation_proposal
    confirmation = confirmation_for("confirmed", true, "确认当前未就绪理解")
    package.fetch("handoff")["ready"] = false
    proposal["draft_package_handoff_ready"] = false
    confirmation["draft_package_handoff_ready"] = false
    assert_invalid(confirmation, "package_creation_authorized must be true only", source_session, package, proposal)
  end

  def test_all_source_bindings_must_match
    mutations = {
      "session_id" => "session-20260821-999",
      "source_session_revision_number" => 2,
      "package_id" => "pkg-20260821-999",
      "compilation_proposal_id" => "compile-proposal-20260821-999",
      "draft_package_handoff_ready" => false
    }

    mutations.each do |field, value|
      document = confirmation_receipt
      document[field] = value
      assert_invalid(document, "#{field} does not match its confirmed source")
    end
  end

  def test_each_exact_source_file_digest_must_match
    %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
    ].each do |field|
      document = confirmation_receipt
      document[field] = "0" * 64
      assert_invalid(document, "#{field} does not match its confirmed source")
    end
  end

  def test_semantically_equivalent_byte_drift_invalidates_confirmation
    source_paths = [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE]
    expected_fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
    ]

    source_paths.each_with_index do |_source, changed_index|
      Dir.mktmpdir("pmind-compilation-confirmation-drift") do |directory|
        paths = [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE].map do |path|
          target = File.join(directory, File.basename(path))
          FileUtils.cp(path, target)
          target
        end
        File.open(paths.fetch(changed_index), "ab") { |file| file.write("\n") }

        preview = previewer
        refute preview.preview_files(*paths)
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
    document["captured_at"] = "2026-08-21T12:04:00+08:00"

    assert_invalid(document, "cannot predate its Proposal")
  end

  def test_confirmation_data_policy_cannot_downgrade_sources
    session = source_session
    proposal = compilation_proposal
    session.fetch("intake")["data_classification"] = "internal"
    proposal["data_classification"] = "internal"

    assert_invalid(confirmation_receipt, "data classification cannot downgrade", session, draft_package, proposal)
  end

  def test_confirmation_cannot_drop_personal_data_declaration
    session = source_session
    proposal = compilation_proposal
    confirmation = confirmation_receipt
    session.fetch("intake")["data_classification"] = "internal"
    session.fetch("intake")["contains_personal_data"] = true
    proposal["data_classification"] = "internal"
    proposal["contains_personal_data"] = true
    confirmation["data_classification"] = "internal"

    assert_invalid(confirmation, "cannot drop a source personal-data declaration", session, draft_package, proposal)
  end

  def test_handoff_risk_and_secret_authorization_declarations_are_rejected
    ["handoff_authorized", "high_risk_authorization_inferred", "contains_secrets"].each do |field|
      document = confirmation_receipt
      document[field] = true

      assert_invalid(document, "expected constant false")
    end
  end

  def test_success_copy_hides_paths_digests_ids_and_source_content
    preview = previewer
    copy = preview.preview_files(SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE)
    session = source_session
    package = draft_package
    proposal = compilation_proposal
    confirmation = confirmation_receipt

    [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE].each { |path| refute_includes copy, path }
    refute_includes copy, session.dig("intake", "raw_intent")
    refute_includes copy, session.dig("rounds", 0, "answers", 0, "user_answer")
    refute_includes copy, package.dig("knowledge", "evidence", 0, "source")
    refute_includes copy, confirmation["user_response"]
    refute_includes copy, confirmation["user_response_sha256"]
    refute_includes copy, confirmation["compilation_confirmation_id"]
    refute_includes copy, proposal["compilation_proposal_id"]
    refute_includes copy, confirmation["source_session_file_sha256"]
  end

  def test_dynamic_approval_copy_is_markdown_safe
    package = draft_package
    package.dig("approval_points", 0)["scope"] = "<script>_approval_"

    copy = assert_preview(confirmation_receipt, source_session, package, compilation_proposal)

    refute_includes copy, "<script>"
    assert_includes copy, "&lt;script&gt;\\_approval\\_"
  end

  def test_cli_reads_all_four_inputs_without_writing
    paths = [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE, CONFIRMATION_FIXTURE]
    before = paths.map { |path| File.binread(path) }
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_prompt_package_compilation_confirmation.rb"),
      *paths,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "尚未创建最终 Package"
    assert_equal "", stderr
    assert_equal before, paths.map { |path| File.binread(path) }
  end

  def test_cli_rejects_missing_input_without_echoing_confirmation
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_prompt_package_compilation_confirmation.rb"),
      SESSION_FIXTURE,
      PACKAGE_FIXTURE,
      PROPOSAL_FIXTURE,
      "missing-compilation-confirmation.yaml",
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "cannot load YAML"
    refute_includes stderr, confirmation_receipt["user_response"]
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_prompt_package_compilation_confirmation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def assert_preview(document, session = source_session, package = draft_package, proposal = compilation_proposal)
    preview = previewer
    copy = preview.preview(session, package, proposal, document, input_digests)
    assert copy, preview.errors.join("\n")
    copy
  end

  def assert_invalid(document, expected_error, session = source_session, package = draft_package, proposal = compilation_proposal)
    preview = previewer
    refute preview.preview(session, package, proposal, document, input_digests)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
    refute preview.errors.join("\n").include?(document["user_response"].to_s)
  end

  def previewer
    PMind::PromptPackageCompilationConfirmationPreview.new(ROOT)
  end

  def source_session
    load_yaml(SESSION_FIXTURE)
  end

  def draft_package
    load_yaml(PACKAGE_FIXTURE)
  end

  def compilation_proposal
    load_yaml(PROPOSAL_FIXTURE)
  end

  def confirmation_receipt
    load_yaml(CONFIRMATION_FIXTURE)
  end

  def confirmation_for(decision, authorized, response)
    document = confirmation_receipt
    document["confirmation_decision"] = decision
    document["package_creation_authorized"] = authorized
    document["user_response"] = response
    document["user_response_sha256"] = Digest::SHA256.hexdigest(response)
    document
  end

  def input_digests
    {
      "source_session_file_sha256" => Digest::SHA256.file(SESSION_FIXTURE).hexdigest,
      "draft_package_file_sha256" => Digest::SHA256.file(PACKAGE_FIXTURE).hexdigest,
      "compilation_proposal_file_sha256" => Digest::SHA256.file(PROPOSAL_FIXTURE).hexdigest,
      "compilation_confirmation_receipt_file_sha256" => Digest::SHA256.file(CONFIRMATION_FIXTURE).hexdigest
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
