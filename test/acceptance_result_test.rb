# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "fileutils"
require "tmpdir"
require_relative "../scripts/validate_evals"

class AcceptanceResultTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def setup
    loader = PMind::EvalValidator.new(ROOT)
    @case_document = loader.load_yaml("evals/cases/seed/seed-001-csv-export.yaml")
    @schema = loader.load_yaml("evals/schema/acceptance-result-v0.yaml")
  end

  def test_consensus_is_accepted_when_two_primary_decisions_match
    result = base_result("consensus", pass_decision, pass_decision)
    result["final_decision"] = pass_decision

    assert_valid(result, pass_run)
  end

  def test_disagreement_can_wait_for_adjudication_without_a_final_decision
    result = base_result("needs_adjudication", pass_decision, fail_decision)

    assert_valid(result, not_scored_run)
  end

  def test_disagreement_can_be_closed_by_a_distinct_adjudicator
    result = base_result("adjudicated", pass_decision, fail_decision)
    result["final_decision"] = fail_decision
    result["adjudicator_ref"] = "reviewer-3"

    assert_valid(result, fail_run)
  end

  def test_consensus_rejects_differing_primary_decisions
    result = base_result("consensus", pass_decision, fail_decision)
    result["final_decision"] = pass_decision

    assert_invalid(result, pass_run, "consensus requires matching reviewer decisions")
  end

  def test_pending_adjudication_rejects_a_premature_final_decision
    result = base_result("needs_adjudication", pass_decision, fail_decision)
    result["final_decision"] = pass_decision

    assert_invalid(result, not_scored_run, "must not contain final_decision")
  end

  def test_adjudicated_state_requires_a_distinct_adjudicator
    result = base_result("adjudicated", pass_decision, fail_decision)
    result["final_decision"] = fail_decision

    assert_invalid(result, fail_run, "requires a distinct adjudicator_ref")
  end

  def test_first_pass_success_is_derived_from_blocking_criteria
    inconsistent = pass_decision
    inconsistent["criteria"].first["result"] = "fail"
    result = base_result("consensus", inconsistent, inconsistent)
    result["final_decision"] = deep_copy(inconsistent)

    assert_invalid(result, pass_run, "does not match the rubric formula")
  end

  def test_reviewer_identities_must_be_unique
    result = base_result("consensus", pass_decision, pass_decision)
    result["reviewer_assessments"].last["reviewer_ref"] = "reviewer-1"
    result["final_decision"] = pass_decision

    assert_invalid(result, pass_run, "reviewer_ref reviewer-1 must be unique")
  end

  def test_each_decision_must_cover_every_case_criterion_once_and_in_order
    incomplete = pass_decision
    incomplete["criteria"].pop
    result = base_result("consensus", incomplete, incomplete)
    result["final_decision"] = deep_copy(incomplete)

    assert_invalid(result, pass_run, "must cover acceptance criteria once and in case order")
  end

  def test_diagnostic_scores_are_capped_at_two
    oversized = pass_decision
    oversized["diagnostic_scores"]["acceptance"] = 3
    result = base_result("consensus", oversized, oversized)
    result["final_decision"] = deep_copy(oversized)

    assert_invalid(result, pass_run, "must be <= 2")
  end

  def test_evidence_must_be_preserved_inside_the_run_directory
    outside_evidence = pass_decision
    outside_evidence["criteria"].first["evidence_paths"] = ["README.md"]
    result = base_result("consensus", outside_evidence, outside_evidence)
    result["final_decision"] = deep_copy(outside_evidence)

    assert_invalid(result, pass_run, "evidence path must be a regular file inside its run directory")
  end

  def test_malformed_reviewer_collection_is_rejected_without_crashing
    result = base_result("consensus", pass_decision, pass_decision)
    result["reviewer_assessments"] = { "unexpected" => "shape" }

    assert_invalid(result, pass_run, "expected array")
  end

  def test_malformed_criterion_is_rejected_without_crashing
    malformed = pass_decision
    malformed["criteria"] = [123]
    result = base_result("consensus", malformed, malformed)
    result["final_decision"] = deep_copy(malformed)

    assert_invalid(result, pass_run, "expected object")
  end

  def test_preserved_run_artifacts_and_receipt_digests_are_cross_checked
    Dir.mktmpdir("pmind-acceptance-") do |root|
      run, result = preserved_run(root)
      validator = artifact_validator(root)

      validator.send(:validate_run_artifacts, run, @case_document, "artifact-test")

      assert_empty validator.errors, validator.errors.join("\n")
      assert_equal result["run_id"], run["run_id"]
    end
  end

  def test_stale_preserved_receipt_digest_is_rejected
    Dir.mktmpdir("pmind-acceptance-") do |root|
      run, = preserved_run(root)
      run["workspace_set_receipt_digest"] = "0" * 64
      validator = artifact_validator(root)

      validator.send(:validate_run_artifacts, run, @case_document, "artifact-test")

      assert validator.errors.any? { |error| error.include?("workspace_set_receipt_digest does not match") },
             validator.errors.join("\n")
    end
  end

  private

  def assert_valid(result, run)
    validator = PMind::EvalValidator.new(ROOT)

    assert validator.validate_acceptance_result(result, @case_document, run, "acceptance-test", @schema),
           validator.errors.join("\n")
  end

  def assert_invalid(result, run, expected_error)
    validator = PMind::EvalValidator.new(ROOT)

    refute validator.validate_acceptance_result(result, @case_document, run, "acceptance-test", @schema)
    assert validator.errors.any? { |error| error.include?(expected_error) }, validator.errors.join("\n")
  end

  def base_result(status, first_decision, second_decision)
    {
      "schema_version" => "0.1.0",
      "run_id" => "run-seed-001-baseline-001",
      "case_id" => "seed-001",
      "arm" => "baseline",
      "rubric_version" => "0.1.0",
      "status" => status,
      "reviewer_assessments" => [
        { "reviewer_ref" => "reviewer-1", "decision" => deep_copy(first_decision) },
        { "reviewer_ref" => "reviewer-2", "decision" => deep_copy(second_decision) }
      ]
    }
  end

  def preserved_run(root)
    relative_root = "evals/runs/run-seed-001-baseline-001"
    absolute_root = File.join(root, relative_root)
    FileUtils.mkdir_p(absolute_root)
    artifacts = {
      "input.md" => "Test-only raw input.\n",
      "result.md" => "Test-only delivery result.\n",
      "executor-profile.yaml" => "profile: frozen-test-profile\n",
      "workspace-set.yaml" => "workspace_set: frozen-test-receipt\n"
    }
    artifacts.each do |name, content|
      File.write(File.join(absolute_root, name), content)
    end

    result = base_result("consensus", pass_decision, pass_decision)
    result["final_decision"] = pass_decision
    File.write(File.join(absolute_root, "acceptance.yaml"), YAML.dump(result))

    run = pass_run.merge(
      "input_artifact_path" => "#{relative_root}/input.md",
      "result_path" => "#{relative_root}/result.md",
      "acceptance_results_path" => "#{relative_root}/acceptance.yaml",
      "executor_profile_path" => "#{relative_root}/executor-profile.yaml",
      "executor_profile_revision" => Digest::SHA256.file(File.join(absolute_root, "executor-profile.yaml")).hexdigest,
      "workspace_set_receipt_path" => "#{relative_root}/workspace-set.yaml",
      "workspace_set_receipt_digest" => Digest::SHA256.file(File.join(absolute_root, "workspace-set.yaml")).hexdigest
    )
    [run, result]
  end

  def artifact_validator(root)
    validator = PMind::EvalValidator.new(root)
    validator.instance_variable_set(:@acceptance_result_schema, @schema)
    validator
  end

  def pass_decision
    decision_with(
      @case_document.dig("oracle", "acceptance_criteria").map do |criterion|
        criterion_result(criterion["criterion_id"], "pass")
      end,
      true,
      "none"
    )
  end

  def fail_decision
    criteria = @case_document.dig("oracle", "acceptance_criteria").map do |criterion|
      result = criterion["criterion_id"] == "AC-01" ? "fail" : "pass"
      criterion_result(criterion["criterion_id"], result)
    end
    decision_with(criteria, false, "evaluation_ambiguity")
  end

  def decision_with(criteria, success, failure)
    {
      "run_valid" => true,
      "invalid_reasons" => [],
      "criteria" => criteria,
      "material_respecification" => false,
      "safety_violation" => false,
      "usable_without_restart" => true,
      "first_pass_delivery_success" => success,
      "diagnostic_scores" => {
        "acceptance" => 2,
        "specification_fidelity" => 2,
        "traceability" => 2,
        "safety_authority" => 2,
        "delivery_efficiency" => 2,
        "user_usability" => 2
      },
      "primary_failure_classification" => failure
    }
  end

  def criterion_result(criterion_id, result)
    {
      "criterion_id" => criterion_id,
      "result" => result,
      "rationale" => "Test-only assessment rationale.",
      "evidence_paths" => []
    }
  end

  def base_run(outcome, failure)
    {
      "run_id" => "run-seed-001-baseline-001",
      "arm" => "baseline",
      "rubric_version" => "0.1.0",
      "outcome" => outcome,
      "failure_classification" => failure
    }
  end

  def pass_run
    base_run("pass", "none")
  end

  def fail_run
    base_run("fail", "evaluation_ambiguity")
  end

  def not_scored_run
    base_run("not_scored", "not_scored")
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
