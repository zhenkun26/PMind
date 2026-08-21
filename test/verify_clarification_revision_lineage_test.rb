# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/verify_clarification_revision_lineage"

class VerifyClarificationRevisionLineageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-gap-scan.yaml")
  RECEIPT_FIXTURE = File.join(ROOT, "test/fixtures/clarification-answer-receipt-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/clarification-revision-proposal-valid.yaml")
  CONFIRMATION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-confirmation-receipt-valid.yaml")

  def test_persisted_revision_can_be_deterministically_replayed
    with_generated_revision do |paths|
      verifier = lineage_verifier
      copy = verifier.verify_files(*paths)

      assert copy, verifier.errors.join("\n")
      assert_includes copy, "Session revision 来源链已验证"
      assert_includes copy, "Session 内容：与确定性重建一致"
      assert_includes copy, "可以进入 Prompt Package 编译准备"
    end
  end

  def test_semantically_equivalent_yaml_formatting_is_accepted
    with_generated_revision do |paths|
      revision_path = paths.last
      original = File.binread(revision_path)
      File.open(revision_path, "wb") do |file|
        file.write("# equivalent YAML formatting\n")
        file.write(original)
      end

      verifier = lineage_verifier
      assert verifier.verify_files(*paths), verifier.errors.join("\n")
    end
  end

  def test_all_three_persisted_candidate_states_are_verifiable
    %w[clarifying ready_to_compile blocked].each do |target_status|
      Dir.mktmpdir("pmind-lineage-state") do |directory|
        paths = write_chain(directory, target_status)
        verifier = lineage_verifier
        copy = verifier.verify_files(*paths)

        assert copy, "#{target_status}: #{verifier.errors.join("\n")}"
        assert_equal target_status, verifier.revision["status"]
      end
    end
  end

  def test_each_source_file_byte_drift_is_rejected
    expected_fields = %w[
      source_session_file_sha256
      answer_receipt_file_sha256
      proposal_file_sha256
      confirmation_receipt_file_sha256
    ]
    expected_fields.each_with_index do |field, index|
      with_generated_revision do |paths|
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
      answer_receipt_file_sha256
      proposal_file_sha256
      confirmation_receipt_file_sha256
    ]
    fields.each do |field|
      with_generated_revision do |paths|
        mutate_revision(paths.last) { |revision| revision.fetch("revision")[field] = "0" * 64 }
        verifier = lineage_verifier

        refute verifier.verify_files(*paths)
        assert verifier.errors.any? { |error| error.include?("revision lineage #{field}") }, verifier.errors.join("\n")
      end
    end
  end

  def test_normalized_content_tampering_is_rejected
    with_generated_revision do |paths|
      mutate_revision(paths.last) do |revision|
        revision.dig("rounds", 0, "answers", 0)["normalized_conclusion"] = "未经确认的改写结论。"
      end

      assert_invalid(paths, "persisted Session content does not match deterministic reconstruction")
    end
  end

  def test_raw_answer_tampering_is_rejected
    with_generated_revision do |paths|
      mutate_revision(paths.last) do |revision|
        revision.dig("rounds", 0, "answers", 0)["user_answer"] = "伪造后的回答"
      end

      assert_invalid(paths, "persisted Session content does not match deterministic reconstruction")
    end
  end

  def test_high_risk_boundary_tampering_is_rejected
    with_generated_revision do |paths|
      mutate_revision(paths.last) do |revision|
        revision.dig("compile_gate", "high_risk_actions", 0)["description"] = "被弱化的边界"
      end

      assert_invalid(paths, "persisted Session content does not match deterministic reconstruction")
    end
  end

  def test_missing_revision_metadata_is_rejected
    with_generated_revision do |paths|
      mutate_revision(paths.last) { |revision| revision.delete("revision") }

      assert_invalid(paths, "persisted Session is missing revision lineage metadata")
    end
  end

  def test_illegal_persisted_state_is_rejected
    with_generated_revision do |paths|
      mutate_revision(paths.last) { |revision| revision["status"] = "gap_scan" }

      assert_invalid(paths, "revision metadata requires a post-clarification Session state")
    end
  end

  def test_non_confirmed_receipt_cannot_replay_a_revision
    with_generated_revision do |paths|
      confirmation = load_yaml(paths.fetch(3))
      response = "请先修改当前 Proposal。"
      confirmation["confirmation_decision"] = "modify_requested"
      confirmation["revision_creation_authorized"] = false
      confirmation["user_response"] = response
      confirmation["user_response_sha256"] = Digest::SHA256.hexdigest(response)
      write_yaml(paths.fetch(3), confirmation)

      assert_invalid(paths, "confirmation decision does not authorize revision creation")
    end
  end

  def test_success_copy_hides_paths_hashes_ids_and_raw_user_text
    with_generated_revision do |paths|
      verifier = lineage_verifier
      copy = verifier.verify_files(*paths)
      confirmation = load_yaml(paths.fetch(3))
      answer_receipt = load_yaml(paths.fetch(1))

      paths.each { |path| refute_includes copy, path }
      refute_includes copy, confirmation["user_response"]
      refute_includes copy, answer_receipt.dig("responses", 0, "user_answer")
      refute_includes copy, confirmation["confirmation_id"]
      refute_includes copy, confirmation["proposal_id"]
      refute_includes copy, confirmation["user_response_sha256"]
      refute_includes copy, "product-owner-test"
      refute_includes copy, "constraints.product"
    end
  end

  def test_dynamic_risk_copy_is_markdown_safe
    Dir.mktmpdir("pmind-lineage-markdown") do |directory|
      paths = write_chain(directory, "ready_to_compile", "<script>_approval_")
      verifier = lineage_verifier
      copy = verifier.verify_files(*paths)

      assert copy, verifier.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_approval\\_"
    end
  end

  def test_cli_is_read_only_for_all_five_inputs
    with_generated_revision do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/verify_clarification_revision_lineage.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "来源链已验证"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_missing_revision_without_echoing_raw_text
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/verify_clarification_revision_lineage.rb"),
      SESSION_FIXTURE,
      RECEIPT_FIXTURE,
      PROPOSAL_FIXTURE,
      CONFIRMATION_FIXTURE,
      "missing-revision.yaml",
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "cannot load YAML"
    refute_includes stderr, load_yaml(RECEIPT_FIXTURE).dig("responses", 0, "user_answer")
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/verify_clarification_revision_lineage.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_generated_revision
    Dir.mktmpdir("pmind-lineage") do |directory|
      yield write_chain(directory, "ready_to_compile")
    end
  end

  def write_chain(directory, target_status, risk_description = nil)
    session = load_yaml(SESSION_FIXTURE)
    receipt = load_yaml(RECEIPT_FIXTURE)
    proposal = proposal_for_status(load_yaml(PROPOSAL_FIXTURE), target_status)
    if risk_description
      session.dig("compile_gate", "high_risk_actions", 0)["description"] = risk_description
      proposal.dig("patch", "compile_gate_after", "high_risk_actions", 0)["description"] = risk_description
    end

    session_path = File.join(directory, "source-session.yaml")
    receipt_path = File.join(directory, "answer-receipt.yaml")
    proposal_path = File.join(directory, "proposal.yaml")
    confirmation_path = File.join(directory, "confirmation.yaml")
    revision_path = File.join(directory, "revision.yaml")
    write_yaml(session_path, session)
    write_yaml(receipt_path, receipt)
    write_yaml(proposal_path, proposal)

    confirmation = load_yaml(CONFIRMATION_FIXTURE)
    confirmation["source_session_file_sha256"] = Digest::SHA256.file(session_path).hexdigest
    confirmation["answer_receipt_file_sha256"] = Digest::SHA256.file(receipt_path).hexdigest
    confirmation["proposal_file_sha256"] = Digest::SHA256.file(proposal_path).hexdigest
    confirmation["target_session_status"] = target_status
    write_yaml(confirmation_path, confirmation)

    creator = PMind::ClarificationRevisionCreator.new(ROOT)
    created = creator.create_files(session_path, receipt_path, proposal_path, confirmation_path, revision_path)
    raise creator.errors.join("\n") unless created

    [session_path, receipt_path, proposal_path, confirmation_path, revision_path]
  end

  def proposal_for_status(proposal, target_status)
    patch = proposal.fetch("patch")
    patch["status_after"] = target_status
    gate = patch.fetch("compile_gate_after")
    case target_status
    when "ready_to_compile"
      proposal
    when "clarifying"
      patch["questions_to_add"] = [pending_question]
      gate["ready"] = false
      gate["next_question_ids"] = ["QUESTION-002"]
      gate["stop_reason"] = "not_stopped"
      proposal
    when "blocked"
      answer = patch.dig("append_round", "answers", 0)
      answer["outcome_status"] = "unknown"
      answer["normalized_conclusion"] = "授权角色仍无法确认。"
      answer["user_visible_effect"] = "导出能力保持阻塞。"
      gap = patch.fetch("gap_updates").first
      gap["status"] = "unknown"
      gap["blocking"] = true
      gap["summary"] = "授权角色仍无法确认。"
      gap["knowledge_ref"] = "UNKNOWN-003"
      patch["unknowns_to_add"] = [{
        "unknown_id" => "UNKNOWN-003",
        "question" => "哪些角色被授权导出？",
        "blocking" => true
      }]
      gate["ready"] = false
      gate["blocking_reasons"] = ["导出权限无法安全默认。"]
      gate["next_question_ids"] = []
      gate["stop_reason"] = "blocked"
      proposal
    end
  end

  def pending_question
    {
      "question_id" => "QUESTION-002",
      "gap_dimension" => "evidence",
      "question" => "现有本地化约定是什么？",
      "why_now" => "需要确定后续界面文案。",
      "affected_fields" => ["knowledge.unknowns"],
      "safe_default_or_stop" => "未回答时保留为非阻塞 unknown。",
      "priority" => {
        "materiality" => 2,
        "uncertainty" => 2,
        "answerability" => 1,
        "friction" => 1,
        "score" => 4
      },
      "status" => "pending"
    }
  end

  def assert_invalid(paths, expected_error)
    verifier = lineage_verifier
    refute verifier.verify_files(*paths)
    assert verifier.errors.any? { |error| error.include?(expected_error) }, verifier.errors.join("\n")
  end

  def mutate_revision(path)
    revision = load_yaml(path)
    yield revision
    write_yaml(path, revision)
  end

  def lineage_verifier
    PMind::ClarificationRevisionLineageVerifier.new(ROOT)
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
