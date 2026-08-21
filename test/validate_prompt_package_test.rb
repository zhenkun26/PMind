# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tempfile"
require "yaml"
require_relative "../scripts/validate_prompt_package"

class ValidatePromptPackageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FIXTURE = File.join(ROOT, "test/fixtures/prompt-package-valid.yaml")

  def test_required_action_is_valid_when_it_remains_prohibited
    assert_valid(package)
  end

  def test_approved_action_is_valid_when_authorized_by_an_identified_approver
    document = package
    approval = document.fetch("approval_points").first
    approval["status"] = "approved"
    approval["approver_ref"] = "security-owner-test"
    document.dig("handoff", "prohibited_actions").delete("external_service_write")
    document.dig("handoff", "authorized_actions") << "external_service_write"

    assert_valid(document)
  end

  def test_rejected_action_is_valid_when_it_remains_prohibited
    document = package
    approval = document.fetch("approval_points").first
    approval["status"] = "rejected"
    approval["approver_ref"] = "security-owner-test"

    assert_valid(document)
  end

  def test_not_applicable_action_is_valid_when_absent_from_handoff_lists
    document = package
    approval = document.fetch("approval_points").first
    approval["status"] = "not_applicable"
    approval["action"] = "production_data_access"
    document.fetch("risks").first["requires_approval"] = false

    assert_valid(document)
  end

  def test_not_ready_package_can_preserve_a_review_block_truthfully
    document = package
    document.fetch("review_findings").first["verdict"] = "block"
    document.fetch("handoff")["ready"] = false

    assert_valid(document)
  end

  def test_not_ready_package_can_preserve_a_blocking_unknown_truthfully
    document = package
    document.dig("knowledge", "unknowns").first["blocking"] = true
    document.fetch("handoff")["ready"] = false

    assert_valid(document)
  end

  def test_approved_action_cannot_remain_prohibited
    document = package
    approval = document.fetch("approval_points").first
    approval["status"] = "approved"
    approval["approver_ref"] = "security-owner-test"

    assert_invalid(document, "approved action external_service_write must be authorized")
  end

  def test_required_action_cannot_be_authorized
    document = package
    document.dig("handoff", "prohibited_actions").delete("external_service_write")
    document.dig("handoff", "authorized_actions") << "external_service_write"

    assert_invalid(document, "required action external_service_write must remain prohibited")
  end

  def test_rejected_action_requires_an_identified_approver
    document = package
    document.fetch("approval_points").first["status"] = "rejected"

    assert_invalid(document, "rejected approval APPROVAL-001 requires approver_ref")
  end

  def test_approver_reference_cannot_be_blank_or_whitespace
    document = package
    approval = document.fetch("approval_points").first
    approval["status"] = "approved"
    approval["approver_ref"] = " "

    assert_invalid(document, "does not match")
  end

  def test_not_applicable_action_cannot_appear_in_handoff_lists
    document = package
    approval = document.fetch("approval_points").first
    approval["status"] = "not_applicable"
    approval["action"] = "production_data_access"
    document.fetch("risks").first["requires_approval"] = false
    document.dig("handoff", "prohibited_actions") << "production_data_access"

    assert_invalid(document, "not_applicable action production_data_access must not appear")
  end

  def test_action_cannot_be_both_authorized_and_prohibited
    document = package
    document.dig("handoff", "authorized_actions") << "commit"

    assert_invalid(document, "action commit cannot be both authorized and prohibited")
  end

  def test_ready_handoff_rejects_a_blocking_unknown
    document = package
    document.dig("knowledge", "unknowns").first["blocking"] = true

    assert_invalid(document, "handoff.ready cannot be true (blocking unknown remains)")
  end

  def test_ready_handoff_rejects_a_review_block
    document = package
    document.fetch("review_findings").first["verdict"] = "block"

    assert_invalid(document, "handoff.ready cannot be true (Review Lens block remains)")
  end

  def test_all_six_review_lenses_are_required
    document = package
    document.fetch("review_findings").delete_if { |finding| finding["lens_id"] == "user_value" }

    assert_invalid(document, "missing required Review Lens user_value")
  end

  def test_fact_rejects_an_unresolved_evidence_reference
    document = package
    document.dig("knowledge", "facts").first["source_refs"] = ["EVID-999"]

    assert_invalid(document, "unresolved fact source reference EVID-999")
  end

  def test_rejected_evidence_cannot_support_a_review_finding
    document = package
    document.dig("knowledge", "evidence").first["trust_status"] = "rejected"

    assert_invalid(document, "cannot use rejected evidence EVID-001")
  end

  def test_risk_requiring_approval_cannot_be_uncovered
    document = package
    document["approval_points"] = []

    assert_invalid(document, "risk RISK-001 requires an active Approval Point")
  end

  def test_default_high_risk_action_cannot_silently_disappear
    document = package
    document.dig("handoff", "prohibited_actions").delete("commit")

    assert_invalid(document, "default high-risk action commit must remain prohibited")
  end

  def test_identifiers_must_be_unique_within_their_namespace
    document = package
    duplicate = deep_copy(document.fetch("acceptance_criteria").first)
    duplicate["statement"] = "另一条使用同一稳定标识的验收标准。"
    document.fetch("acceptance_criteria") << duplicate

    assert_invalid(document, "duplicate criterion_id AC-01")
  end

  def test_malformed_knowledge_shape_is_rejected_without_crashing
    document = package
    document["knowledge"] = "invalid"

    assert_invalid(document, "expected object")
  end

  def test_cli_validates_a_package_without_writing_files
    before = File.binread(FIXTURE)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      File.join(ROOT, "scripts/validate_prompt_package.rb"),
      FIXTURE,
      chdir: ROOT
    )

    assert status.success?, stderr
    assert_includes stdout, "PMIND_PROMPT_PACKAGE_VALIDATION_PASS"
    assert_includes stdout, "ready=true"
    assert_equal "", stderr
    assert_equal before, File.binread(FIXTURE)
  end

  def test_cli_returns_failure_for_an_invalid_package
    document = package
    document.dig("knowledge", "unknowns").first["blocking"] = true
    Tempfile.create(["pmind-invalid-package-", ".yaml"]) do |file|
      file.write(YAML.dump(document))
      file.flush

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        File.join(ROOT, "scripts/validate_prompt_package.rb"),
        file.path,
        chdir: ROOT
      )

      refute status.success?
      assert_equal "", stdout
      assert_includes stderr, "handoff.ready cannot be true"
    end
  end

  private

  def assert_valid(document)
    validator = PMind::PromptPackageValidator.new(ROOT)

    assert validator.validate(document), validator.errors.join("\n")
  end

  def assert_invalid(document, expected_error)
    validator = PMind::PromptPackageValidator.new(ROOT)

    refute validator.validate(document)
    assert validator.errors.any? { |error| error.include?(expected_error) }, validator.errors.join("\n")
  end

  def package
    YAML.safe_load(
      File.read(FIXTURE),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end
