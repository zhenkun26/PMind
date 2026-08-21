# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "../scripts/prepare_calibration_workspaces"

class PrepareCalibrationWorkspacesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PREPARED_AT = "2026-08-21T12:00:00Z"

  def test_prepare_creates_six_independent_copies_and_a_valid_receipt
    with_output do |preparer, output|
      prepared = preparer.prepare(output: output, prepared_at: PREPARED_AT)
      manifest = load_yaml(File.join(prepared, "workspace-set.yaml"))

      assert_equal File.realpath(output), prepared
      assert_equal "ready", manifest["status"]
      assert_equal false, manifest["oracle_included"]
      assert_equal 3, manifest["cases"].length
      assert preparer.verify(prepared)

      arm_paths = manifest["cases"].flat_map { |entry| entry.fetch("arms").values }
      assert_equal 6, arm_paths.length
      arm_paths.each do |arm|
        assert_equal arm["source_revision"], arm["prepared_revision"]
        assert File.directory?(File.join(prepared, arm["path"]))
      end

      baseline = File.join(prepared, "cases/seed-001/baseline/README.md")
      pmind = File.join(prepared, "cases/seed-001/pmind/README.md")
      original_pmind = File.read(pmind)
      File.open(baseline, "ab") { |file| file.write("\nbaseline-only\n") }
      assert_equal original_pmind, File.read(pmind)
    end
  end

  def test_verify_rejects_hidden_workspace_tampering
    with_output do |preparer, output|
      preparer.prepare(output: output, prepared_at: PREPARED_AT)
      target = File.join(output, "cases/seed-009/pmind/.injected")
      File.write(target, "tampered")

      error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
        preparer.verify(output)
      end
      assert_includes error.message, "has drifted from its frozen source"
    end
  end

  def test_verify_rejects_an_oracle_directory
    with_output do |preparer, output|
      preparer.prepare(output: output, prepared_at: PREPARED_AT)
      Dir.mkdir(File.join(output, "oracle"))

      error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
        preparer.verify(output)
      end
      assert_includes error.message, "undeclared entries"
    end
  end

  def test_verify_rejects_manifest_identity_drift
    with_output do |preparer, output|
      preparer.prepare(output: output, prepared_at: PREPARED_AT)
      manifest_path = File.join(output, "workspace-set.yaml")
      manifest = load_yaml(manifest_path)
      manifest.fetch("cases").first["fixture_id"] = "fixture-seed-999"
      File.open(manifest_path, "wb") { |file| file.write(YAML.dump(manifest)) }

      error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
        preparer.verify(output)
      end
      assert_includes error.message, "fixture_id does not match"
    end
  end

  def test_verify_rejects_a_symbolic_link
    with_output do |preparer, output|
      preparer.prepare(output: output, prepared_at: PREPARED_AT)
      arm = File.join(output, "cases/seed-006/baseline")
      File.symlink(File.join(arm, "README.md"), File.join(arm, "linked-readme"))

      error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
        preparer.verify(output)
      end
      assert_includes error.message, "symbolic link is forbidden"
    end
  end

  def test_prepare_refuses_to_overwrite_an_existing_target
    with_output do |preparer, output|
      Dir.mkdir(output)
      sentinel = File.join(output, "sentinel")
      File.write(sentinel, "preserve")

      error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
        preparer.prepare(output: output, prepared_at: PREPARED_AT)
      end
      assert_includes error.message, "refusing to overwrite"
      assert_equal "preserve", File.read(sentinel)
    end
  end

  def test_prepare_cleans_staging_when_the_receipt_is_invalid
    with_output do |preparer, output|
      error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
        preparer.prepare(output: output, prepared_at: "not-a-time")
      end

      assert_includes error.message, "invalid date-time"
      refute File.exist?(output)
      assert_empty Dir.children(File.dirname(output))
    end
  end

  def test_prepare_requires_an_absolute_output_outside_the_repository
    preparer = PMind::CalibrationWorkspacePreparer.new(ROOT)

    relative_error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
      preparer.prepare(output: "relative/workspaces", prepared_at: PREPARED_AT)
    end
    assert_includes relative_error.message, "absolute path"

    repository_target = File.join(ROOT, ".forbidden-calibration-workspaces")
    repository_error = assert_raises(PMind::CalibrationWorkspacePreparer::PreparationError) do
      preparer.prepare(output: repository_target, prepared_at: PREPARED_AT)
    end
    assert_includes repository_error.message, "outside the PMind repository"
    refute File.exist?(repository_target)
  end

  private

  def with_output
    Dir.mktmpdir("pmind-workspace-set-test-") do |parent|
      output = File.join(parent, "calibration-001")
      yield PMind::CalibrationWorkspacePreparer.new(ROOT), output
    end
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
