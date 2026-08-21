#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "prepare_calibration_workspaces"

module PMind
  class CalibrationPreflight
    Result = Struct.new(:status, :gates, :blockers, keyword_init: true)
    WAVE_MANIFEST = "evals/calibration/wave-01.yaml"

    class PreflightError < StandardError; end

    def initialize(root)
      @root = File.realpath(root)
    end

    def run(workspace_set: nil)
      validator = EvalValidator.new(@root)
      unless validator.validate_repository
        raise PreflightError, "repository validation failed:\n#{validator.errors.join("\n")}"
      end

      wave = validator.load_yaml(WAVE_MANIFEST)
      profile_path = wave.dig("executor_config", "profile_path")
      profile = validator.load_yaml(profile_path)
      workspace_ready, workspace_blocker = workspace_evidence(workspace_set)
      gates = {
        "contracts_valid" => true,
        "rubric_frozen" => true,
        "roles_assigned" => validator.roles_ready?(wave["roles"]),
        "fixtures_ready" => fixtures_ready?(wave),
        "executor_frozen" => validator.executor_profile_ready?(profile),
        "isolated_workspaces_ready" => workspace_ready
      }

      blockers = []
      unless gates["roles_assigned"]
        roles = wave.fetch("roles").select { |_role, assignment| assignment["status"] != "assigned" }.keys
        blockers << "roles unassigned: #{roles.join(", ")}"
      end
      unless gates["executor_frozen"]
        blockers << "executor profile unresolved: #{profile.fetch("unresolved_fields").join(", ")}"
      end
      blockers << workspace_blocker if workspace_blocker

      mismatched_gates = gates.keys.select { |gate| wave.dig("start_gates", gate) != gates[gate] }
      unless mismatched_gates.empty?
        blockers << "Wave start_gates do not match preflight evidence: #{mismatched_gates.join(", ")}"
      end

      if gates.values.all?
        unless wave["can_start"] && wave["status"] == "ready" && wave.fetch("blocked_reasons").empty?
          blockers << "Wave status, can_start, and blocked_reasons are not reconciled for execution"
        end
      end

      Result.new(
        status: blockers.empty? ? "ready" : "blocked",
        gates: gates.freeze,
        blockers: blockers.freeze
      )
    end

    private

    def fixtures_ready?(wave)
      wave.fetch("cases").all? do |entry|
        fixture = entry.fetch("fixture")
        fixture["status"] == "ready" && !fixture["workspace_base_revision"].to_s.empty?
      end
    end

    def workspace_evidence(path)
      return [false, "isolated workspace set was not supplied"] if path.nil?

      CalibrationWorkspacePreparer.new(@root).verify(path)
      [true, nil]
    rescue CalibrationWorkspacePreparer::PreparationError => e
      [false, "isolated workspace set is invalid: #{e.message.lines.first.strip}"]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  parser = OptionParser.new do |config|
    config.banner = "Usage: ruby scripts/calibration_preflight.rb [--workspace-set ABSOLUTE_PATH]"
    config.on("--workspace-set PATH", "Verify a prepared external workspace set") do |path|
      options[:workspace_set] = path
    end
  end

  begin
    parser.parse!
    project_root = File.expand_path("..", __dir__)
    result = PMind::CalibrationPreflight.new(project_root).run(workspace_set: options[:workspace_set])
    result.gates.each { |gate, passed| puts "GATE #{gate}=#{passed}" }
    result.blockers.each { |blocker| puts "BLOCKER #{blocker}" }
    puts "PMIND_CALIBRATION_PREFLIGHT_#{result.status.upcase} gates=#{result.gates.values.count(true)}/#{result.gates.length}"
    exit(result.status == "ready" ? 0 : 2)
  rescue OptionParser::ParseError, PMind::CalibrationPreflight::PreflightError => e
    warn "PMIND_CALIBRATION_PREFLIGHT_ERROR #{e.message}"
    warn parser
    exit 1
  end
end
