# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/preview_handoff_confirmation"

class PreviewHandoffConfirmationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  COMPILATION_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")
  COMPILATION_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-confirmation-receipt-valid.yaml")
  HANDOFF_PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/handoff-proposal-valid.yaml")
  HANDOFF_CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/handoff-confirmation-receipt-valid.yaml")

  def test_confirmed_receipt_authorizes_only_future_controlled_handoff
    with_seven_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已收到 Handoff 确认，尚未交接"
      assert_includes copy, "编码型 Downstream Executor"
      assert_includes copy, "仅限当前已验证的精确 Prompt Package"
      assert_includes copy, "允许后续受控步骤继续"
      assert_includes copy, "仍禁止的动作"
      assert_includes copy, "推送远端"
      assert_includes copy, "任何外部效果"
      assert_includes copy, "仍待单独审批"
      assert_includes copy, "本地 Handoff Envelope 创建步骤"
      assert_includes copy, "独立重放 lineage"
      assert_includes copy, "必须停止并获得单独授权"
    end
  end

  def test_modify_requested_is_legal_only_without_handoff_authorization
    with_seven_files do |paths|
      set_choice(paths, "modify_requested", false, "需要修改交接范围后再确认。")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已收到 Handoff 修改请求，当前授权未成立"
      assert_includes copy, "尚未发生 Handoff"
      assert_includes copy, "外部效果与高风险动作仍未获授权"
    end
  end

  def test_rejected_is_legal_only_without_handoff_authorization
    with_seven_files do |paths|
      set_choice(paths, "rejected", false, "拒绝本次交接。")
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "已拒绝本次 Handoff，最终 Package 保持不变"
      assert_includes copy, "不会交给 Downstream Executor"
      assert_includes copy, "不会产生外部效果"
    end
  end

  def test_each_illegal_choice_authorization_transition_is_rejected
    [
      ["confirmed", false],
      ["modify_requested", true],
      ["rejected", true]
    ].each do |decision, authorized|
      with_seven_files do |paths|
        set_choice(paths, decision, authorized, "状态矩阵测试。")

        assert_invalid(paths, "handoff_authorized must be true only for confirmed")
      end
    end
  end

  def test_receipt_never_authorizes_external_effects_or_infers_high_risk_authority
    %w[external_effects_authorized high_risk_authorization_inferred].each do |field|
      with_seven_files do |paths|
        receipt = load_yaml(paths.fetch(6))
        receipt[field] = true
        write_yaml(paths.fetch(6), receipt)

        assert_invalid(paths, "expected constant false")
      end
    end
  end

  def test_complete_six_file_proposal_chain_is_replayed
    expected_fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
    ]
    expected_fields.each_with_index do |field, index|
      with_seven_files do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("\n") }

        assert_invalid(paths, field)
      end
    end
  end

  def test_final_package_drift_is_rejected_before_confirmation
    with_seven_files do |paths|
      File.open(paths.fetch(4), "ab") { |file| file.write("# final package changed\n") }

      assert_invalid(paths, "final_package_file_sha256 does not match the exact final Package")
    end
  end

  def test_handoff_proposal_byte_drift_is_rejected_by_receipt_binding
    with_seven_files do |paths|
      File.open(paths.fetch(5), "ab") { |file| file.write("# proposal changed\n") }

      assert_invalid(paths, "handoff_proposal_file_sha256 does not match its confirmed source")
    end
  end

  def test_receipt_binds_exact_final_package_bytes_used_by_proposal_preview
    with_seven_files do |paths|
      File.open(paths.fetch(4), "ab") { |file| file.write("# equivalent final YAML\n") }
      proposal = load_yaml(paths.fetch(5))
      proposal["final_package_file_sha256"] = Digest::SHA256.file(paths.fetch(4)).hexdigest
      write_yaml(paths.fetch(5), proposal)
      receipt = load_yaml(paths.fetch(6))
      receipt["handoff_proposal_file_sha256"] = Digest::SHA256.file(paths.fetch(5)).hexdigest
      write_yaml(paths.fetch(6), receipt)

      assert_invalid(paths, "final_package_file_sha256 does not match its confirmed source")
    end
  end

  def test_preview_exposes_digest_of_exact_confirmation_bytes_it_loaded
    with_seven_files do |paths|
      File.open(paths.fetch(6), "ab") { |file| file.write("# equivalent receipt YAML\n") }
      preview = confirmation_preview

      assert preview.preview_files(*paths), preview.errors.join("\n")
      assert_equal Digest::SHA256.file(paths.fetch(6)).hexdigest, preview.confirmation_file_sha256
    end
  end

  def test_each_declared_source_digest_must_match
    %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
    ].each do |field|
      with_seven_files do |paths|
        receipt = load_yaml(paths.fetch(6))
        receipt[field] = "0" * 64
        write_yaml(paths.fetch(6), receipt)

        assert_invalid(paths, "#{field} does not match its confirmed source")
      end
    end
  end

  def test_identity_recipient_ready_and_pending_state_must_match
    replacements = {
      "package_id" => "pkg-20260821-999",
      "handoff_proposal_id" => "handoff-proposal-20260821-999",
      "package_handoff_ready" => false,
      "recipient" => "research_agent",
      "handoff_proposal_status" => "confirmed"
    }
    replacements.each do |field, replacement|
      with_seven_files do |paths|
        receipt = load_yaml(paths.fetch(6))
        receipt[field] = replacement
        write_yaml(paths.fetch(6), receipt)

        preview = confirmation_preview
        refute preview.preview_files(*paths)
        assert preview.errors.any? { |error| error.include?(field) || error.include?("expected constant") }, preview.errors.join("\n")
      end
    end
  end

  def test_user_response_digest_must_match_without_echoing_response
    with_seven_files do |paths|
      receipt = load_yaml(paths.fetch(6))
      receipt["user_response_sha256"] = "0" * 64
      write_yaml(paths.fetch(6), receipt)

      assert_invalid(paths, "user response digest does not match")
    end
  end

  def test_confirmation_cannot_predate_handoff_proposal
    with_seven_files do |paths|
      receipt = load_yaml(paths.fetch(6))
      receipt["captured_at"] = "2026-08-21T12:09:59+08:00"
      write_yaml(paths.fetch(6), receipt)

      assert_invalid(paths, "cannot predate its Proposal")
    end
  end

  def test_confirmation_cannot_downgrade_proposal_or_package_input_classification
    with_seven_files do |paths|
      rebuild_seven_files(paths) do |_session, package, _compilation_proposal, _compilation_confirmation, handoff_proposal, handoff_confirmation|
        package.dig("execution_contract", "inputs", 0)["data_classification"] = "restricted"
        handoff_proposal["data_classification"] = "restricted"
        handoff_confirmation["data_classification"] = "public"
      end

      assert_invalid(paths, "data classification cannot downgrade its sources")
    end
  end

  def test_personal_user_response_cannot_use_public_classification
    with_seven_files do |paths|
      receipt = load_yaml(paths.fetch(6))
      receipt["contains_personal_data"] = true
      write_yaml(paths.fetch(6), receipt)

      assert_invalid(paths, "personal data cannot use public classification")
    end
  end

  def test_malformed_receipt_is_rejected_without_echoing_source_content
    with_seven_files do |paths|
      File.open(paths.fetch(6), "wb") { |file| file.write("confirmation_decision: [unterminated\n") }
      preview = confirmation_preview

      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("cannot load YAML") }, preview.errors.join("\n")
      refute_includes preview.errors.join("\n"), load_yaml(paths.fetch(0)).dig("rounds", 0, "answers", 0, "user_answer")
    end
  end

  def test_confirmed_copy_is_markdown_safe
    with_seven_files do |paths|
      rebuild_seven_files(paths) do |_session, package, _compilation_proposal, _compilation_confirmation, _handoff_proposal, _handoff_confirmation|
        package.dig("handoff", "stop_conditions")[0] = "<script>_stop_"
        package.fetch("approval_points").first["scope"] = "[approval](https://invalid.example)"
      end
      preview = confirmation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_stop\\_"
      assert_includes copy, "\\[approval\\](https://invalid.example)"
    end
  end

  def test_success_copy_hides_paths_digests_ids_and_source_content
    with_seven_files do |paths|
      preview = confirmation_preview
      copy = preview.preview_files(*paths)
      session = load_yaml(paths.fetch(0))
      package = load_yaml(paths.fetch(4))
      compilation_confirmation = load_yaml(paths.fetch(3))
      handoff_proposal = load_yaml(paths.fetch(5))
      receipt = load_yaml(paths.fetch(6))

      paths.each { |path| refute_includes copy, path }
      refute_includes copy, session.dig("intake", "raw_intent")
      refute_includes copy, session.dig("rounds", 0, "answers", 0, "user_answer")
      refute_includes copy, package.dig("knowledge", "evidence", 0, "source")
      refute_includes copy, package.dig("knowledge", "decisions", 0, "decision_maker_ref")
      refute_includes copy, package.dig("review_findings", 0, "owner")
      refute_includes copy, compilation_confirmation["user_response"]
      refute_includes copy, handoff_proposal["handoff_proposal_id"]
      refute_includes copy, receipt["handoff_confirmation_id"]
      refute_includes copy, receipt["user_response"]
      refute_includes copy, receipt["user_response_sha256"]
      refute_includes copy, receipt["final_package_file_sha256"]
      refute_includes copy, package["package_id"]
      refute_includes copy, "constraints.product"
    end
  end

  def test_cli_reads_all_seven_inputs_without_writing
    with_seven_files do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_confirmation.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "已收到 Handoff 确认，尚未交接"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_missing_receipt_without_echoing_confirmation
    with_seven_files do |paths|
      receipt = load_yaml(paths.fetch(6))
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_handoff_confirmation.rb"),
        *paths.first(6),
        "missing-handoff-confirmation.yaml",
        chdir: ROOT
      )

      refute status.success?
      assert_includes stderr, "cannot load YAML"
      refute_includes stderr, receipt["user_response"]
    end
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_handoff_confirmation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_seven_files
    Dir.mktmpdir("pmind-handoff-confirmation") do |directory|
      paths = write_seven_files(directory)
      yield paths
    end
  end

  def write_seven_files(directory)
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
    sources.zip([paths.fetch(0), paths.fetch(1), paths.fetch(2), paths.fetch(3), paths.fetch(5), paths.fetch(6)]).each do |source, target|
      FileUtils.cp(source, target)
    end
    create_final_package(paths)
    refresh_handoff_proposal(paths)
    refresh_handoff_confirmation(paths)
    paths
  end

  def rebuild_seven_files(paths)
    session = load_yaml(paths.fetch(0))
    package = load_yaml(paths.fetch(1))
    compilation_proposal = load_yaml(paths.fetch(2))
    compilation_confirmation = load_yaml(paths.fetch(3))
    handoff_proposal = load_yaml(paths.fetch(5))
    handoff_confirmation = load_yaml(paths.fetch(6))
    yield session, package, compilation_proposal, compilation_confirmation, handoff_proposal, handoff_confirmation

    write_yaml(paths.fetch(0), session)
    write_yaml(paths.fetch(1), package)
    refresh_compilation_chain(paths, compilation_proposal, compilation_confirmation)
    File.delete(paths.fetch(4))
    create_final_package(paths)
    write_yaml(paths.fetch(5), handoff_proposal)
    refresh_handoff_proposal(paths)
    write_yaml(paths.fetch(6), handoff_confirmation)
    refresh_handoff_confirmation(paths)
  end

  def refresh_compilation_chain(paths, compilation_proposal = load_yaml(paths.fetch(2)), confirmation = load_yaml(paths.fetch(3)))
    compilation_proposal["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    compilation_proposal["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    write_yaml(paths.fetch(2), compilation_proposal)

    confirmation["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    confirmation["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    confirmation["compilation_proposal_file_sha256"] = Digest::SHA256.file(paths.fetch(2)).hexdigest
    write_yaml(paths.fetch(3), confirmation)
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

  def set_choice(paths, decision, authorized, response)
    receipt = load_yaml(paths.fetch(6))
    receipt["confirmation_decision"] = decision
    receipt["handoff_authorized"] = authorized
    receipt["user_response"] = response
    receipt["user_response_sha256"] = Digest::SHA256.hexdigest(response)
    write_yaml(paths.fetch(6), receipt)
  end

  def assert_invalid(paths, expected_error)
    receipt = load_yaml(paths.fetch(6))
    preview = confirmation_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
    refute_includes preview.errors.join("\n"), receipt["user_response"].to_s
  end

  def confirmation_preview
    PMind::HandoffConfirmationPreview.new(ROOT)
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
