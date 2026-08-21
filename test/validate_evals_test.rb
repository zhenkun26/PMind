# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/validate_evals"

class ValidateEvalsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_repository_assets_are_valid
    validator = PMind::EvalValidator.new(ROOT)

    assert validator.validate_repository, validator.errors.join("\n")
    assert_equal 10, validator.summary["cases"]
    assert_equal 3, validator.summary["fixtures"]
    assert_equal 1, validator.summary["executor_profiles"]
    assert_equal 1, validator.summary["calibration_waves"]
    assert_equal 0, validator.summary["acceptance_results"]
    assert_equal 9, validator.summary["gap_dimensions"]
  end

  def test_schema_const_violation_is_rejected
    validator = PMind::EvalValidator.new(ROOT)
    schema = validator.load_yaml("evals/schema/case-v0.yaml")
    document = validator.load_yaml("evals/cases/seed/seed-001-csv-export.yaml")
    document["schema_version"] = "9.9.9"

    refute validator.validate_document(schema, document, "mutated-case", schema)
    assert validator.errors.any? { |error| error.include?("expected constant") }
  end

  def test_case_unknown_must_be_declared_in_coverage
    validator = PMind::EvalValidator.new(ROOT)
    entries = Dir[File.join(ROOT, "evals/cases/seed/*.yaml")].sort.map do |path|
      [path, validator.load_yaml(path)]
    end
    first_case = entries.first[1]
    missing_dimension = first_case.dig("oracle", "material_unknowns").first["dimension"]
    first_case.dig("coverage", "gap_dimensions").delete(missing_dimension)

    refute validator.validate_case_set(entries)
    assert validator.errors.any? { |error| error.include?("is not declared in coverage") }
  end

  def test_ready_wave_rejects_unassigned_roles_and_unfrozen_executor
    validator = PMind::EvalValidator.new(ROOT)
    manifest = validator.load_yaml("evals/calibration/wave-01.yaml")
    manifest["can_start"] = true
    manifest["status"] = "ready"
    manifest["blocked_reasons"] = []
    case_ids = %w[seed-001 seed-006 seed-009]

    refute validator.validate_calibration(manifest, case_ids, "mutated-wave")
    assert validator.errors.any? { |error| error.include?("must be assigned") }
    assert validator.errors.any? { |error| error.include?("executor configuration must be frozen") }
  end

  def test_fixture_rejects_workspace_digest_drift
    validator = PMind::EvalValidator.new(ROOT)
    fixture = validator.load_yaml("evals/fixtures/seed-001/fixture.yaml")
    fixture["workspace_revision"]["digest"] = "0" * 64

    refute validator.validate_fixture(fixture, "evals/fixtures/seed-001/fixture.yaml")
    assert validator.errors.any? { |error| error.include?("workspace digest mismatch") }
  end

  def test_calibration_fixture_gate_must_match_ready_manifests
    validator = PMind::EvalValidator.new(ROOT)
    manifest = validator.load_yaml("evals/calibration/wave-01.yaml")
    manifest["start_gates"]["fixtures_ready"] = false
    fixtures = %w[seed-001 seed-006 seed-009].to_h do |case_id|
      [case_id, validator.load_yaml("evals/fixtures/#{case_id}/fixture.yaml")]
    end

    refute validator.validate_calibration(
      manifest,
      fixtures.keys,
      "mutated-wave",
      fixtures
    )
    assert validator.errors.any? { |error| error.include?("fixtures_ready gate does not match") }
  end

  def test_executor_profile_unresolved_fields_must_match_missing_decisions
    validator = PMind::EvalValidator.new(ROOT)
    profile = validator.load_yaml("evals/calibration/executor-profiles/calibration-001.yaml")
    profile["unresolved_fields"].delete("model_version")

    refute validator.validate_executor_profile(profile, "mutated-profile")
    assert validator.errors.any? { |error| error.include?("must exactly match missing executor decisions") }
  end

  def test_role_gate_rejects_reused_assignee_references
    validator = PMind::EvalValidator.new(ROOT)
    manifest = validator.load_yaml("evals/calibration/wave-01.yaml")
    manifest["roles"].each_value do |assignment|
      assignment["status"] = "assigned"
      assignment["assignee_ref"] = "same-person"
    end
    profile_path = "evals/calibration/executor-profiles/calibration-001.yaml"
    profile = validator.load_yaml(profile_path)

    refute validator.validate_calibration(
      manifest,
      %w[seed-001 seed-006 seed-009],
      "mutated-wave",
      {},
      profile,
      profile_path
    )
    assert validator.errors.any? { |error| error.include?("cannot hold multiple calibration roles") }
  end

  def test_role_gate_must_match_four_distinct_assignments
    validator = PMind::EvalValidator.new(ROOT)
    manifest = validator.load_yaml("evals/calibration/wave-01.yaml")
    manifest["roles"].each_with_index do |(_role, assignment), index|
      assignment["status"] = "assigned"
      assignment["assignee_ref"] = "person-#{index + 1}"
    end
    profile_path = "evals/calibration/executor-profiles/calibration-001.yaml"
    profile = validator.load_yaml(profile_path)

    refute validator.validate_calibration(
      manifest,
      %w[seed-001 seed-006 seed-009],
      "mutated-wave",
      {},
      profile,
      profile_path
    )
    assert validator.errors.any? { |error| error.include?("roles_assigned gate does not match") }
  end

  def test_fail_run_requires_concrete_failure_classification
    validator = PMind::EvalValidator.new(ROOT)
    schema = validator.load_yaml("evals/schema/case-v0.yaml")
    entries = Dir[File.join(ROOT, "evals/cases/seed/*.yaml")].sort.map do |path|
      [path, validator.load_yaml(path)]
    end
    entries.first[1]["run_records"] = [valid_run.merge(
      "outcome" => "fail",
      "failure_classification" => "none"
    )]

    assert validator.validate_document(schema, entries.first[1], "mutated-run", schema)
    refute validator.validate_case_set(entries)
    assert validator.errors.any? { |error| error.include?("requires a concrete failure classification") }
  end

  def test_invalid_run_requires_concrete_failure_classification
    validator = PMind::EvalValidator.new(ROOT)
    entries = Dir[File.join(ROOT, "evals/cases/seed/*.yaml")].sort.map do |path|
      [path, validator.load_yaml(path)]
    end
    entries.first[1]["run_records"] = [valid_run.merge(
      "outcome" => "invalid_run",
      "failure_classification" => "not_scored"
    )]

    refute validator.validate_case_set(entries)
    assert validator.errors.any? { |error| error.include?("invalid_run outcome requires a concrete failure classification") }
  end

  def test_case_schema_keeps_real_case_run_identifiers_available
    validator = PMind::EvalValidator.new(ROOT)
    schema = validator.load_yaml("evals/schema/case-v0.yaml")
    run_schema = schema.dig("properties", "run_records", "items")
    real_run = valid_run.merge(
      "run_id" => "run-real-001-baseline-001",
      "input_artifact_path" => "evals/runs/run-real-001-baseline-001/input.md",
      "result_path" => "evals/runs/run-real-001-baseline-001/result.md",
      "acceptance_results_path" => "evals/runs/run-real-001-baseline-001/acceptance.yaml",
      "executor_profile_path" => "evals/runs/run-real-001-baseline-001/executor-profile.yaml",
      "workspace_set_receipt_path" => "evals/runs/run-real-001-baseline-001/workspace-set.yaml"
    )

    assert validator.validate_document(run_schema, real_run, "real-run", schema), validator.errors.join("\n")
  end

  private

  def valid_run
    {
      "run_id" => "run-seed-001-baseline-001",
      "arm" => "baseline",
      "protocol_version" => "0.1.0",
      "input_artifact_path" => "evals/runs/run-seed-001-baseline-001/input.md",
      "started_at" => "2026-08-21T10:00:00+08:00",
      "finished_at" => "2026-08-21T10:05:00+08:00",
      "executor_profile_path" => "evals/runs/run-seed-001-baseline-001/executor-profile.yaml",
      "executor_profile_revision" => "a" * 64,
      "executor_version" => "test-executor",
      "model_version" => "test-model",
      "reasoning_settings" => "fixed-test-settings",
      "workspace_set_receipt_digest" => "b" * 64,
      "workspace_set_receipt_path" => "evals/runs/run-seed-001-baseline-001/workspace-set.yaml",
      "workspace_base_revision" => "c" * 64,
      "workspace_result_revision" => "d" * 64,
      "tool_policy" => "no-external-writes",
      "pre_handoff_clarification_rounds" => 0,
      "executor_clarification_rounds" => 0,
      "executor_rework_rounds" => 0,
      "material_rework_rounds" => 0,
      "idea_to_handoff_minutes" => 1,
      "handoff_to_result_minutes" => 5,
      "model_calls" => 1,
      "search_calls" => 0,
      "human_intervention_minutes" => 0,
      "estimated_cost" => {
        "status" => "unknown",
        "currency" => "USD",
        "amount_decimal" => "unknown"
      },
      "protocol_deviations" => [],
      "rubric_version" => "0.1.0",
      "outcome" => "pass",
      "failure_classification" => "none",
      "result_path" => "evals/runs/run-seed-001-baseline-001/result.md",
      "acceptance_results_path" => "evals/runs/run-seed-001-baseline-001/acceptance.yaml"
    }
  end
end
