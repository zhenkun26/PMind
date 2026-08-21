#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "yaml"
require_relative "validate_evals"

module PMind
  class PromptPackageValidator
    SCHEMA_PATH = "schemas/prompt-package-v0.yaml"
    LENSES = %w[
      user_value
      scope_business
      technical_reuse
      data_safety_compliance
      delivery_operations
      testability_acceptance
    ].freeze
    DEFAULT_RESTRICTED_ACTIONS = %w[
      commit
      push
      deploy
      send_message
      external_service_write
    ].freeze

    attr_reader :errors, :package

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @package = nil
    end

    def validate_file(path)
      errors.clear
      @package = nil
      absolute = File.expand_path(path)
      document = load_yaml_file(absolute)
      return false unless document

      validate(document, path)
    end

    def validate(document, path = "prompt-package")
      errors.clear
      @package = document
      schema_validator = EvalValidator.new(@root)
      schema = schema_validator.load_yaml(SCHEMA_PATH)
      unless schema
        errors.concat(schema_validator.errors)
        return false
      end

      schema_validator.validate_document(schema, document, path, schema)
      errors.concat(schema_validator.errors)
      return false unless document.is_a?(Hash)

      validate_identifiers(document, path)
      validate_references(document, path)
      validate_reviews(document, path)
      validate_approvals(document, path)
      validate_handoff(document, path)
      errors.empty?
    end

    private

    def load_yaml_file(path)
      YAML.safe_load(
        File.read(path),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load Prompt Package (#{e.message})"
      nil
    end

    def validate_identifiers(document, path)
      knowledge = document["knowledge"].is_a?(Hash) ? document["knowledge"] : {}
      groups = {
        "fact_id" => knowledge["facts"],
        "evidence_id" => knowledge["evidence"],
        "assumption_id" => knowledge["assumptions"],
        "unknown_id" => knowledge["unknowns"],
        "decision_id" => knowledge["decisions"],
        "question_id" => document["clarifications"],
        "finding_id" => document["review_findings"],
        "criterion_id" => document["acceptance_criteria"],
        "risk_id" => document["risks"],
        "approval_id" => document["approval_points"]
      }
      constraint_entries = hash_values(document["constraints"]).flat_map { |entries| array_of_hashes(entries) }
      groups["constraint_id"] = constraint_entries

      groups.each do |field, entries|
        ids = array_of_hashes(entries).map { |entry| entry[field] }.compact
        duplicate_values(ids).each { |id| errors << "#{path}: duplicate #{field} #{id}" }
      end
    end

    def validate_references(document, path)
      knowledge = document["knowledge"].is_a?(Hash) ? document["knowledge"] : {}
      evidence = index_by(knowledge["evidence"], "evidence_id")
      assumptions = index_by(knowledge["assumptions"], "assumption_id")
      decisions = index_by(knowledge["decisions"], "decision_id")

      array_of_hashes(knowledge["facts"]).each do |fact|
        Array(fact["source_refs"]).each do |source_ref|
          next if source_ref == "user"

          validate_reference(source_ref, evidence, "fact source", path)
          if evidence.dig(source_ref, "trust_status") == "rejected"
            errors << "#{path}: fact #{fact["fact_id"]} cannot use rejected evidence #{source_ref}"
          end
        end
      end

      hash_values(document["constraints"]).flat_map { |entries| array_of_hashes(entries) }.each do |constraint|
        source_ref = constraint["source_ref"]
        next if source_ref == "user"
        next if evidence.key?(source_ref) || decisions.key?(source_ref)

        errors << "#{path}: constraint #{constraint["constraint_id"]} has unresolved source_ref #{source_ref}"
      end

      array_of_hashes(document["review_findings"]).each do |finding|
        Array(finding["evidence_ids"]).each do |evidence_id|
          validate_reference(evidence_id, evidence, "review evidence", path)
          if evidence.dig(evidence_id, "trust_status") == "rejected"
            errors << "#{path}: finding #{finding["finding_id"]} cannot use rejected evidence #{evidence_id}"
          end
        end
        Array(finding["assumption_ids"]).each do |assumption_id|
          validate_reference(assumption_id, assumptions, "review assumption", path)
        end
      end
    end

    def validate_reviews(document, path)
      findings = array_of_hashes(document["review_findings"])
      lens_ids = findings.map { |finding| finding["lens_id"] }.compact.uniq
      (LENSES - lens_ids).each do |lens_id|
        errors << "#{path}: missing required Review Lens #{lens_id}"
      end
    end

    def validate_approvals(document, path)
      risks = index_by(document["risks"], "risk_id")
      approvals = array_of_hashes(document["approval_points"])
      actions = approvals.map { |approval| approval["action"] }.compact
      duplicate_values(actions).each do |action|
        errors << "#{path}: action #{action} cannot have multiple Approval Points"
      end

      approvals.each do |approval|
        Array(approval["risk_ids"]).each do |risk_id|
          validate_reference(risk_id, risks, "approval risk", path)
        end
        if %w[approved rejected].include?(approval["status"]) && !present?(approval["approver_ref"])
          errors << "#{path}: #{approval["status"]} approval #{approval["approval_id"]} requires approver_ref"
        end
      end

      covered_risks = approvals.reject { |approval| approval["status"] == "not_applicable" }
                              .flat_map { |approval| Array(approval["risk_ids"]) }
                              .uniq
      risks.each_value do |risk|
        if risk["requires_approval"] == true && !covered_risks.include?(risk["risk_id"])
          errors << "#{path}: risk #{risk["risk_id"]} requires an active Approval Point"
        end
      end
    end

    def validate_handoff(document, path)
      handoff = document["handoff"].is_a?(Hash) ? document["handoff"] : {}
      authorized = Array(handoff["authorized_actions"])
      prohibited = Array(handoff["prohibited_actions"])
      overlap = authorized & prohibited
      overlap.each { |action| errors << "#{path}: action #{action} cannot be both authorized and prohibited" }

      approvals = array_of_hashes(document["approval_points"])
      approvals.each do |approval|
        validate_approval_action(approval, authorized, prohibited, path)
      end

      DEFAULT_RESTRICTED_ACTIONS.each do |action|
        approval = approvals.find { |entry| entry["action"] == action && entry["status"] == "approved" }
        next if approval && authorized.include?(action) && !prohibited.include?(action)
        next if prohibited.include?(action) && !authorized.include?(action)

        errors << "#{path}: default high-risk action #{action} must remain prohibited unless explicitly approved"
      end

      unless handoff["recipient"] == "coding_agent"
        errors << "#{path}: handoff recipient must match the coding_agent execution contract"
      end

      blockers = handoff_blockers(document)
      if handoff["ready"] == true && !blockers.empty?
        errors << "#{path}: handoff.ready cannot be true (#{blockers.join("; ")})"
      end
    end

    def validate_approval_action(approval, authorized, prohibited, path)
      action = approval["action"]
      case approval["status"]
      when "approved"
        unless authorized.include?(action) && !prohibited.include?(action)
          errors << "#{path}: approved action #{action} must be authorized and not prohibited"
        end
      when "required", "rejected"
        unless prohibited.include?(action) && !authorized.include?(action)
          errors << "#{path}: #{approval["status"]} action #{action} must remain prohibited"
        end
      when "not_applicable"
        if authorized.include?(action) || prohibited.include?(action)
          errors << "#{path}: not_applicable action #{action} must not appear in Handoff action lists"
        end
      end
    end

    def handoff_blockers(document)
      blockers = []
      knowledge = document["knowledge"].is_a?(Hash) ? document["knowledge"] : {}
      unknowns = array_of_hashes(knowledge["unknowns"])
      blockers << "blocking unknown remains" if unknowns.any? { |unknown| unknown["blocking"] == true }
      findings = array_of_hashes(document["review_findings"])
      blockers << "Review Lens block remains" if findings.any? { |finding| finding["verdict"] == "block" }
      blockers
    end

    def validate_reference(reference, index, kind, path)
      errors << "#{path}: unresolved #{kind} reference #{reference}" unless index.key?(reference)
    end

    def index_by(entries, field)
      array_of_hashes(entries).each_with_object({}) do |entry, index|
        index[entry[field]] = entry if entry[field]
      end
    end

    def array_of_hashes(value)
      value.is_a?(Array) ? value.select { |entry| entry.is_a?(Hash) } : []
    end

    def hash_values(value)
      value.is_a?(Hash) ? value.values : []
    end

    def duplicate_values(values)
      values.group_by { |value| value }.select { |_value, group| group.length > 1 }.keys
    end

    def present?(value)
      value.is_a?(String) && !value.empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  parser = OptionParser.new do |config|
    config.banner = "Usage: ruby scripts/validate_prompt_package.rb PACKAGE.yaml"
  end

  begin
    parser.parse!
    raise OptionParser::MissingArgument, "provide exactly one Prompt Package path" unless ARGV.length == 1

    project_root = File.expand_path("..", __dir__)
    validator = PMind::PromptPackageValidator.new(project_root)
    if validator.validate_file(ARGV.fetch(0))
      ready = validator.package.dig("handoff", "ready")
      puts "PMIND_PROMPT_PACKAGE_VALIDATION_PASS path=#{File.expand_path(ARGV.fetch(0))} ready=#{ready}"
      exit 0
    end

    warn validator.errors.join("\n")
    exit 1
  rescue OptionParser::ParseError => e
    warn "PMIND_PROMPT_PACKAGE_VALIDATION_ERROR #{e.message}"
    warn parser
    exit 1
  end
end
