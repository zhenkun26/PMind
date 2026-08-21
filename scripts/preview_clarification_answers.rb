#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "validate_clarification_session"

module PMind
  class ClarificationAnswerPreview
    SCHEMA_PATH = "schemas/clarification-answer-receipt-v0.yaml"
    ALLOWED_SESSION_STATUSES = %w[gap_scan clarifying].freeze
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    RESPONSE_COPY = {
      "answered" => "已收到回答，等待归一化与复核。",
      "skipped" => "已记录跳过，将按安全默认或停止条件处理。",
      "unknown" => "已记录“不知道”，将重新判断是否阻塞。",
      "refused" => "已记录拒绝提供，不会推断或补写。"
    }.freeze

    attr_reader :errors, :session, :receipt

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @session = nil
      @receipt = nil
    end

    def preview_files(session_path, receipt_path)
      errors.clear
      @session = load_yaml_file(session_path)
      @receipt = load_yaml_file(receipt_path)
      return nil unless session && receipt

      preview(session, receipt, session_path, receipt_path)
    end

    def preview(session_document, receipt_document, session_path = "clarification-session", receipt_path = "answer-receipt")
      errors.clear
      @session = session_document
      @receipt = receipt_document

      session_validator = ClarificationSessionValidator.new(@root)
      session_valid = session_validator.validate(session_document, session_path)
      errors.concat(session_validator.errors)
      receipt_valid = validate_receipt_schema(receipt_document, receipt_path)
      return nil unless session_valid && receipt_valid

      validate_binding(session_document, receipt_document, receipt_path)
      return nil unless errors.empty?

      render_copy(session_document, receipt_document)
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

    def validate_receipt_schema(document, path)
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

    def validate_binding(session_document, receipt_document, path)
      validate_session_state(session_document, receipt_document, path)
      validate_identity(session_document, receipt_document, path)
      validate_round(session_document, receipt_document, path)
      validate_responses(session_document, receipt_document, path)
      validate_time(session_document, receipt_document, path)
      validate_data_policy(session_document, receipt_document, path)
    end

    def validate_session_state(session_document, receipt_document, path)
      status = session_document["status"]
      unless ALLOWED_SESSION_STATUSES.include?(status)
        errors << "#{path}: Answer Receipt dry-run requires a gap_scan or clarifying Session"
      end
      unless receipt_document["session_status"] == status
        errors << "#{path}: captured session_status does not match the current Session"
      end
    end

    def validate_identity(session_document, receipt_document, path)
      unless receipt_document["session_id"] == session_document["session_id"]
        errors << "#{path}: session_id does not match the current Session"
      end
      unless receipt_document["session_raw_intent_sha256"] == session_document.dig("intake", "raw_intent_sha256")
        errors << "#{path}: Session raw Intent digest does not match"
      end
    end

    def validate_round(session_document, receipt_document, path)
      expected_round = session_document.fetch("rounds").length + 1
      unless receipt_document["round_number"] == expected_round
        errors << "#{path}: round_number must be the next consecutive round #{expected_round}"
      end
    end

    def validate_responses(session_document, receipt_document, path)
      responses = receipt_document.fetch("responses")
      response_ids = responses.map { |response| response["question_id"] }
      duplicate_values(response_ids).each do |question_id|
        errors << "#{path}: duplicate response for #{question_id}"
      end

      next_ids = session_document.dig("compile_gate", "next_question_ids")
      unless response_ids == next_ids
        errors << "#{path}: responses must exactly match next_question_ids in order"
      end

      questions = session_document.fetch("questions").each_with_object({}) do |question, index|
        index[question["question_id"]] = question
      end
      responses.each do |response|
        question = questions[response["question_id"]]
        next unless question

        if response["user_answer"].length > 4000
          errors << "#{path}: user answer for #{response["question_id"]} exceeds 4000 characters"
        end
        expected_question_digest = Digest::SHA256.hexdigest(question["question"])
        unless response["question_sha256"] == expected_question_digest
          errors << "#{path}: question digest does not match #{response["question_id"]}"
        end
        expected_answer_digest = Digest::SHA256.hexdigest(response["user_answer"])
        unless response["user_answer_sha256"] == expected_answer_digest
          errors << "#{path}: user answer digest does not match #{response["question_id"]}"
        end
      end
    end

    def validate_time(session_document, receipt_document, path)
      captured_at = parse_time(receipt_document["captured_at"])
      boundaries = [parse_time(session_document["created_at"])]
      session_document.fetch("rounds").each do |round|
        boundaries << parse_time(round["completed_at"])
      end
      latest_boundary = boundaries.compact.max
      if captured_at && latest_boundary && captured_at < latest_boundary
        errors << "#{path}: captured_at cannot predate the Session or its latest completed round"
      end
    end

    def validate_data_policy(session_document, receipt_document, path)
      session_rank = CLASSIFICATION_RANK[session_document.dig("intake", "data_classification")]
      receipt_rank = CLASSIFICATION_RANK[receipt_document["data_classification"]]
      if session_rank && receipt_rank && receipt_rank < session_rank
        errors << "#{path}: Answer Receipt data classification cannot downgrade the Session"
      end
      if receipt_document["contains_personal_data"] == true && receipt_document["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def render_copy(session_document, receipt_document)
      response_count = receipt_document.fetch("responses").length
      lines = [
        "# 回答已收到，尚未应用",
        "",
        "已收到本轮 #{response_count} 项回复，将用于预演第 #{receipt_document.fetch("round_number")} 轮记录。Session 尚未修改。"
      ]
      append_privacy_notice(lines, session_document, receipt_document)
      lines.concat(["", "## 记录结果", ""])

      questions = session_document.fetch("questions").each_with_object({}) do |question, index|
        index[question.fetch("question_id")] = question
      end
      receipt_document.fetch("responses").each_with_index do |response, index|
        question = questions.fetch(response.fetch("question_id"))
        lines << "#{index + 1}. #{MarkdownSafety.inline(question.fetch("question"))}"
        lines << ""
        lines << "   记录状态：#{RESPONSE_COPY.fetch(response.fetch("response_kind"))}"
        lines << "" unless index == receipt_document.fetch("responses").length - 1
      end

      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "操作者仍需逐项确认归一化结论、受影响字段和信息缺口状态，再创建新的 Session revision。普通回答不会自动成为高风险授权。"
                   ])
      lines.join("\n")
    end

    def append_privacy_notice(lines, session_document, receipt_document)
      session_intake = session_document.fetch("intake")
      sensitive = session_intake["contains_personal_data"] == true ||
                  receipt_document["contains_personal_data"] == true ||
                  %w[confidential restricted].include?(receipt_document["data_classification"])
      return unless sensitive

      lines.concat([
                     "",
                     "> 隐私提示：确认文案不会回显原答；后续处理仍应保持最小化和脱敏，不要加入密钥或 token。"
                   ])
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end

    def duplicate_values(values)
      values.group_by { |value| value }.select { |_value, group| group.length > 1 }.keys
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 2
    warn "Usage: ruby scripts/preview_clarification_answers.rb SESSION.yaml RECEIPT.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::ClarificationAnswerPreview.new(project_root)
  copy = preview.preview_files(ARGV.fetch(0), ARGV.fetch(1))
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
