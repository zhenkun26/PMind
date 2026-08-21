#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "optparse"
require "time"
require "yaml"
require_relative "validate_prompt_package"

module PMind
  class ClarificationSessionValidator
    SCHEMA_PATH = "schemas/clarification-session-v0.yaml"
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
    CRITICAL_GAPS = %w[outcome scope acceptance risk_authority handoff].freeze
    TIE_PRIORITY = {
      "risk_authority" => 0,
      "outcome" => 1,
      "scope" => 2,
      "acceptance" => 3
    }.freeze

    attr_reader :errors, :session, :prompt_package

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @session = nil
      @prompt_package = nil
    end

    def validate_file(path)
      errors.clear
      @session = nil
      @prompt_package = nil
      document = load_yaml_file(path)
      return false unless document

      validate(document, path)
    end

    def validate_pair_files(session_path, package_path)
      errors.clear
      @session = nil
      @prompt_package = nil
      session_document = load_yaml_file(session_path)
      package_document = load_yaml_file(package_path)
      return false unless session_document && package_document

      validate_pair(session_document, package_document, session_path, package_path)
    end

    def validate(document, path = "clarification-session")
      errors.clear
      @session = document
      @prompt_package = nil
      schema_validator = EvalValidator.new(@root)
      schema = schema_validator.load_yaml(SCHEMA_PATH)
      unless schema
        errors.concat(schema_validator.errors)
        return false
      end

      schema_validator.validate_document(schema, document, path, schema)
      errors.concat(schema_validator.errors)
      return false unless document.is_a?(Hash)

      validate_intake(document, path)
      validate_identifiers(document, path)
      validate_gap_map(document, path)
      validate_rounds(document, path)
      validate_revision(document, path)
      validate_question_priority(document, path)
      validate_compile_gate(document, path)
      validate_state(document, path)
      errors.empty?
    end

    def validate_pair(session_document, package_document, session_path = "clarification-session", package_path = "prompt-package")
      session_valid = validate(session_document, session_path)
      package_validator = PromptPackageValidator.new(@root)
      package_valid = package_validator.validate(package_document, package_path)
      errors.concat(package_validator.errors)
      @prompt_package = package_document
      return false unless session_valid && package_valid

      validate_lineage(session_document, package_document, package_path)
      errors.empty?
    end

    private

    def load_yaml_file(path)
      absolute = File.expand_path(path)
      YAML.safe_load(
        File.read(absolute),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      nil
    end

    def validate_intake(document, path)
      intake = hash_value(document["intake"])
      raw_intent = intake["raw_intent"]
      if raw_intent.is_a?(String)
        digest = Digest::SHA256.hexdigest(raw_intent)
        unless intake["raw_intent_sha256"] == digest
          errors << "#{path}: raw_intent_sha256 does not match the immutable raw_intent"
        end
      end
      if intake["contains_personal_data"] == true && intake["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def validate_identifiers(document, path)
      groups = {
        "question_id" => document["questions"],
        "assumption_id" => document["assumptions"],
        "unknown_id" => document["unknowns"],
        "decision_id" => document["decisions"]
      }
      groups.each do |field, entries|
        ids = array_of_hashes(entries).map { |entry| entry[field] }.compact
        duplicate_values(ids).each { |id| errors << "#{path}: duplicate #{field} #{id}" }
      end

      round_numbers = array_of_hashes(document["rounds"]).map { |round| round["round_number"] }.compact
      duplicate_values(round_numbers).each { |number| errors << "#{path}: duplicate round_number #{number}" }
      gap_dimensions = array_of_hashes(document["gaps"]).map { |gap| gap["dimension"] }.compact
      duplicate_values(gap_dimensions).each { |dimension| errors << "#{path}: duplicate Gap dimension #{dimension}" }
      actions = array_of_hashes(document.dig("compile_gate", "high_risk_actions")).map { |entry| entry["action"] }.compact
      duplicate_values(actions).each { |action| errors << "#{path}: duplicate high-risk action #{action}" }
    rescue TypeError
      # Structural errors are already reported by Schema validation.
    end

    def validate_gap_map(document, path)
      gaps = array_of_hashes(document["gaps"])
      unless document["status"] == "intake"
        present_dimensions = gaps.map { |gap| gap["dimension"] }.compact.uniq
        (GAP_DIMENSIONS - present_dimensions).each do |dimension|
          errors << "#{path}: missing Gap dimension #{dimension}"
        end
      end

      assumptions = index_by(document["assumptions"], "assumption_id")
      unknowns = index_by(document["unknowns"], "unknown_id")
      questions = index_by(document["questions"], "question_id")
      decisions = index_by(document["decisions"], "decision_id")
      answers = array_of_hashes(document["rounds"]).flat_map { |round| array_of_hashes(round["answers"]) }
      answers_by_id = answers.each_with_object({}) { |answer, index| index[answer["question_id"]] = answer }
      gaps.each do |gap|
        validate_gap_sources(gap, questions, decisions, answers_by_id, path)
        validate_gap_state(gap, assumptions, unknowns, path)
      end
    end

    def validate_gap_sources(gap, questions, decisions, answers_by_id, path)
      Array(gap["source_refs"]).each do |source_ref|
        next if source_ref == "intake"
        next if decisions.key?(source_ref)
        if questions.key?(source_ref)
          answer = answers_by_id[source_ref]
          unless questions[source_ref]["status"] == "asked" && answer
            errors << "#{path}: Gap #{gap["dimension"]} cannot use unanswered question #{source_ref}"
          else
            validate_gap_answer_outcome(gap, answer, source_ref, path)
          end
          next
        end

        errors << "#{path}: Gap #{gap["dimension"]} has unresolved source_ref #{source_ref}"
      end
    end

    def validate_gap_answer_outcome(gap, answer, question_id, path)
      allowed = case gap["status"]
                when "resolved" then ["resolved"]
                when "assumed" then ["assumed"]
                when "unknown" then %w[unknown refused]
                else return
                end
      return if allowed.include?(answer["outcome_status"])

      errors << "#{path}: Gap #{gap["dimension"]} status contradicts answer outcome for #{question_id}"
    end

    def validate_gap_state(gap, assumptions, unknowns, path)
      dimension = gap["dimension"]
      knowledge_ref = gap["knowledge_ref"]
      not_applicable_reason = gap["not_applicable_reason"]
      source_refs = Array(gap["source_refs"])
      case gap["status"]
      when "resolved"
        errors << "#{path}: resolved Gap #{dimension} cannot remain blocking" if gap["blocking"] != false
        errors << "#{path}: resolved Gap #{dimension} requires a source_ref" if source_refs.empty?
        errors << "#{path}: resolved Gap #{dimension} cannot have knowledge_ref" if knowledge_ref
        errors << "#{path}: resolved Gap #{dimension} cannot have not_applicable_reason" if not_applicable_reason
      when "assumed"
        errors << "#{path}: assumed Gap #{dimension} cannot remain blocking" if gap["blocking"] != false
        unless knowledge_ref && assumptions.key?(knowledge_ref)
          errors << "#{path}: assumed Gap #{dimension} requires a matching ASSUMP knowledge_ref"
        end
        errors << "#{path}: assumed Gap #{dimension} cannot have not_applicable_reason" if not_applicable_reason
      when "unknown"
        unknown = unknowns[knowledge_ref]
        unless knowledge_ref && unknown
          errors << "#{path}: unknown Gap #{dimension} requires a matching UNKNOWN knowledge_ref"
        end
        if unknown && gap["blocking"] != unknown["blocking"]
          errors << "#{path}: unknown Gap #{dimension} blocking flag must match #{knowledge_ref}"
        end
        if CRITICAL_GAPS.include?(dimension) && gap["blocking"] != true
          errors << "#{path}: critical unknown Gap #{dimension} must remain blocking"
        end
        errors << "#{path}: unknown Gap #{dimension} cannot have not_applicable_reason" if not_applicable_reason
      when "not_applicable"
        errors << "#{path}: not_applicable Gap #{dimension} cannot remain blocking" if gap["blocking"] != false
        errors << "#{path}: not_applicable Gap #{dimension} requires a reason" unless present?(not_applicable_reason)
        errors << "#{path}: not_applicable Gap #{dimension} cannot have knowledge_ref" if knowledge_ref
      end
    end

    def validate_rounds(document, path)
      rounds = array_of_hashes(document["rounds"])
      questions = index_by(document["questions"], "question_id")
      expected_numbers = (1..rounds.length).to_a
      actual_numbers = rounds.map { |round| round["round_number"] }
      unless actual_numbers == expected_numbers
        errors << "#{path}: round numbers must be consecutive and ordered from 1"
      end

      answered = {}
      previous_time = parse_time(document["created_at"])
      rounds.each do |round|
        completed_at = parse_time(round["completed_at"])
        if completed_at && previous_time && completed_at < previous_time
          errors << "#{path}: round #{round["round_number"]} completed_at is out of order"
        end
        previous_time = completed_at if completed_at

        array_of_hashes(round["answers"]).each do |answer|
          question_id = answer["question_id"]
          if answered.key?(question_id)
            errors << "#{path}: question #{question_id} cannot be answered more than once"
            next
          end
          answered[question_id] = round["round_number"]
          question = questions[question_id]
          unless question
            errors << "#{path}: round #{round["round_number"]} references unknown question #{question_id}"
            next
          end
          unless question["status"] == "asked" && question["round_number"] == round["round_number"]
            errors << "#{path}: answered question #{question_id} must be marked asked in the same round"
          end
          unless answer["affected_fields"] == question["affected_fields"]
            errors << "#{path}: answer #{question_id} affected_fields must match its question"
          end
        end
      end

      questions.each_value do |question|
        question_id = question["question_id"]
        if question["status"] == "asked"
          errors << "#{path}: asked question #{question_id} requires exactly one answer" unless answered.key?(question_id)
        elsif question.key?("round_number") || answered.key?(question_id)
          errors << "#{path}: #{question["status"]} question #{question_id} cannot belong to a round"
        end
      end
      validate_round_extension(document, rounds.length, path)
    end

    def validate_round_extension(document, round_count, path)
      policy = hash_value(document["round_policy"])
      extended = policy["extension_authorized_by_user"] == true
      if round_count > 3 && (!extended || !present?(policy["extension_reason"]))
        errors << "#{path}: more than three rounds require user authorization and an extension reason"
      elsif !extended && policy.key?("extension_reason")
        errors << "#{path}: extension_reason requires extension_authorized_by_user"
      elsif extended && !present?(policy["extension_reason"])
        errors << "#{path}: authorized round extension requires extension_reason"
      end
    end

    def validate_revision(document, path)
      revision = document["revision"]
      return unless revision.is_a?(Hash)

      rounds = array_of_hashes(document["rounds"])
      unless revision["revision_number"] == rounds.length
        errors << "#{path}: revision_number must equal the completed round count #{rounds.length}"
      end
      unless %w[clarifying ready_to_compile blocked].include?(document["status"])
        errors << "#{path}: revision metadata requires a post-clarification Session state"
      end

      revision_time = parse_time(revision["created_at"])
      latest_round_time = rounds.map { |round| parse_time(round["completed_at"]) }.compact.max
      if revision_time && latest_round_time && revision_time < latest_round_time
        errors << "#{path}: revision created_at cannot predate its latest completed round"
      end
    end

    def validate_question_priority(document, path)
      questions = array_of_hashes(document["questions"])
      questions.each do |question|
        priority = hash_value(question["priority"])
        values = %w[materiality uncertainty answerability friction].map { |field| priority[field] }
        next unless values.all? { |value| value.is_a?(Integer) }

        expected = priority["materiality"] + priority["uncertainty"] + priority["answerability"] - priority["friction"]
        unless priority["score"] == expected
          errors << "#{path}: question #{question["question_id"]} priority score must equal #{expected}"
        end
      end

      gate = hash_value(document["compile_gate"])
      next_ids = Array(gate["next_question_ids"])
      pending = questions.select { |question| question["status"] == "pending" }
      pending_index = index_by(pending, "question_id")
      next_ids.each do |question_id|
        errors << "#{path}: next question #{question_id} must reference a pending question" unless pending_index.key?(question_id)
      end
      return if next_ids.empty?

      expected_order = pending.sort_by do |question|
        score = question.dig("priority", "score")
        [-score.to_i, TIE_PRIORITY.fetch(question["gap_dimension"], 4), question["question_id"].to_s]
      end.map { |question| question["question_id"] }
      unless next_ids == expected_order.first(next_ids.length)
        errors << "#{path}: next_question_ids must be the highest-priority pending prefix"
      end
    end

    def validate_compile_gate(document, path)
      gate = hash_value(document["compile_gate"])
      gaps = array_of_hashes(document["gaps"])
      unknowns = array_of_hashes(document["unknowns"])
      if gate["ready"] == true
        errors << "#{path}: compile gate cannot be ready while a blocking Gap remains" if gaps.any? { |gap| gap["blocking"] == true }
        errors << "#{path}: compile gate cannot be ready while a blocking unknown remains" if unknowns.any? { |unknown| unknown["blocking"] == true }
        errors << "#{path}: ready compile gate cannot retain blocking_reasons" unless Array(gate["blocking_reasons"]).empty?
        errors << "#{path}: ready compile gate cannot retain material_conflicts" unless Array(gate["material_conflicts"]).empty?
        errors << "#{path}: ready compile gate cannot retain next questions" unless Array(gate["next_question_ids"]).empty?
      end
    end

    def validate_state(document, path)
      status = document["status"]
      gaps = array_of_hashes(document["gaps"])
      questions = array_of_hashes(document["questions"])
      rounds = array_of_hashes(document["rounds"])
      gate = hash_value(document["compile_gate"])
      next_ids = Array(gate["next_question_ids"])

      case status
      when "intake"
        unless gaps.empty? && questions.empty? && rounds.empty? && gate["ready"] == false &&
               next_ids.empty? && gate["stop_reason"] == "not_stopped"
          errors << "#{path}: intake state allows only immutable Intake data"
        end
      when "gap_scan"
        unless complete_gap_map?(gaps) && rounds.empty? && gate["ready"] == false &&
               next_ids.length.between?(1, 3) && gate["stop_reason"] == "not_stopped"
          errors << "#{path}: gap_scan state requires a complete Gap Map and 1-3 next questions"
        end
      when "clarifying"
        unless complete_gap_map?(gaps) && !rounds.empty? && gate["ready"] == false &&
               next_ids.length.between?(1, 3) && gate["stop_reason"] == "not_stopped"
          errors << "#{path}: clarifying state requires completed rounds and 1-3 next questions"
        end
      when "ready_to_compile"
        allowed_stops = %w[sufficient_information user_requested_compile max_rounds_reached]
        unless complete_gap_map?(gaps) && gate["ready"] == true && next_ids.empty? && allowed_stops.include?(gate["stop_reason"])
          errors << "#{path}: ready_to_compile state does not match its compile gate"
        end
      when "blocked"
        blockers = Array(gate["blocking_reasons"])
        conflicts = Array(gate["material_conflicts"])
        unless complete_gap_map?(gaps) && gate["ready"] == false && next_ids.empty? &&
               gate["stop_reason"] == "blocked" && !(blockers.empty? && conflicts.empty?)
          errors << "#{path}: blocked state requires a recorded blocker or material conflict"
        end
      end
    end

    def validate_lineage(session_document, package_document, path)
      unless session_document["status"] == "ready_to_compile" && session_document.dig("compile_gate", "ready") == true
        errors << "#{path}: Prompt Package lineage requires a ready_to_compile Clarification Session"
        return
      end

      intake = session_document["intake"]
      unless package_document.dig("intent", "raw_intent") == intake["raw_intent"]
        errors << "#{path}: Prompt Package raw_intent must exactly match the Clarification Session"
      end
      unless package_document.dig("intent", "task_type") == intake["task_type"]
        errors << "#{path}: Prompt Package task_type must match the Clarification Session"
      end
      validate_lineage_time(session_document, package_document, path)
      validate_clarification_lineage(session_document, package_document, path)
      validate_knowledge_lineage(session_document, package_document, path)
      validate_risk_lineage(session_document, package_document, path)
    end

    def validate_lineage_time(session_document, package_document, path)
      session_time = parse_time(session_document["created_at"])
      package_time = parse_time(package_document["created_at"])
      if session_time && package_time && package_time < session_time
        errors << "#{path}: Prompt Package cannot predate its Clarification Session"
      end
    end

    def validate_clarification_lineage(session_document, package_document, path)
      questions = index_by(session_document["questions"], "question_id")
      answers = array_of_hashes(session_document["rounds"]).flat_map { |round| array_of_hashes(round["answers"]) }
      package_clarifications = index_by(package_document["clarifications"], "question_id")
      answer_ids = answers.map { |answer| answer["question_id"] }.sort
      unless package_clarifications.keys.sort == answer_ids
        errors << "#{path}: Prompt Package Clarifications must exactly match answered Session questions"
      end

      answers.each do |answer|
        question = questions[answer["question_id"]]
        compiled = package_clarifications[answer["question_id"]]
        next unless question && compiled

        expected_status = answer["outcome_status"] == "unknown" ? "unresolved" : answer["outcome_status"]
        expected = {
          "question" => question["question"],
          "user_answer" => answer["user_answer"],
          "outcome_status" => expected_status,
          "affected_fields" => answer["affected_fields"]
        }
        expected.each do |field, value|
          unless compiled[field] == value
            errors << "#{path}: Clarification #{answer["question_id"]} changed #{field} from its Session source"
          end
        end
      end
    end

    def validate_knowledge_lineage(session_document, package_document, path)
      package_knowledge = hash_value(package_document["knowledge"])
      {
        "assumptions" => "assumption_id",
        "unknowns" => "unknown_id",
        "decisions" => "decision_id"
      }.each do |collection, id_field|
        compiled = index_by(package_knowledge[collection], id_field)
        array_of_hashes(session_document[collection]).each do |source|
          unless compiled[source[id_field]] == source
            errors << "#{path}: #{collection} #{source[id_field]} must preserve its Session fields"
          end
        end
      end
    end

    def validate_risk_lineage(session_document, package_document, path)
      package_actions = array_of_hashes(package_document["approval_points"]).map { |approval| approval["action"] }.compact
      array_of_hashes(session_document.dig("compile_gate", "high_risk_actions")).each do |risk_action|
        unless package_actions.include?(risk_action["action"])
          errors << "#{path}: high-risk action #{risk_action["action"]} requires a Prompt Package Approval Point"
        end
      end
    rescue TypeError
      # Structural errors are already reported before lineage validation.
    end

    def complete_gap_map?(gaps)
      gaps.map { |gap| gap["dimension"] }.compact.uniq.sort == GAP_DIMENSIONS.sort
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end

    def index_by(entries, field)
      array_of_hashes(entries).each_with_object({}) do |entry, index|
        index[entry[field]] = entry if entry[field]
      end
    end

    def array_of_hashes(value)
      value.is_a?(Array) ? value.select { |entry| entry.is_a?(Hash) } : []
    end

    def hash_value(value)
      value.is_a?(Hash) ? value : {}
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
  options = {}
  parser = OptionParser.new do |config|
    config.banner = "Usage: ruby scripts/validate_clarification_session.rb SESSION.yaml [--prompt-package PACKAGE.yaml]"
    config.on("--prompt-package PATH", "Cross-check Prompt Package lineage") do |path|
      options[:prompt_package] = path
    end
  end

  begin
    parser.parse!
    raise OptionParser::MissingArgument, "provide exactly one Clarification Session path" unless ARGV.length == 1

    project_root = File.expand_path("..", __dir__)
    validator = PMind::ClarificationSessionValidator.new(project_root)
    valid = if options[:prompt_package]
              validator.validate_pair_files(ARGV.fetch(0), options[:prompt_package])
            else
              validator.validate_file(ARGV.fetch(0))
            end
    if valid
      lineage = options[:prompt_package] ? "true" : "not_checked"
      puts "PMIND_CLARIFICATION_SESSION_VALIDATION_PASS path=#{File.expand_path(ARGV.fetch(0))} " \
           "status=#{validator.session["status"]} compile_ready=#{validator.session.dig("compile_gate", "ready")} lineage=#{lineage}"
      exit 0
    end

    warn validator.errors.join("\n")
    exit 1
  rescue OptionParser::ParseError => e
    warn "PMIND_CLARIFICATION_SESSION_VALIDATION_ERROR #{e.message}"
    warn parser
    exit 1
  end
end
