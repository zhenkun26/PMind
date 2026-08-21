# frozen_string_literal: true

require "json"
require "minitest/autorun"

class AdminSnapshotTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_package_and_metrics_match_frozen_case_context
    package = JSON.parse(File.read(File.join(ROOT, "package.json")))
    metrics = JSON.parse(File.read(File.join(ROOT, "metrics.json")))

    assert_equal "18.2.0", package.dig("dependencies", "react")
    assert_equal "5.5.4", package.dig("devDependencies", "typescript")
    assert_equal 25_000, metrics["estimated_source_lines"]
    assert_equal 2, metrics["frontend_engineers"]
    assert_equal 6, metrics["migration_window_weeks"]
    assert_equal "representative_excerpt", metrics["snapshot_kind"]
  end

  def test_snapshot_is_unmodified_and_dependency_free
    refute File.exist?(File.join(ROOT, "node_modules"))
    refute File.exist?(File.join(ROOT, "FRAMEWORK_RECOMMENDATION.md"))
    assert File.exist?(File.join(ROOT, "src", "AdminApp.tsx"))
    assert File.exist?(File.join(ROOT, "src", "forms", "ProjectForm.tsx"))
  end
end
