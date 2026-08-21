#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_clarification_revision"

module PMind
  class ClarificationConfirmationPreview
    SCHEMA_PATH = "schemas/clarification-confirmation-receipt-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    STATUS_COPY = {
      "clarifying" => "继续澄清",
      "ready_to_compile" => "具备 Prompt Package 编译条件",
      "blocked" => "保持阻塞，等待最小必要信息"
    }.freeze

    attr_reader :errors, :candidate_session, :confirmation, :input_digests

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @candidate_session = nil
      @confirmation = nil
      @input_digests = nil
    end

    def preview_files(session_path, receipt_path, proposal_path, confirmation_path)
      errors.clear
      @candidate_session = nil
      @confirmation = nil
      @input_digests = nil

      session, session_bytes = load_yaml_file(session_path)
      receipt, receipt_bytes = load_yaml_file(receipt_path)
      proposal, proposal_bytes = load_yaml_file(proposal_path)
      confirmation_document, confirmation_bytes = load_yaml_file(confirmation_path)
      return nil unless session && receipt && proposal && confirmation_document

      digests = {
        "source_session_file_sha256" => Digest::SHA256.hexdigest(session_bytes),
        "answer_receipt_file_sha256" => Digest::SHA256.hexdigest(receipt_bytes),
        "proposal_file_sha256" => Digest::SHA256.hexdigest(proposal_bytes),
        "confirmation_receipt_file_sha256" => Digest::SHA256.hexdigest(confirmation_bytes)
      }
      paths = {
        session: session_path,
        receipt: receipt_path,
        proposal: proposal_path,
        confirmation: confirmation_path
      }
      preview(session, receipt, proposal, confirmation_document, digests, paths)
    end

    def preview(session, receipt, proposal, confirmation_document, digests, paths = {})
      errors.clear
      @candidate_session = nil
      @confirmation = confirmation_document
      @input_digests = digests

      revision_preview = ClarificationRevisionPreview.new(@root)
      proposal_copy = revision_preview.preview(
        session,
        receipt,
        proposal,
        paths.fetch(:session, "clarification-session"),
        paths.fetch(:receipt, "answer-receipt"),
        paths.fetch(:proposal, "revision-proposal")
      )
      errors.concat(revision_preview.errors)
      confirmation_valid = validate_confirmation_schema(
        confirmation_document,
        paths.fetch(:confirmation, "confirmation-receipt")
      )
      return nil unless proposal_copy && confirmation_valid

      @candidate_session = revision_preview.candidate_session
      validate_binding(session, receipt, proposal, confirmation_document, digests, paths.fetch(:confirmation, "confirmation-receipt"))
      return nil unless errors.empty?

      render_copy(confirmation_document, candidate_session)
    end

    private

    def load_yaml_file(path)
      bytes = File.binread(File.expand_path(path))
      document = YAML.safe_load(
        bytes,
        permitted_classes: [],
        permitted_symbols: [],
        aliases: false
      )
      [document, bytes]
    rescue Errno::ENOENT, Errno::EACCES, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      [nil, nil]
    end

    def validate_confirmation_schema(document, path)
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

    def validate_binding(session, receipt, proposal, document, digests, path)
      expected = {
        "session_id" => session["session_id"],
        "source_session_status" => session["status"],
        "source_session_file_sha256" => digests["source_session_file_sha256"],
        "answer_receipt_id" => receipt["receipt_id"],
        "answer_receipt_file_sha256" => digests["answer_receipt_file_sha256"],
        "proposal_id" => proposal["proposal_id"],
        "proposal_file_sha256" => digests["proposal_file_sha256"],
        "round_number" => proposal["round_number"],
        "target_revision_number" => candidate_session.fetch("rounds").length,
        "target_session_status" => candidate_session["status"]
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its confirmed source" unless document[field] == value
      end

      validate_choice(document, path)
      validate_response_digest(document, path)
      validate_time(proposal, document, path)
      validate_data_policy(session, receipt, document, path)
    end

    def validate_choice(document, path)
      expected_authorization = document["confirmation_decision"] == "confirmed"
      unless document["revision_creation_authorized"] == expected_authorization
        errors << "#{path}: revision_creation_authorized must be true only for confirmed"
      end
    end

    def validate_response_digest(document, path)
      expected = Digest::SHA256.hexdigest(document["user_response"])
      unless document["user_response_sha256"] == expected
        errors << "#{path}: user response digest does not match"
      end
    end

    def validate_time(proposal, document, path)
      proposal_time = parse_time(proposal["created_at"])
      confirmation_time = parse_time(document["captured_at"])
      if proposal_time && confirmation_time && confirmation_time < proposal_time
        errors << "#{path}: Confirmation Receipt cannot predate its Proposal"
      end
    end

    def validate_data_policy(session, receipt, document, path)
      source_ranks = [
        CLASSIFICATION_RANK[session.dig("intake", "data_classification")],
        CLASSIFICATION_RANK[receipt["data_classification"]]
      ].compact
      confirmation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if confirmation_rank && !source_ranks.empty? && confirmation_rank < source_ranks.max
        errors << "#{path}: Confirmation Receipt data classification cannot downgrade its sources"
      end
      if document["contains_personal_data"] == true && document["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def render_copy(document, candidate)
      case document.fetch("confirmation_decision")
      when "confirmed"
        render_confirmed_copy(document, candidate)
      when "modify_requested"
        [
          "# 已收到修改请求，当前 Proposal 不会应用",
          "",
          "原 Session 未修改，也不会创建 revision。请根据修改请求形成新的 Proposal，重新预演后再确认。",
          "",
          "普通修改请求不会成为高风险授权。"
        ].join("\n")
      when "rejected"
        [
          "# 已拒绝本次修订，原 Session 保持不变",
          "",
          "当前 Proposal 不会应用，也不会创建 revision。若要继续，请从新的 Clarification 或 Proposal 开始。",
          "",
          "本次拒绝不会改变任何高风险审批状态。"
        ].join("\n")
      end
    end

    def render_confirmed_copy(document, candidate)
      lines = [
        "# 已收到修订确认，尚未创建 revision",
        "",
        "已确认当前 Proposal 的理解。原 Session 仍未修改。",
        "",
        "## 预计创建",
        "",
        "- Revision #{document.fetch("target_revision_number")}",
        "- Session 状态：#{STATUS_COPY.fetch(candidate.fetch("status"))}"
      ]
      actions = candidate.dig("compile_gate", "high_risk_actions")
      unless actions.empty?
        lines.concat(["", "## 仍需单独审批", ""])
        actions.each do |action|
          lines << "- #{MarkdownSafety.inline(action.fetch("description"))}"
        end
      end
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "可由受控创建命令生成新的 Session revision。此确认不授权任何高风险动作。"
                   ])
      lines.join("\n")
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 4
    warn "Usage: ruby scripts/preview_clarification_confirmation.rb SESSION.yaml RECEIPT.yaml PROPOSAL.yaml CONFIRMATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::ClarificationConfirmationPreview.new(project_root)
  copy = preview.preview_files(ARGV.fetch(0), ARGV.fetch(1), ARGV.fetch(2), ARGV.fetch(3))
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
