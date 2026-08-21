#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "time"
require "yaml"
require_relative "workspace_tree"

module PMind
  class EvalValidator
    CASE_SCHEMA = "evals/schema/case-v0.yaml"
    CALIBRATION_SCHEMA = "evals/schema/calibration-wave-v0.yaml"
    EXECUTOR_PROFILE_SCHEMA = "evals/schema/executor-profile-v0.yaml"
    FIXTURE_SCHEMA = "evals/schema/fixture-v0.yaml"
    EXECUTOR_DECISION_FIELDS = %w[
      executor_type
      executor_version
      model_version
      reasoning_settings
      tool_policy
      time_limit_minutes
      max_attempts
    ].freeze
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
      executor_profile_schema = load_yaml(EXECUTOR_PROFILE_SCHEMA)
      fixture_schema = load_yaml(FIXTURE_SCHEMA)
      return false unless case_schema && calibration_schema && executor_profile_schema && fixture_schema

      case_entries = yaml_entries("evals/cases/seed/*.yaml")
      calibration_entries = yaml_entries("evals/calibration/*.yaml")
      executor_profile_entries = yaml_entries("evals/calibration/executor-profiles/*.yaml")
      fixture_entries = yaml_entries("evals/fixtures/*/fixture.yaml")

      case_entries.each do |path, document|
        validate_document(case_schema, document, relative(path), case_schema)
      end
      validate_case_set(case_entries)

      case_ids = case_entries.map { |_path, document| document["case_id"] }.compact
      fixture_entries.each do |path, document|
        validate_document(fixture_schema, document, relative(path), fixture_schema)
        validate_fixture(document, relative(path))
      end
      validate_fixture_set(fixture_entries, case_ids)
      fixtures_by_case = fixture_entries.each_with_object({}) do |(_path, document), output|
        output[document["case_id"]] = document if document["case_id"]
      end

      executor_profile_entries.each do |path, document|
        validate_document(executor_profile_schema, document, relative(path), executor_profile_schema)
        validate_executor_profile(document, relative(path))
      end
      validate_executor_profile_set(executor_profile_entries)
      profiles_by_wave = executor_profile_entries.each_with_object({}) do |(path, document), output|
        output[document["wave_id"]] = [document, relative(path)] if document["wave_id"]
      end

      calibration_entries.each do |path, document|
        validate_document(calibration_schema, document, relative(path), calibration_schema)
        profile, profile_path = profiles_by_wave[document["wave_id"]]
        validate_calibration(
          document,
          case_ids,
          relative(path),
          fixtures_by_case,
          profile,
          profile_path
        )
      end

      dimensions = case_entries.flat_map do |_path, document|
        document.dig("coverage", "gap_dimensions") || []
      end.uniq
      risks = case_entries.flat_map do |_path, document|
        document.dig("coverage", "risk_tags") || []
      end.uniq

      @summary = {
        "cases" => case_entries.length,
        "fixtures" => fixture_entries.length,
        "executor_profiles" => executor_profile_entries.length,
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

    def validate_fixture_set(entries, case_ids)
      errors << "fixtures: expected 3, got #{entries.length}" unless entries.length == 3

      fixture_ids = entries.map { |_path, document| document["fixture_id"] }.compact
      case_fixture_ids = entries.map { |_path, document| document["case_id"] }.compact
      duplicate_values(fixture_ids).each { |fixture_id| errors << "fixtures: duplicate fixture_id #{fixture_id}" }
      duplicate_values(case_fixture_ids).each { |case_id| errors << "fixtures: duplicate case_id #{case_id}" }
      (case_fixture_ids - case_ids).each { |case_id| errors << "fixtures: unknown case_id #{case_id}" }
      errors.empty?
    end

    def validate_executor_profile_set(entries)
      errors << "executor profiles: expected 1, got #{entries.length}" unless entries.length == 1

      profile_ids = entries.map { |_path, document| document["profile_id"] }.compact
      wave_ids = entries.map { |_path, document| document["wave_id"] }.compact
      duplicate_values(profile_ids).each { |id| errors << "executor profiles: duplicate profile_id #{id}" }
      duplicate_values(wave_ids).each { |id| errors << "executor profiles: duplicate wave_id #{id}" }
      errors.empty?
    end

    def validate_executor_profile(profile, path)
      wave_id = profile["wave_id"]
      expected_path = "evals/calibration/executor-profiles/#{wave_id}.yaml"
      unless path == expected_path && profile["profile_id"] == "executor-#{wave_id}"
        errors << "#{path}: profile path and profile_id must match wave_id"
      end

      missing = EXECUTOR_DECISION_FIELDS.reject { |field| profile.key?(field) }
      unresolved = profile["unresolved_fields"] || []
      unless unresolved.sort == missing.sort
        errors << "#{path}: unresolved_fields must exactly match missing executor decisions"
      end

      if profile["status"] == "frozen" && !unresolved.empty?
        errors << "#{path}: frozen profile cannot retain unresolved fields"
      elsif profile["status"] == "draft" && unresolved.empty?
        errors << "#{path}: draft profile must retain at least one unresolved field"
      end
      errors.empty?
    end

    def executor_profile_ready?(profile)
      profile && profile["status"] == "frozen" && (profile["unresolved_fields"] || []).empty?
    end

    def roles_ready?(roles)
      assignments = (roles || {}).values
      refs = assignments.map { |assignment| assignment["assignee_ref"] }
      assignments.length == 4 &&
        assignments.all? { |assignment| assignment["status"] == "assigned" && present?(assignment["assignee_ref"]) } &&
        refs.uniq.length == 4
    end

    def validate_fixture(fixture, path)
      case_id = fixture["case_id"]
      fixture_root = "evals/fixtures/#{case_id}"
      unless fixture["fixture_id"] == "fixture-#{case_id}"
        errors << "#{path}: fixture_id must match case_id"
      end
      unless path == "#{fixture_root}/fixture.yaml"
        errors << "#{path}: fixture manifest path must match case_id"
      end
      unless fixture.dig("paths", "workspace") == "#{fixture_root}/workspace" &&
             fixture.dig("paths", "oracle") == "#{fixture_root}/oracle"
        errors << "#{path}: workspace and oracle paths must match case_id"
      end

      workspace = safe_repo_path(fixture.dig("paths", "workspace"), path)
      oracle = safe_repo_path(fixture.dig("paths", "oracle"), path)
      return false unless workspace && oracle

      errors << "#{path}: workspace directory is missing" unless File.directory?(workspace)
      errors << "#{path}: oracle directory is missing" unless File.directory?(oracle)
      return false unless File.directory?(workspace) && File.directory?(oracle)

      if nested_path?(workspace, oracle) || nested_path?(oracle, workspace)
        errors << "#{path}: workspace and oracle must be disjoint"
      end
      workspace_files = safe_tree_files(workspace, path)
      oracle_files = safe_tree_files(oracle, path)
      return false unless workspace_files && oracle_files

      validate_artifact_inventory(
        fixture["workspace_artifacts"] || [],
        workspace_files.map { |file| relative(file) },
        workspace,
        "workspace",
        path
      )
      validate_artifact_inventory(
        fixture["oracle_artifacts"] || [],
        oracle_files.map { |file| relative(file) },
        oracle,
        "oracle",
        path
      )

      digest = workspace_digest(fixture.dig("paths", "workspace"))
      unless digest == fixture.dig("workspace_revision", "digest")
        errors << "#{path}: workspace digest mismatch, actual #{digest}"
      end

      unless fixture["executor_excludes"] == [fixture.dig("paths", "oracle")]
        errors << "#{path}: executor_excludes must contain only the oracle directory"
      end
      validate_fixture_checks(fixture, path)
      errors.empty?
    end

    def workspace_digest(relative_workspace)
      workspace = safe_repo_path(relative_workspace, "workspace digest")
      return nil unless workspace && File.directory?(workspace)

      WorkspaceTree.digest(workspace)
    rescue WorkspaceTree::UnsafeTreeError => e
      errors << "workspace digest: #{e.message}"
      nil
    end

    def validate_calibration(
      manifest,
      case_ids,
      path,
      fixtures_by_case = {},
      executor_profile = nil,
      executor_profile_path = nil
    )
      selected = (manifest["cases"] || []).map { |entry| entry["case_id"] }.compact
      duplicate_values(selected).each { |case_id| errors << "#{path}: duplicate case #{case_id}" }
      (selected - case_ids).each { |case_id| errors << "#{path}: unknown case #{case_id}" }

      orders = (manifest["cases"] || []).map { |entry| entry["arm_order"] }
      baseline_first = orders.count("baseline_then_pmind")
      pmind_first = orders.count("pmind_then_baseline")
      if (baseline_first - pmind_first).abs > 1
        errors << "#{path}: arm order must be balanced within one case"
      end

      unless fixtures_by_case.empty?
        fixtures_ready = (manifest["cases"] || []).all? do |entry|
          fixture = fixtures_by_case[entry["case_id"]]
          fixture &&
            fixture["status"] == "ready" &&
            entry.dig("fixture", "status") == "ready" &&
            entry.dig("fixture", "workspace_base_revision") == fixture.dig("workspace_revision", "digest")
        end
        if manifest.dig("start_gates", "fixtures_ready") != fixtures_ready
          errors << "#{path}: fixtures_ready gate does not match fixture manifests"
        end
      end

      validate_executor_gate(manifest, executor_profile, executor_profile_path, path)
      validate_role_gate(manifest, path)

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

    def validate_executor_gate(manifest, profile, profile_path, path)
      config = manifest["executor_config"] || {}
      if profile.nil?
        if present?(config["profile_path"]) || manifest.dig("start_gates", "executor_frozen")
          errors << "#{path}: executor profile is missing from validation context"
        end
        return
      end

      unless config["profile_path"] == profile_path && profile["wave_id"] == manifest["wave_id"]
        errors << "#{path}: executor profile path and wave_id must match the Wave"
      end

      frozen = executor_profile_ready?(profile)
      expected_status = frozen ? "frozen" : "unfrozen"
      unless config["status"] == expected_status
        errors << "#{path}: executor configuration status does not match its profile"
      end
      unless manifest.dig("start_gates", "executor_frozen") == frozen
        errors << "#{path}: executor_frozen gate does not match its profile"
      end

      if frozen
        expected_revision = Digest::SHA256.file(File.expand_path(profile_path, @root)).hexdigest
        unless config["profile_revision"] == expected_revision
          errors << "#{path}: frozen executor profile revision is missing or stale"
        end
      elsif config.key?("profile_revision")
        errors << "#{path}: draft executor profile must not have a frozen revision"
      end
    end

    def validate_role_gate(manifest, path)
      assignments = (manifest["roles"] || {}).values
      assigned_refs = assignments.each_with_object([]) do |assignment, refs|
        if assignment["status"] == "assigned" && present?(assignment["assignee_ref"])
          refs << assignment["assignee_ref"]
        end
      end
      duplicate_values(assigned_refs).each do |assignee_ref|
        errors << "#{path}: assignee_ref #{assignee_ref} cannot hold multiple calibration roles"
      end

      roles_assigned = roles_ready?(manifest["roles"])
      unless manifest.dig("start_gates", "roles_assigned") == roles_assigned
        errors << "#{path}: roles_assigned gate does not match distinct role assignments"
      end
    end

    def validate_artifact_inventory(declared, actual, expected_root, kind, path)
      declared.each do |artifact|
        absolute = safe_repo_path(artifact, path)
        next unless absolute

        unless nested_path?(absolute, expected_root) && File.file?(absolute)
          errors << "#{path}: #{kind} artifact is missing or outside #{kind} (#{artifact})"
        end
      end
      (actual.sort - declared.sort).each { |artifact| errors << "#{path}: undeclared #{kind} artifact #{artifact}" }
      (declared.sort - actual.sort).each { |artifact| errors << "#{path}: missing declared #{kind} artifact #{artifact}" }
    end

    def validate_fixture_checks(fixture, path)
      checks = fixture["checks"] || {}
      (checks["base"] || []).each do |check|
        errors << "#{path}: base check must expect pass" unless check["pre_implementation_expectation"] == "pass"
        validate_check_command(check, path)
      end
      (checks["acceptance"] || []).each do |check|
        if check["pre_implementation_expectation"] == "pass"
          errors << "#{path}: acceptance check cannot pass before implementation"
        end
        validate_check_command(check, path)
      end
    end

    def validate_check_command(check, path)
      artifact = safe_repo_path(check["artifact"], path)
      errors << "#{path}: check artifact is missing #{check["artifact"]}" unless artifact && File.file?(artifact)

      command = check["command"]
      if check["mode"] == "ruby_test"
        unless command == ["ruby", check["artifact"]]
          errors << "#{path}: ruby_test command must exactly invoke its declared artifact"
        end
      elsif command
        errors << "#{path}: manual_review check must not declare a command"
      end
    end

    def safe_repo_path(path, context)
      unless path.is_a?(String) && !path.empty?
        errors << "#{context}: repository path is missing"
        return nil
      end

      absolute = File.expand_path(path, @root)
      unless absolute == @root || absolute.start_with?("#{@root}/")
        errors << "#{context}: path escapes repository (#{path})"
        return nil
      end
      absolute
    end

    def nested_path?(candidate, root)
      candidate == root || candidate.start_with?("#{root}/")
    end

    def safe_tree_files(root, path)
      WorkspaceTree.files(root)
    rescue WorkspaceTree::UnsafeTreeError => e
      errors << "#{path}: #{e.message}"
      nil
    end

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
      errors << "#{path}: frozen executor missing profile_path" unless present?(executor["profile_path"])
      errors << "#{path}: frozen executor missing profile_revision" unless present?(executor["profile_revision"])

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
