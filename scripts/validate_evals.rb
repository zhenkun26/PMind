#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "time"
require "yaml"

module PMind
  class EvalValidator
    CASE_SCHEMA = "evals/schema/case-v0.yaml"
    CALIBRATION_SCHEMA = "evals/schema/calibration-wave-v0.yaml"
    GAP_DIMENSIONS = %w[
      outcome
      user_scenario
      scope
      current_state
      constraints
      evidence
      acceptance
      risk_authority
      handoff
    ].freeze

    attr_reader :errors, :summary

    def initialize(root)
      @root = File.expand_path(root)
      @errors = []
      @summary = {}
    end

    def validate_repository
      errors.clear

      case_schema = load_yaml(CASE_SCHEMA)
      calibration_schema = load_yaml(CALIBRATION_SCHEMA)
      return false unless case_schema && calibration_schema

      case_entries = yaml_entries("evals/cases/seed/*.yaml")
      calibration_entries = yaml_entries("evals/calibration/*.yaml")

      case_entries.each do |path, document|
        validate_document(case_schema, document, relative(path), case_schema)
      end
      validate_case_set(case_entries)

      case_ids = case_entries.map { |_path, document| document["case_id"] }.compact
      calibration_entries.each do |path, document|
        validate_document(calibration_schema, document, relative(path), calibration_schema)
        validate_calibration(document, case_ids, relative(path))
      end

      dimensions = case_entries.flat_map do |_path, document|
        document.dig("coverage", "gap_dimensions") || []
      end.uniq
      risks = case_entries.flat_map do |_path, document|
        document.dig("coverage", "risk_tags") || []
      end.uniq

      @summary = {
        "cases" => case_entries.length,
        "calibration_waves" => calibration_entries.length,
        "gap_dimensions" => dimensions.length,
        "risk_tags" => risks.length
      }
      errors.empty?
    end

    def load_yaml(path)
      absolute = File.expand_path(path, @root)
      YAML.safe_load(
        File.read(absolute),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT => e
      errors << "#{path}: missing file (#{e.message})"
      nil
    rescue Psych::Exception => e
      errors << "#{path}: invalid YAML (#{e.message})"
      nil
    end

    def validate_document(schema, data, path, root_schema = schema)
      validate_node(schema, data, path, root_schema)
      errors.empty?
    end

    def validate_case_set(entries)
      errors << "seed cases: expected 10, got #{entries.length}" unless entries.length == 10

      ids = entries.map { |_path, document| document["case_id"] }.compact
      duplicate_values(ids).each { |id| errors << "seed cases: duplicate case_id #{id}" }

      all_dimensions = []
      entries.each do |path, document|
        label = relative(path)
        case_id = document["case_id"]
        if case_id && !File.basename(path).start_with?(case_id)
          errors << "#{label}: filename must start with #{case_id}"
        end

        if document.dig("data_policy", "contains_secrets") != false
          errors << "#{label}: contains_secrets must remain false"
        end

        dimensions = document.dig("coverage", "gap_dimensions") || []
        all_dimensions.concat(dimensions)
        (document.dig("oracle", "material_unknowns") || []).each do |unknown|
          dimension = unknown["dimension"]
          unless dimensions.include?(dimension)
            errors << "#{label}: material unknown dimension #{dimension} is not declared in coverage"
          end
        end

        criteria_ids = (document.dig("oracle", "acceptance_criteria") || []).map do |criterion|
          criterion["criterion_id"]
        end.compact
        duplicate_values(criteria_ids).each do |criterion_id|
          errors << "#{label}: duplicate acceptance criterion #{criterion_id}"
        end

        run_ids = (document["run_records"] || []).map { |run| run["run_id"] }.compact
        duplicate_values(run_ids).each { |run_id| errors << "#{label}: duplicate run_id #{run_id}" }
        (document["run_records"] || []).each do |run|
          validate_run_consistency(run, label)
        end
      end

      (GAP_DIMENSIONS - all_dimensions.uniq).each do |dimension|
        errors << "seed cases: missing gap dimension #{dimension}"
      end
      errors.empty?
    end

    def validate_calibration(manifest, case_ids, path)
      selected = (manifest["cases"] || []).map { |entry| entry["case_id"] }.compact
      duplicate_values(selected).each { |case_id| errors << "#{path}: duplicate case #{case_id}" }
      (selected - case_ids).each { |case_id| errors << "#{path}: unknown case #{case_id}" }

      orders = (manifest["cases"] || []).map { |entry| entry["arm_order"] }
      baseline_first = orders.count("baseline_then_pmind")
      pmind_first = orders.count("pmind_then_baseline")
      if (baseline_first - pmind_first).abs > 1
        errors << "#{path}: arm order must be balanced within one case"
      end

      if manifest["can_start"]
        validate_ready_calibration(manifest, path)
      else
        unless %w[blocked invalid].include?(manifest["status"])
          errors << "#{path}: can_start false requires blocked or invalid status"
        end
        if (manifest["blocked_reasons"] || []).empty?
          errors << "#{path}: blocked wave must explain at least one reason"
        end
      end
      errors.empty?
    end

    private

    def yaml_entries(pattern)
      Dir[File.join(@root, pattern)].sort.each_with_object([]) do |path, entries|
        document = load_yaml(relative(path))
        entries << [path, document] if document
      end
    end

    def validate_node(schema, data, path, root_schema)
      if schema["$ref"]
        resolved = resolve_ref(root_schema, schema["$ref"], path)
        validate_node(resolved, data, path, root_schema) if resolved
        return
      end

      if schema.key?("const") && data != schema["const"]
        errors << "#{path}: expected constant #{schema["const"].inspect}"
      end
      if schema["enum"] && !schema["enum"].include?(data)
        errors << "#{path}: value #{data.inspect} is outside enum"
      end

      type = schema["type"]
      unless type_matches?(type, data)
        errors << "#{path}: expected #{type}, got #{data.class}"
        return
      end

      validate_object(schema, data, path, root_schema) if data.is_a?(Hash)
      validate_array(schema, data, path, root_schema) if data.is_a?(Array)
      validate_number(schema, data, path) if data.is_a?(Numeric)
      validate_string(schema, data, path) if data.is_a?(String)
    end

    def validate_object(schema, data, path, root_schema)
      Array(schema["required"]).each do |key|
        errors << "#{path}: missing required field #{key}" unless data.key?(key)
      end

      properties = schema["properties"] || {}
      if schema["additionalProperties"] == false
        (data.keys - properties.keys).each { |key| errors << "#{path}: unexpected field #{key}" }
      end
      properties.each do |key, child_schema|
        validate_node(child_schema, data[key], "#{path}.#{key}", root_schema) if data.key?(key)
      end
    end

    def validate_array(schema, data, path, root_schema)
      if schema["minItems"] && data.length < schema["minItems"]
        errors << "#{path}: requires at least #{schema["minItems"]} items"
      end
      if schema["maxItems"] && data.length > schema["maxItems"]
        errors << "#{path}: allows at most #{schema["maxItems"]} items"
      end
      if schema["uniqueItems"] && data.uniq.length != data.length
        errors << "#{path}: items must be unique"
      end
      return unless schema["items"]

      data.each_with_index do |item, index|
        validate_node(schema["items"], item, "#{path}[#{index}]", root_schema)
      end
    end

    def validate_number(schema, data, path)
      if schema["minimum"] && data < schema["minimum"]
        errors << "#{path}: must be >= #{schema["minimum"]}"
      end
    end

    def validate_string(schema, data, path)
      if schema["minLength"] && data.length < schema["minLength"]
        errors << "#{path}: must contain at least #{schema["minLength"]} characters"
      end
      if schema["pattern"] && !(Regexp.new(schema["pattern"]) =~ data)
        errors << "#{path}: does not match #{schema["pattern"]}"
      end
      validate_format(schema["format"], data, path) if schema["format"]
    rescue RegexpError => e
      errors << "#{path}: schema has invalid pattern (#{e.message})"
    end

    def validate_format(format, data, path)
      Date.iso8601(data) if format == "date"
      Time.iso8601(data) if format == "date-time"
    rescue ArgumentError
      errors << "#{path}: invalid #{format} value"
    end

    def validate_run_consistency(run, path)
      cost = run["estimated_cost"] || {}
      case cost["status"]
      when "known"
        if %w[unknown not_applicable].include?(cost["amount_decimal"]) || cost["currency"] == "not_applicable"
          errors << "#{path}: known cost requires decimal amount and real currency"
        end
      when "unknown"
        errors << "#{path}: unknown cost must use amount_decimal unknown" unless cost["amount_decimal"] == "unknown"
      when "not_applicable"
        unless cost["amount_decimal"] == "not_applicable" && cost["currency"] == "not_applicable"
          errors << "#{path}: not_applicable cost must use not_applicable amount and currency"
        end
      end

      outcome = run["outcome"]
      failure = run["failure_classification"]
      errors << "#{path}: pass outcome requires failure none" if outcome == "pass" && failure != "none"
      if outcome == "fail" && %w[none not_scored].include?(failure)
        errors << "#{path}: fail outcome requires a concrete failure classification"
      end
      errors << "#{path}: not_scored outcome requires matching failure" if outcome == "not_scored" && failure != "not_scored"
    end

    def validate_ready_calibration(manifest, path)
      unless %w[ready in_progress].include?(manifest["status"])
        errors << "#{path}: can_start true requires ready or in_progress status"
      end
      errors << "#{path}: ready wave cannot retain blocked reasons" unless (manifest["blocked_reasons"] || []).empty?

      (manifest["roles"] || {}).each do |role, assignment|
        unless assignment["status"] == "assigned" && present?(assignment["assignee_ref"])
          errors << "#{path}: role #{role} must be assigned with assignee_ref"
        end
      end

      executor = manifest["executor_config"] || {}
      errors << "#{path}: executor configuration must be frozen" unless executor["status"] == "frozen"
      %w[executor_type model_version reasoning_settings tool_policy time_limit_minutes].each do |field|
        errors << "#{path}: frozen executor missing #{field}" unless present?(executor[field])
      end

      (manifest["cases"] || []).each do |entry|
        fixture = entry["fixture"] || {}
        unless fixture["status"] == "ready" && present?(fixture["workspace_base_revision"])
          errors << "#{path}: #{entry["case_id"]} fixture must be ready with base revision"
        end
      end
      (manifest["start_gates"] || {}).each do |gate, passed|
        errors << "#{path}: start gate #{gate} is not satisfied" unless passed == true
      end
    end

    def resolve_ref(root_schema, reference, path)
      unless reference.start_with?("#/")
        errors << "#{path}: only local schema refs are supported"
        return nil
      end

      reference.delete_prefix("#/").split("/").reduce(root_schema) do |node, segment|
        node.fetch(segment.gsub("~1", "/").gsub("~0", "~"))
      end
    rescue KeyError
      errors << "#{path}: unresolved schema ref #{reference}"
      nil
    end

    def type_matches?(type, data)
      case type
      when nil then true
      when "object" then data.is_a?(Hash)
      when "array" then data.is_a?(Array)
      when "string" then data.is_a?(String)
      when "boolean" then data == true || data == false
      when "integer" then data.is_a?(Integer)
      when "number" then data.is_a?(Numeric)
      else false
      end
    end

    def duplicate_values(values)
      values.group_by { |value| value }.select { |_value, group| group.length > 1 }.keys
    end

    def present?(value)
      !value.nil? && (!value.respond_to?(:empty?) || !value.empty?)
    end

    def relative(path)
      path.delete_prefix("#{@root}/")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  project_root = File.expand_path("..", __dir__)
  validator = PMind::EvalValidator.new(project_root)
  if validator.validate_repository
    summary = validator.summary.map { |key, value| "#{key}=#{value}" }.join(" ")
    puts "PMIND_EVAL_VALIDATION_PASS #{summary}"
    exit 0
  end

  warn validator.errors.join("\n")
  exit 1
end
