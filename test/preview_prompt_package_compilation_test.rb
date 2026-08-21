# frozen_string_literal: true

require "digest"
require "fileutils"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../scripts/preview_prompt_package_compilation"

class PreviewPromptPackageCompilationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SESSION_FIXTURE = File.join(ROOT, "test/fixtures/clarification-session-revision-ready.yaml")
  PACKAGE_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")
  PROPOSAL_FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-compilation-proposal-valid.yaml")

  def test_valid_proposal_previews_material_package_content
    preview = compilation_preview
    copy = preview.preview_files(SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE)

    assert copy, preview.errors.join("\n")
    assert_includes copy, "请确认 Prompt Package 编译提案"
    assert_includes copy, "本次范围"
    assert_includes copy, "Blocking 验收标准"
    assert_includes copy, "待单独审批"
    assert_includes copy, "不等于 Handoff 或高风险授权"
  end

  def test_handoff_not_ready_is_a_legal_review_state_but_not_creatable
    with_triplet do |paths|
      package = load_yaml(paths.fetch(1))
      package.dig("handoff")["ready"] = false
      write_yaml(paths.fetch(1), package)
      refresh_proposal_bindings(paths)

      preview = compilation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      assert_includes copy, "尚未通过结构化 Quality Gate"
      assert_includes copy, "不得创建可交接 Package"
      assert_includes copy, "不允许创建可交接 Package"
      assert_includes copy, "修正 Quality Gate 后必须重新提案"
      refute_includes copy, "允许后续受控步骤基于这份候选内容创建最终 Package"
    end
  end

  def test_non_ready_session_is_rejected
    preview = compilation_preview
    refute preview.preview_files(
      File.join(ROOT, "test/fixtures/clarification-session-gap-scan.yaml"),
      PACKAGE_FIXTURE,
      PROPOSAL_FIXTURE
    )

    assert preview.errors.any? { |error| error.include?("requires a ready_to_compile Clarification Session") }, preview.errors.join("\n")
  end

  def test_ready_session_without_revision_lineage_is_rejected
    with_triplet do |paths|
      FileUtils.cp(File.join(ROOT, "test/fixtures/clarification-session-ready.yaml"), paths.fetch(0))
      refresh_proposal_bindings(paths, revision_number: 1)

      assert_invalid(paths, "requires a persisted Session revision with lineage metadata")
    end
  end

  def test_session_to_package_lineage_drift_is_rejected
    with_triplet do |paths|
      package = load_yaml(paths.fetch(1))
      package.dig("intent", "raw_intent") << "被改写"
      write_yaml(paths.fetch(1), package)
      refresh_proposal_bindings(paths)

      assert_invalid(paths, "raw_intent must exactly match")
    end
  end

  def test_each_bound_source_file_byte_drift_is_rejected
    %w[source_session_file_sha256 draft_package_file_sha256].each_with_index do |field, index|
      with_triplet do |paths|
        File.open(paths.fetch(index), "ab") { |file| file.write("\n") }

        assert_invalid(paths, "#{field} does not match its exact source")
      end
    end
  end

  def test_each_declared_source_digest_must_match
    %w[source_session_file_sha256 draft_package_file_sha256].each do |field|
      with_triplet do |paths|
        proposal = load_yaml(paths.fetch(2))
        proposal[field] = "0" * 64
        write_yaml(paths.fetch(2), proposal)

        assert_invalid(paths, "#{field} does not match its exact source")
      end
    end
  end

  def test_revision_number_and_handoff_state_must_match
    {
      "source_session_revision_number" => 2,
      "draft_package_handoff_ready" => false
    }.each do |field, value|
      with_triplet do |paths|
        proposal = load_yaml(paths.fetch(2))
        proposal[field] = value
        write_yaml(paths.fetch(2), proposal)

        assert_invalid(paths, "#{field} does not match its exact source")
      end
    end
  end

  def test_proposal_cannot_predate_revision_or_package
    with_triplet do |paths|
      proposal = load_yaml(paths.fetch(2))
      proposal["created_at"] = "2026-08-21T11:59:00+08:00"
      write_yaml(paths.fetch(2), proposal)

      assert_invalid(paths, "cannot predate its Session revision or draft Package")
    end
  end

  def test_data_classification_and_personal_data_cannot_be_downgraded
    with_triplet do |paths|
      session = load_yaml(paths.fetch(0))
      session.dig("intake")["data_classification"] = "internal"
      session.dig("intake")["contains_personal_data"] = true
      write_yaml(paths.fetch(0), session)
      refresh_proposal_bindings(paths)

      preview = compilation_preview
      refute preview.preview_files(*paths)
      assert preview.errors.any? { |error| error.include?("data classification cannot downgrade") }, preview.errors.join("\n")
      assert preview.errors.any? { |error| error.include?("cannot drop the Session personal-data declaration") }, preview.errors.join("\n")
    end
  end

  def test_pending_proposal_cannot_declare_creation_handoff_or_risk_authorization
    %w[package_creation_authorized handoff_authorized high_risk_authorization_inferred].each do |field|
      with_triplet do |paths|
        proposal = load_yaml(paths.fetch(2))
        proposal.fetch("confirmation")[field] = true
        write_yaml(paths.fetch(2), proposal)

        assert_invalid(paths, "expected constant false")
      end
    end
  end

  def test_success_copy_hides_paths_digests_ids_and_source_content
    preview = compilation_preview
    copy = preview.preview_files(SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE)
    session = load_yaml(SESSION_FIXTURE)
    package = load_yaml(PACKAGE_FIXTURE)
    proposal = load_yaml(PROPOSAL_FIXTURE)

    [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE].each { |path| refute_includes copy, path }
    refute_includes copy, session.dig("intake", "raw_intent")
    refute_includes copy, session.dig("rounds", 0, "answers", 0, "user_answer")
    refute_includes copy, package.dig("knowledge", "evidence", 0, "source")
    refute_includes copy, package.dig("knowledge", "decisions", 0, "decision_maker_ref")
    refute_includes copy, package.dig("review_findings", 0, "owner")
    refute_includes copy, proposal["compilation_proposal_id"]
    refute_includes copy, proposal["source_session_file_sha256"]
    refute_includes copy, proposal["draft_package_file_sha256"]
  end

  def test_dynamic_user_visible_content_is_markdown_safe
    with_triplet do |paths|
      package = load_yaml(paths.fetch(1))
      package.dig("scope", "in_scope")[0] = "<script>_scope_"
      write_yaml(paths.fetch(1), package)
      refresh_proposal_bindings(paths)

      preview = compilation_preview
      copy = preview.preview_files(*paths)

      assert copy, preview.errors.join("\n")
      refute_includes copy, "<script>"
      assert_includes copy, "&lt;script&gt;\\_scope\\_"
    end
  end

  def test_cli_reads_all_three_inputs_without_writing
    with_triplet do |paths|
      before = paths.map { |path| File.binread(path) }
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/preview_prompt_package_compilation.rb"),
        *paths,
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_includes stdout, "请确认 Prompt Package 编译提案"
      assert_equal "", stderr
      assert_equal before, paths.map { |path| File.binread(path) }
    end
  end

  def test_cli_rejects_missing_input_without_echoing_source_content
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_prompt_package_compilation.rb"),
      SESSION_FIXTURE,
      PACKAGE_FIXTURE,
      "missing-compilation-proposal.yaml",
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "cannot load YAML"
    refute_includes stderr, load_yaml(SESSION_FIXTURE).dig("rounds", 0, "answers", 0, "user_answer")
  end

  def test_cli_rejects_wrong_argument_count
    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/preview_prompt_package_compilation.rb"),
      chdir: ROOT
    )

    refute status.success?
    assert_includes stderr, "Usage:"
  end

  private

  def with_triplet
    Dir.mktmpdir("pmind-compilation-preview") do |directory|
      paths = ["session.yaml", "package.yaml", "proposal.yaml"].map { |name| File.join(directory, name) }
      [SESSION_FIXTURE, PACKAGE_FIXTURE, PROPOSAL_FIXTURE].zip(paths).each do |source, target|
        FileUtils.cp(source, target)
      end
      yield paths
    end
  end

  def refresh_proposal_bindings(paths, revision_number: nil)
    session = load_yaml(paths.fetch(0))
    package = load_yaml(paths.fetch(1))
    proposal = load_yaml(paths.fetch(2))
    proposal["session_id"] = session["session_id"]
    proposal["source_session_revision_number"] = revision_number || session.dig("revision", "revision_number")
    proposal["source_session_status"] = session["status"]
    proposal["source_session_file_sha256"] = Digest::SHA256.file(paths.fetch(0)).hexdigest
    proposal["package_id"] = package["package_id"]
    proposal["draft_package_file_sha256"] = Digest::SHA256.file(paths.fetch(1)).hexdigest
    proposal["draft_package_handoff_ready"] = package.dig("handoff", "ready")
    write_yaml(paths.fetch(2), proposal)
  end

  def assert_invalid(paths, expected_error)
    preview = compilation_preview
    refute preview.preview_files(*paths)
    assert preview.errors.any? { |error| error.include?(expected_error) }, preview.errors.join("\n")
  end

  def compilation_preview
    PMind::PromptPackageCompilationPreview.new(ROOT)
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
