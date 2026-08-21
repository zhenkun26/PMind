#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_clarification_answers"

module PMind
  class ClarificationRevisionPreview
    SCHEMA_PATH = "schemas/clarification-revision-proposal-v0.yaml"
    OUTCOMES_BY_RESPONSE_KIND = {
      "answered" => %w[resolved assumed unknown],
      "skipped" => %w[assumed unknown],
      "unknown" => ["unknown"],
      "refused" => ["refused"]
    }.freeze
    OUTCOME_COPY = {
      "resolved" => "已解决",
      "assumed" => "暂按假设",
      "unknown" => "仍未知",
      "refused" => "拒绝提供"
    }.freeze
    STATUS_COPY = {
      "clarifying" => "继续澄清",
      "ready_to_compile" => "具备 Prompt Package 编译条件",
      "blocked" => "保持阻塞，等待最小必要信息"
    }.freeze

    attr_reader :errors, :candidate_session

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @candidate_session = nil
    end

    def preview_files(session_path, receipt_path, proposal_path)
      errors.clear
      session = load_yaml_file(session_path)
      receipt = load_yaml_file(receipt_path)
      proposal = load_yaml_file(proposal_path)
      return nil unless session && receipt && proposal

      preview(session, receipt, proposal, session_path, receipt_path, proposal_path)
    end

    def preview(session, receipt, proposal, session_path = "clarification-session", receipt_path = "answer-receipt", proposal_path = "revision-proposal")
      errors.clear
      @candidate_session = nil

      answer_preview = ClarificationAnswerPreview.new(@root)
      receipt_valid = !answer_preview.preview(session, receipt, session_path, receipt_path).nil?
      errors.concat(answer_preview.errors)
      proposal_valid = validate_proposal_schema(proposal, proposal_path)
      return nil unless receipt_valid && proposal_valid

      validate_binding(session, receipt, proposal, proposal_path)
      validate_patch(session, receipt, proposal, proposal_path)
      return nil unless errors.empty?

      @candidate_session = apply_patch(session, receipt, proposal)
      validate_candidate(session, candidate_session, proposal, proposal_path)
      return nil unless errors.empty?

      render_copy(session, proposal, candidate_session)
    end

    private

    def load_yaml_file(path)
      YAML.safe_load(
        File.read(File.expand_path(path)),
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      nil
    end

    def validate_proposal_schema(document, path)
      validator = EvalValidator.new(@root)
      schema = validator.load_yaml(SCHEMA_PATH)
      unless schema
        errors.concat(validator.errors)
        return false
      end

      validator.validate_document(schema, document, path, schema)
      errors.concat(validator.errors)
      document.is_a?(Hash) && validator.errors.empty?
    end

    def validate_binding(session, receipt, proposal, path)
      expected = {
        "session_id" => session["session_id"],
        "session_raw_intent_sha256" => session.dig("intake", "raw_intent_sha256"),
        "source_session_status" => session["status"],
        "receipt_id" => receipt["receipt_id"],
        "round_number" => receipt["round_number"]
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its source" unless proposal[field] == value
      end

      proposal_time = parse_time(proposal["created_at"])
      receipt_time = parse_time(receipt["captured_at"])
      if proposal_time && receipt_time && proposal_time < receipt_time
        errors << "#{path}: Proposal cannot predate its Answer Receipt"
      end
    end

    def validate_patch(session, receipt, proposal, path)
      patch = proposal.fetch("patch")
      responses = receipt.fetch("responses")
      response_ids = responses.map { |response| response["question_id"] }
      questions = index_by(session.fetch("questions"), "question_id")

      validate_question_updates(patch, response_ids, receipt["round_number"], path)
      validate_round_patch(patch, responses, questions, proposal, path)
      validate_gap_updates(session, patch, response_ids, questions, path)
      validate_knowledge_removals(session, patch, questions, response_ids, path)
    end

    def validate_question_updates(patch, response_ids, round_number, path)
      updates = patch.fetch("question_updates")
      update_ids = updates.map { |update| update["question_id"] }
      unless update_ids == response_ids
        errors << "#{path}: question_updates must exactly match Receipt responses in order"
      end
      updates.each do |update|
        unless update["status"] == "asked" && update["round_number"] == round_number
          errors << "#{path}: every current question must become asked in the Receipt round"
        end
      end
    end

    def validate_round_patch(patch, responses, questions, proposal, path)
      round = patch.fetch("append_round")
      unless round["round_number"] == proposal["round_number"]
        errors << "#{path}: appended round_number must match the Proposal"
      end
      unless round["completed_at"] == proposal["created_at"]
        errors << "#{path}: appended round completed_at must equal Proposal created_at"
      end

      answers = round.fetch("answers")
      answer_ids = answers.map { |answer| answer["question_id"] }
      response_ids = responses.map { |response| response["question_id"] }
      unless answer_ids == response_ids
        errors << "#{path}: normalized answers must exactly match Receipt responses in order"
      end

      responses.each_with_index do |response, index|
        answer = answers[index]
        next unless answer

        question = questions[response["question_id"]]
        unless answer["source_user_answer_sha256"] == response["user_answer_sha256"]
          errors << "#{path}: normalization source answer digest does not match #{response["question_id"]}"
        end
        allowed_outcomes = OUTCOMES_BY_RESPONSE_KIND.fetch(response["response_kind"])
        unless allowed_outcomes.include?(answer["outcome_status"])
          errors << "#{path}: #{response["response_kind"]} response cannot become #{answer["outcome_status"]}"
        end
        if question && answer["affected_fields"] != question["affected_fields"]
          errors << "#{path}: normalized affected_fields must match #{response["question_id"]}"
        end
        if answer["normalized_conclusion"].length > 2000
          errors << "#{path}: normalized conclusion for #{response["question_id"]} exceeds 2000 characters"
        end
        if answer["user_visible_effect"].length > 500
          errors << "#{path}: user-visible effect for #{response["question_id"]} exceeds 500 characters"
        end
      end
    end

    def validate_gap_updates(session, patch, response_ids, questions, path)
      dimensions = response_ids.map { |question_id| questions.fetch(question_id)["gap_dimension"] }
      if dimensions.uniq.length != dimensions.length
        errors << "#{path}: v0 requires one current question per Gap dimension"
        return
      end

      updates = patch.fetch("gap_updates")
      unless updates.map { |update| update["dimension"] } == dimensions
        errors << "#{path}: gap_updates must exactly match current question dimensions in order"
      end
      updates.each_with_index do |update, index|
        question_id = response_ids[index]
        answer = patch.dig("append_round", "answers", index)
        next unless question_id && answer

        unless update["source_question_ids"] == [question_id]
          errors << "#{path}: Gap #{update["dimension"]} must cite its current question only"
        end
        expected_gap_status = %w[unknown refused].include?(answer["outcome_status"]) ? "unknown" : answer["outcome_status"]
        unless update["status"] == expected_gap_status
          errors << "#{path}: Gap #{update["dimension"]} status must match its normalized outcome"
        end
      end
    end

    def validate_knowledge_removals(session, patch, questions, response_ids, path)
      mutable_dimensions = response_ids.map { |question_id| questions.fetch(question_id)["gap_dimension"] }
      removable_refs = session.fetch("gaps").select do |gap|
        mutable_dimensions.include?(gap["dimension"])
      end.map { |gap| gap["knowledge_ref"] }.compact

      requested = patch.fetch("assumption_ids_to_remove") + patch.fetch("unknown_ids_to_remove")
      (requested - removable_refs).each do |knowledge_id|
        errors << "#{path}: cannot remove unrelated knowledge #{knowledge_id}"
      end
    end

    def apply_patch(session, receipt, proposal)
      candidate = deep_copy(session)
      patch = proposal.fetch("patch")
      responses = index_by(receipt.fetch("responses"), "question_id")

      candidate["status"] = patch.fetch("status_after")
      question_index = index_by(candidate.fetch("questions"), "question_id")
      patch.fetch("question_updates").each do |update|
        question = question_index.fetch(update.fetch("question_id"))
        question["status"] = "asked"
        question["round_number"] = update.fetch("round_number")
      end
      candidate["questions"].concat(deep_copy(patch.fetch("questions_to_add")))

      round_patch = patch.fetch("append_round")
      candidate["rounds"] << {
        "round_number" => round_patch.fetch("round_number"),
        "completed_at" => round_patch.fetch("completed_at"),
        "answers" => round_patch.fetch("answers").map do |answer|
          response = responses.fetch(answer.fetch("question_id"))
          {
            "question_id" => answer.fetch("question_id"),
            "user_answer" => response.fetch("user_answer"),
            "outcome_status" => answer.fetch("outcome_status"),
            "normalized_conclusion" => answer.fetch("normalized_conclusion"),
            "affected_fields" => deep_copy(answer.fetch("affected_fields"))
          }
        end
      }

      gap_index = index_by(candidate.fetch("gaps"), "dimension")
      patch.fetch("gap_updates").each do |update|
        gap = gap_index.fetch(update.fetch("dimension"))
        gap["status"] = update.fetch("status")
        gap["blocking"] = update.fetch("blocking")
        gap["summary"] = update.fetch("summary")
        gap["source_refs"] = (gap.fetch("source_refs") + update.fetch("source_question_ids")).uniq
        if update.key?("knowledge_ref")
          gap["knowledge_ref"] = update["knowledge_ref"]
        else
          gap.delete("knowledge_ref")
        end
        gap.delete("not_applicable_reason")
      end

      candidate["assumptions"].delete_if do |entry|
        patch.fetch("assumption_ids_to_remove").include?(entry["assumption_id"])
      end
      candidate["unknowns"].delete_if do |entry|
        patch.fetch("unknown_ids_to_remove").include?(entry["unknown_id"])
      end
      candidate["assumptions"].concat(deep_copy(patch.fetch("assumptions_to_add")))
      candidate["unknowns"].concat(deep_copy(patch.fetch("unknowns_to_add")))
      candidate["decisions"].concat(deep_copy(patch.fetch("decisions_to_add")))
      candidate["compile_gate"] = deep_copy(patch.fetch("compile_gate_after"))
      candidate
    end

    def validate_candidate(source, candidate, proposal, path)
      validate_high_risk_preservation(source, candidate, path)
      validator = ClarificationSessionValidator.new(@root)
      unless validator.validate(candidate, "#{path}.candidate_session")
        errors.concat(validator.errors)
      end
      unless candidate["status"] == proposal.dig("patch", "status_after")
        errors << "#{path}: Candidate Session status does not match status_after"
      end
    end

    def validate_high_risk_preservation(source, candidate, path)
      source_actions = index_by(source.dig("compile_gate", "high_risk_actions"), "action")
      candidate_actions = index_by(candidate.dig("compile_gate", "high_risk_actions"), "action")
      source_actions.each do |action, definition|
        unless candidate_actions[action] == definition
          errors << "#{path}: existing high-risk action #{action} must be preserved exactly"
        end
      end
    end

    def render_copy(_source, proposal, candidate)
      patch = proposal.fetch("patch")
      lines = [
        "# 请确认我对本轮回答的理解",
        "",
        "以下内容只是 Session revision 预演，当前 Session 尚未修改。"
      ]
      lines.concat(["", "## 拟记录的理解", ""])
      questions = index_by(candidate.fetch("questions"), "question_id")
      patch.dig("append_round", "answers").each_with_index do |answer, index|
        question = questions.fetch(answer.fetch("question_id"))
        lines << "#{index + 1}. #{MarkdownSafety.inline(question.fetch("question"))}"
        lines << ""
        lines << "   我的理解：#{MarkdownSafety.inline(answer.fetch("normalized_conclusion"))}"
        lines << ""
        lines << "   对产品的影响：#{MarkdownSafety.inline(answer.fetch("user_visible_effect"))}"
        lines << ""
        lines << "   拟记录为：#{OUTCOME_COPY.fetch(answer.fetch("outcome_status"))}"
        lines << "" unless index == patch.dig("append_round", "answers").length - 1
      end

      lines.concat([
                     "",
                     "## 预计结果",
                     "",
                     "- #{STATUS_COPY.fetch(candidate.fetch("status"))}"
                   ])
      append_assumptions(lines, patch.fetch("assumptions_to_add"))
      append_unknowns(lines, candidate.fetch("unknowns"))
      append_decisions(lines, patch.fetch("decisions_to_add"))
      append_high_risk_actions(lines, candidate.dig("compile_gate", "high_risk_actions"))
      lines.concat([
                     "",
                     "## 请选择",
                     "",
                     "1. 确认：允许后续步骤据此创建新的 Session revision。",
                     "2. 修改：指出哪一项理解或影响不准确。",
                     "3. 拒绝：保留当前 Session，不应用这份 Proposal。"
                   ])
      lines.join("\n")
    end

    def append_assumptions(lines, assumptions)
      return if assumptions.empty?

      lines.concat(["", "## 新增假设", ""])
      assumptions.each do |assumption|
        lines << "- #{MarkdownSafety.inline(assumption.fetch("statement"))}（如果不成立：#{MarkdownSafety.inline(assumption.fetch("invalidation_impact"))}）"
      end
    end

    def append_unknowns(lines, unknowns)
      return if unknowns.empty?

      lines.concat(["", "## 仍需留意的未知项", ""])
      unknowns.each do |unknown|
        suffix = unknown["blocking"] == true ? "（阻塞）" : "（不阻塞）"
        lines << "- #{MarkdownSafety.inline(unknown.fetch("question"))}#{suffix}"
      end
    end

    def append_decisions(lines, decisions)
      return if decisions.empty?

      lines.concat(["", "## 新增决策", ""])
      decisions.each do |decision|
        lines << "- #{MarkdownSafety.inline(decision.fetch("selected_option"))}：#{MarkdownSafety.inline(decision.fetch("rationale"))}"
      end
    end

    def append_high_risk_actions(lines, actions)
      return if actions.empty?

      lines.concat(["", "## 仍需单独审批", ""])
      actions.each do |action|
        lines << "- #{MarkdownSafety.inline(action.fetch("description"))}"
      end
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end

    def index_by(entries, field)
      values = entries.is_a?(Array) ? entries.select { |entry| entry.is_a?(Hash) } : []
      values.each_with_object({}) { |entry, index| index[entry[field]] = entry }
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 3
    warn "Usage: ruby scripts/preview_clarification_revision.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::ClarificationRevisionPreview.new(project_root)
  copy = preview.preview_files(ARGV.fetch(0), ARGV.fetch(1), ARGV.fetch(2))
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
