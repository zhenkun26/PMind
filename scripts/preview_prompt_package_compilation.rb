#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "validate_clarification_session"

module PMind
  class PromptPackageCompilationPreview
    SCHEMA_PATH = "schemas/prompt-package-compilation-proposal-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    APPROVAL_COPY = {
      "required" => "待单独审批",
      "approved" => "已按限定范围批准",
      "rejected" => "已拒绝",
      "not_applicable" => "不适用"
    }.freeze

    attr_reader :errors, :session, :prompt_package, :proposal, :input_digests

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @session = nil
      @prompt_package = nil
      @proposal = nil
      @input_digests = nil
    end

    def preview_files(session_path, package_path, proposal_path)
      errors.clear
      @session = nil
      @prompt_package = nil
      @proposal = nil
      @input_digests = nil

      session_document, session_bytes = load_yaml_file(session_path)
      package_document, package_bytes = load_yaml_file(package_path)
      proposal_document, _proposal_bytes = load_yaml_file(proposal_path)
      return nil unless session_document && package_document && proposal_document

      digests = {
        "source_session_file_sha256" => Digest::SHA256.hexdigest(session_bytes),
        "draft_package_file_sha256" => Digest::SHA256.hexdigest(package_bytes)
      }
      preview(
        session_document,
        package_document,
        proposal_document,
        digests,
        session_path,
        package_path,
        proposal_path
      )
    end

    def preview(session_document, package_document, proposal_document, digests, session_path = "session-revision", package_path = "draft-package", proposal_path = "compilation-proposal")
      errors.clear
      @session = session_document
      @prompt_package = package_document
      @proposal = proposal_document
      @input_digests = digests

      proposal_valid = validate_proposal_schema(proposal_document, proposal_path)
      pair_validator = ClarificationSessionValidator.new(@root)
      pair_valid = pair_validator.validate_pair(session_document, package_document, session_path, package_path)
      errors.concat(pair_validator.errors)
      return nil unless proposal_valid && pair_valid

      validate_source_revision(session_document, session_path)
      validate_binding(session_document, package_document, proposal_document, digests, proposal_path)
      validate_time(session_document, package_document, proposal_document, proposal_path)
      validate_data_policy(session_document, proposal_document, proposal_path)
      return nil unless errors.empty?

      render_copy(package_document, proposal_document)
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

    def validate_source_revision(document, path)
      revision = document["revision"]
      unless revision.is_a?(Hash)
        errors << "#{path}: compilation requires a persisted Session revision with lineage metadata"
        return
      end

      unless revision["confirmation_decision"] == "confirmed" && revision["high_risk_authorization_inferred"] == false
        errors << "#{path}: compilation requires a confirmed Session revision without inferred high-risk authorization"
      end
    end

    def validate_binding(session_document, package_document, proposal_document, digests, path)
      expected = {
        "session_id" => session_document["session_id"],
        "source_session_revision_number" => session_document.dig("revision", "revision_number"),
        "source_session_status" => session_document["status"],
        "source_session_file_sha256" => digests["source_session_file_sha256"],
        "package_id" => package_document["package_id"],
        "draft_package_file_sha256" => digests["draft_package_file_sha256"],
        "draft_package_handoff_ready" => package_document.dig("handoff", "ready")
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its exact source" unless proposal_document[field] == value
      end
    end

    def validate_time(session_document, package_document, proposal_document, path)
      source_times = [
        parse_time(session_document.dig("revision", "created_at")),
        parse_time(package_document["created_at"])
      ].compact
      proposal_time = parse_time(proposal_document["created_at"])
      if proposal_time && !source_times.empty? && proposal_time < source_times.max
        errors << "#{path}: Compilation Proposal cannot predate its Session revision or draft Package"
      end
    end

    def validate_data_policy(session_document, proposal_document, path)
      source_rank = CLASSIFICATION_RANK[session_document.dig("intake", "data_classification")]
      proposal_rank = CLASSIFICATION_RANK[proposal_document["data_classification"]]
      if source_rank && proposal_rank && proposal_rank < source_rank
        errors << "#{path}: Compilation Proposal data classification cannot downgrade its Session"
      end
      if session_document.dig("intake", "contains_personal_data") == true && proposal_document["contains_personal_data"] != true
        errors << "#{path}: Compilation Proposal cannot drop the Session personal-data declaration"
      end
      if proposal_document["contains_personal_data"] == true && proposal_document["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def render_copy(package_document, proposal_document)
      lines = [
        "# 请确认 Prompt Package 编译提案",
        "",
        "以下是候选 Package 的审阅摘要。尚未创建受控最终 Package，也尚未发生 Handoff。"
      ]
      append_list(lines, "本次范围", package_document.dig("scope", "in_scope"))
      append_recommendation(lines, package_document.fetch("recommendation"))
      append_acceptance(lines, package_document.fetch("acceptance_criteria"))
      append_unknowns(lines, package_document.dig("knowledge", "unknowns"), package_document.dig("handoff", "open_items"))
      append_approvals(lines, package_document.fetch("approval_points"))
      append_privacy_notice(lines, proposal_document)
      append_quality_gate(lines, package_document.dig("handoff", "ready"))
      append_choices(lines, package_document.dig("handoff", "ready"))
      lines.join("\n")
    end

    def append_list(lines, title, values)
      lines.concat(["", "## #{title}", ""])
      values.each { |value| lines << "- #{MarkdownSafety.inline(value)}" }
    end

    def append_recommendation(lines, recommendation)
      lines.concat([
                     "",
                     "## 推荐方案",
                     "",
                     MarkdownSafety.inline(recommendation.fetch("selected_option"))
                   ])
      tradeoffs = recommendation.fetch("tradeoffs")
      append_list(lines, "主要取舍", tradeoffs) unless tradeoffs.empty?
    end

    def append_acceptance(lines, criteria)
      blocking = criteria.select { |criterion| criterion["blocking"] == true }
      lines.concat(["", "## Blocking 验收标准", ""])
      if blocking.empty?
        lines << "- 当前候选 Package 没有 blocking 验收标准。"
      else
        blocking.each { |criterion| lines << "- #{MarkdownSafety.inline(criterion.fetch("statement"))}" }
      end
    end

    def append_unknowns(lines, unknowns, open_items)
      values = unknowns.map do |unknown|
        suffix = unknown["blocking"] == true ? "（阻塞）" : "（不阻塞）"
        "#{unknown.fetch("question")}#{suffix}"
      end
      values.concat(open_items)
      append_list(lines, "仍需留意", values) unless values.empty?
    end

    def append_approvals(lines, approvals)
      lines.concat(["", "## 审批边界", ""])
      if approvals.empty?
        lines << "- 当前候选 Package 没有单独审批项。"
      else
        approvals.each do |approval|
          scope = MarkdownSafety.inline(approval.fetch("scope"))
          lines << "- #{scope}：#{APPROVAL_COPY.fetch(approval.fetch("status"))}"
        end
      end
      lines << ""
      lines << "确认编译提案不会改变任何审批状态。"
    end

    def append_privacy_notice(lines, proposal_document)
      sensitive = proposal_document["contains_personal_data"] == true ||
                  %w[confidential restricted].include?(proposal_document["data_classification"])
      return unless sensitive

      lines.concat([
                     "",
                     "> 隐私提示：确认文案不会展示原始 Intent、原答或来源内容；后续创建仍应保持最小化和既有数据边界。"
                   ])
    end

    def append_quality_gate(lines, ready)
      message = if ready == true
                  "候选 Package 的结构化 Quality Gate 标记为可交接；仍需完成本次确认，且确认本身不执行 Handoff。"
                else
                  "候选 Package 尚未通过结构化 Quality Gate；可以审阅，但不得创建可交接 Package。"
                end
      lines.concat(["", "## 候选质量门", "", message])
    end

    def append_choices(lines, ready)
      confirmed_copy = if ready == true
                         "确认：允许后续受控步骤基于这份候选内容创建最终 Package；不等于 Handoff 或高风险授权。"
                       else
                         "确认理解：记录对当前内容的认可，但不允许创建可交接 Package；修正 Quality Gate 后必须重新提案。"
                       end
      lines.concat([
                     "",
                     "## 请选择",
                     "",
                     "1. #{confirmed_copy}",
                     "2. 修改：指出范围、方案、验收、未知项或审批边界中需要调整的内容。",
                     "3. 拒绝：停止本次编译，保留 Session revision，不创建最终 Package。"
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
  if ARGV.length != 3
    warn "Usage: ruby scripts/preview_prompt_package_compilation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::PromptPackageCompilationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
