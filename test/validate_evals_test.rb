# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/validate_evals"

class ValidateEvalsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_repository_assets_are_valid
    validator = PMind::EvalValidator.new(ROOT)

    assert validator.validate_repository, validator.errors.join("\n")
    assert_equal 10, validator.summary["cases"]
    assert_equal 1, validator.summary["calibration_waves"]
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

  def test_ready_wave_rejects_unassigned_roles_and_missing_fixtures
    validator = PMind::EvalValidator.new(ROOT)
    manifest = validator.load_yaml("evals/calibration/wave-01.yaml")
    manifest["can_start"] = true
    manifest["status"] = "ready"
    manifest["blocked_reasons"] = []
    case_ids = %w[seed-001 seed-006 seed-009]

    refute validator.validate_calibration(manifest, case_ids, "mutated-wave")
    assert validator.errors.any? { |error| error.include?("must be assigned") }
    assert validator.errors.any? { |error| error.include?("fixture must be ready") }
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

  private

  def valid_run
    {
      "run_id" => "run-seed-001-baseline-001",
      "arm" => "baseline",
      "protocol_version" => "0.1.0",
      "input_artifact_path" => "evals/runs/run-seed-001-baseline-001/input.md",
      "started_at" => "2026-08-21T10:00:00+08:00",
      "finished_at" => "2026-08-21T10:05:00+08:00",
      "executor_version" => "test-executor",
      "workspace_revision" => "fixture-revision",
      "tool_policy" => "no-external-writes",
      "pre_handoff_clarification_rounds" => 0,
      "executor_clarification_rounds" => 0,
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
