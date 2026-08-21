#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "verify_prompt_package_lineage"

module PMind
  class HandoffProposalPreview
    SCHEMA_PATH = "schemas/handoff-proposal-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    RECIPIENT_COPY = {
      "coding_agent" => "编码型 Downstream Executor"
    }.freeze
    ACTION_COPY = {
      "commit" => "提交变更",
      "push" => "推送远端",
      "deploy" => "部署",
      "send_message" => "发送消息",
      "external_service_write" => "修改外部服务"
    }.freeze

    attr_reader :errors, :prompt_package, :proposal

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @prompt_package = nil
      @proposal = nil
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path)
      errors.clear
      @prompt_package = nil
      @proposal = nil

      verifier = PromptPackageLineageVerifier.new(@root)
      lineage_copy = verifier.verify_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path
      )
      errors.concat(verifier.errors)
      return nil unless lineage_copy

      proposal_document = load_yaml_file(handoff_proposal_path)
      return nil unless proposal_document

      @prompt_package = verifier.prompt_package
      @proposal = proposal_document
      proposal_valid = validate_proposal_schema(proposal_document, handoff_proposal_path)
      return nil unless proposal_valid

      validate_package_readiness(prompt_package, package_path)
      validate_binding(
        prompt_package,
        verifier.package_bytes,
        proposal_document,
        handoff_proposal_path
      )
      validate_time(prompt_package, proposal_document, handoff_proposal_path)
      validate_data_policy(prompt_package, proposal_document, handoff_proposal_path)
      return nil unless errors.empty?

      render_copy(prompt_package)
    end

    private

    def load_yaml_file(path)
      YAML.safe_load(
        File.binread(File.expand_path(path)),
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

    def validate_package_readiness(document, path)
      return if document.dig("handoff", "ready") == true

      errors << "#{path}: Handoff Proposal requires a lineage-verified final Package with handoff.ready true"
    end

    def validate_binding(document, package_bytes, proposal_document, path)
      expected = {
        "package_id" => document["package_id"],
        "final_package_file_sha256" => Digest::SHA256.hexdigest(package_bytes),
        "package_handoff_ready" => document.dig("handoff", "ready"),
        "recipient" => document.dig("handoff", "recipient")
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match the exact final Package" unless proposal_document[field] == value
      end
    end

    def validate_time(document, proposal_document, path)
      package_time = parse_time(document.dig("compilation", "created_at"))
      proposal_time = parse_time(proposal_document["created_at"])
      return unless package_time && proposal_time && proposal_time < package_time

      errors << "#{path}: Handoff Proposal cannot predate final Package compilation"
    end

    def validate_data_policy(document, proposal_document, path)
      input_ranks = document.dig("execution_contract", "inputs").map do |input|
        CLASSIFICATION_RANK[input["data_classification"]]
      end.compact
      package_rank = input_ranks.max
      proposal_rank = CLASSIFICATION_RANK[proposal_document["data_classification"]]
      return unless package_rank && proposal_rank && proposal_rank < package_rank

      errors << "#{path}: Handoff Proposal data classification cannot downgrade final Package inputs"
    end

    def render_copy(document)
      handoff = document.fetch("handoff")
      lines = [
        "# Handoff 提案待确认，尚未交接",
        "",
        "最终 Prompt Package 的来源链已验证。以下内容只供确认，本步骤不会保存选择、授权或执行 Handoff。",
        "",
        "## 交接对象",
        "",
        RECIPIENT_COPY.fetch(handoff.fetch("recipient"))
      ]
      append_list(lines, "本次交付范围", document.dig("scope", "in_scope"))
      append_action_boundaries(lines, handoff)
      append_open_items_and_stops(lines, handoff)
      append_approvals(lines, document.fetch("approval_points"))
      append_choices(lines)
      lines.join("\n")
    end

    def append_list(lines, title, values, empty_copy: nil)
      lines.concat(["", "## #{title}", ""])
      if values.empty? && empty_copy
        lines << "- #{empty_copy}"
      else
        values.each { |value| lines << "- #{MarkdownSafety.inline(value)}" }
      end
    end

    def append_action_boundaries(lines, handoff)
      append_action_list(lines, "已授权动作", handoff.fetch("authorized_actions"), "无额外授权动作；不得从本提案推导权限。")
      append_action_list(lines, "禁止动作", handoff.fetch("prohibited_actions"))
    end

    def append_action_list(lines, title, actions, empty_copy = nil)
      readable = actions.map { |action| ACTION_COPY.fetch(action, action.tr("_", " ")) }
      append_list(lines, title, readable, empty_copy: empty_copy)
    end

    def append_open_items_and_stops(lines, handoff)
      append_list(lines, "未决项", handoff.fetch("open_items"), empty_copy: "无未决项。")
      append_list(lines, "停止条件", handoff.fetch("stop_conditions"))
    end

    def append_approvals(lines, approvals)
      lines.concat(["", "## 审批边界保持不变", ""])
      if approvals.empty?
        lines << "- 当前 Package 没有单独审批项。"
      else
        approvals.each do |approval|
          scope = MarkdownSafety.inline(approval.fetch("scope"))
          status = PromptPackageCreator::APPROVAL_COPY.fetch(approval.fetch("status"))
          lines << "- #{scope}：#{status}"
        end
      end
      lines << ""
      lines << "确认 Handoff 提案不会改变任何 Approval Point 状态。"
    end

    def append_choices(lines)
      lines.concat([
                     "",
                     "## 请选择",
                     "",
                     "1. 确认：允许后续受控步骤记录对当前 Handoff 提案的明确选择；本步骤不交接、不产生外部效果。",
                     "2. 请求修改：回到候选 Package，形成新的编译提案、确认回执和最终 Package 来源链。",
                     "3. 拒绝交接：保留已验证的最终 Package，但不允许进入 Handoff。",
                     "",
                     "当前选择尚未保存；Handoff、外部效果和任何高风险动作均未获授权。"
                   ])
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length != 6
    warn "Usage: ruby scripts/preview_handoff_proposal.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffProposalPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
