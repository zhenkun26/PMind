# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

class RepositoryTaskRunnerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RAKE_COMMAND = [RbConfig.ruby, "-S", "rake"].freeze

  def test_task_inventory_exposes_the_supported_verification_contract
    stdout, stderr, status = run_rake("-T")

    assert status.success?, stderr
    %w[calibration compile evals links status test verify yaml].each do |task|
      assert_match(/^rake #{task}\b/, stdout)
    end
  end

  def test_dependency_graph_keeps_status_stricter_than_local_verification
    stdout, stderr, status = run_rake("-P")

    assert status.success?, stderr
    assert_match(/rake verify\n(?:    .+\n)*    compile/, stdout)
    assert_match(/rake verify\n(?:    .+\n)*    test/, stdout)
    assert_match(/rake verify\n(?:    .+\n)*    evals/, stdout)
    assert_match(/rake status\n    verify\n    calibration/, stdout)
    assert_match(/rake default\n    status/, stdout)
  end

  def test_compile_task_rejects_warnings_and_passes_current_tree
    stdout, stderr, status = run_rake("compile")

    assert status.success?, stderr
    assert_match(/PMIND_RUBY_WARNING_COMPILATION_PASS files=\d+/, stdout)
    refute_includes stdout, "RUBY_WARNING_COMPILE_FAIL"
  end

  def test_yaml_and_link_tasks_pass_without_dependencies
    %w[yaml links].each do |task|
      stdout, stderr, status = run_rake(task)
      assert status.success?, "#{task}: #{stderr}"
      assert_includes stdout, task == "yaml" ? "PMIND_SAFE_YAML_PASS" : "PMIND_MARKDOWN_LINK_PASS"
    end
  end

  def test_eval_task_reuses_the_canonical_validator
    stdout, stderr, status = run_rake("evals")

    assert status.success?, stderr
    assert_includes stdout, "PMIND_EVAL_VALIDATION_PASS"
  end

  def test_calibration_task_preserves_the_truthful_blocked_exit
    stdout, stderr, status = run_rake("calibration")

    assert_equal 2, status.exitstatus, stderr
    assert_includes stdout, "PMIND_CALIBRATION_PREFLIGHT_BLOCKED gates=3/6"
    assert_includes stdout, "GATE roles_assigned=false"
    assert_includes stdout, "GATE executor_frozen=false"
    assert_includes stdout, "GATE isolated_workspaces_ready=false"
    refute_includes stdout, "PMIND_LOCAL_DETERMINISTIC_VERIFICATION_PASS"
  end

  def test_unknown_task_fails_without_running_verification
    stdout, stderr, status = run_rake("unknown-task")

    refute status.success?
    assert_includes stderr, "Don't know how to build task"
    refute_includes stdout, "PMIND_LOCAL_DETERMINISTIC_VERIFICATION_PASS"
  end

  private

  def run_rake(*arguments)
    Open3.capture3(*RAKE_COMMAND, *arguments, chdir: ROOT)
  end
end
