# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/calibration_preflight"

class CalibrationPreflightTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_current_wave_reports_only_real_readiness_blockers
    result = PMind::CalibrationPreflight.new(ROOT).run

    assert_equal "blocked", result.status
    assert_equal true, result.gates["contracts_valid"]
    assert_equal true, result.gates["rubric_frozen"]
    assert_equal true, result.gates["fixtures_ready"]
    assert_equal false, result.gates["roles_assigned"]
    assert_equal false, result.gates["executor_frozen"]
    assert_equal false, result.gates["isolated_workspaces_ready"]
    assert result.blockers.any? { |blocker| blocker.include?("roles unassigned") }
    assert result.blockers.any? { |blocker| blocker.include?("executor profile unresolved") }
    assert result.blockers.any? { |blocker| blocker.include?("workspace set was not supplied") }
  end

  def test_verified_workspace_set_clears_only_the_isolation_blocker
    Dir.mktmpdir("pmind-preflight-test-") do |parent|
      output = File.join(parent, "calibration-001")
      PMind::CalibrationWorkspacePreparer.new(ROOT).prepare(
        output: output,
        prepared_at: "2026-08-21T12:00:00Z"
      )

      result = PMind::CalibrationPreflight.new(ROOT).run(workspace_set: output)

      assert_equal "blocked", result.status
      assert_equal true, result.gates["isolated_workspaces_ready"]
      refute result.blockers.any? { |blocker| blocker.include?("workspace set was not supplied") }
      assert result.blockers.any? { |blocker| blocker.include?("isolated_workspaces_ready") }
    end
  end

  def test_invalid_workspace_set_remains_blocked
    result = PMind::CalibrationPreflight.new(ROOT).run(workspace_set: "/path/that/does/not/exist")

    assert_equal "blocked", result.status
    assert_equal false, result.gates["isolated_workspaces_ready"]
    assert result.blockers.any? { |blocker| blocker.include?("workspace set is invalid") }
  end
end
