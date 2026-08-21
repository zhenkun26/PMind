#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_prompt_package_compilation"

module PMind
  class PromptPackageCompilationConfirmationPreview
    SCHEMA_PATH = "schemas/prompt-package-compilation-confirmation-receipt-v0.yaml"
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    APPROVAL_COPY = {
      "required" => "仍待单独审批",
      "approved" => "已按限定范围批准",
      "rejected" => "已拒绝",
      "not_applicable" => "不适用"
    }.freeze

    attr_reader :errors, :session, :prompt_package, :proposal, :confirmation, :input_digests

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @session = nil
      @prompt_package = nil
      @proposal = nil
      @confirmation = nil
      @input_digests = nil
    end

    def preview_files(session_path, package_path, proposal_path, confirmation_path)
      errors.clear
      @session = nil
      @prompt_package = nil
      @proposal = nil
      @confirmation = nil
      @input_digests = nil

      session_document, session_bytes = load_yaml_file(session_path)
      package_document, package_bytes = load_yaml_file(package_path)
      proposal_document, proposal_bytes = load_yaml_file(proposal_path)
      confirmation_document, confirmation_bytes = load_yaml_file(confirmation_path)
      return nil unless session_document && package_document && proposal_document && confirmation_document

      digests = {
        "source_session_file_sha256" => Digest::SHA256.hexdigest(session_bytes),
        "draft_package_file_sha256" => Digest::SHA256.hexdigest(package_bytes),
        "compilation_proposal_file_sha256" => Digest::SHA256.hexdigest(proposal_bytes),
        "compilation_confirmation_receipt_file_sha256" => Digest::SHA256.hexdigest(confirmation_bytes)
      }
      paths = {
        session: session_path,
        package: package_path,
        proposal: proposal_path,
        confirmation: confirmation_path
      }
      preview(session_document, package_document, proposal_document, confirmation_document, digests, paths)
    end

    def preview(session_document, package_document, proposal_document, confirmation_document, digests, paths = {})
      errors.clear
      @session = session_document
      @prompt_package = package_document
      @proposal = proposal_document
      @confirmation = confirmation_document
      @input_digests = digests

      compilation_preview = PromptPackageCompilationPreview.new(@root)
      proposal_copy = compilation_preview.preview(
        session_document,
        package_document,
        proposal_document,
        {
          "source_session_file_sha256" => digests["source_session_file_sha256"],
          "draft_package_file_sha256" => digests["draft_package_file_sha256"]
        },
        paths.fetch(:session, "session-revision"),
        paths.fetch(:package, "draft-package"),
        paths.fetch(:proposal, "compilation-proposal")
      )
      errors.concat(compilation_preview.errors)
      confirmation_valid = validate_confirmation_schema(
        confirmation_document,
        paths.fetch(:confirmation, "compilation-confirmation")
      )
      return nil unless proposal_copy && confirmation_valid

      validate_binding(
        session_document,
        package_document,
        proposal_document,
        confirmation_document,
        digests,
        paths.fetch(:confirmation, "compilation-confirmation")
      )
      return nil unless errors.empty?

      render_copy(confirmation_document, package_document)
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

    def validate_binding(session_document, package_document, proposal_document, document, digests, path)
      expected = {
        "session_id" => session_document["session_id"],
        "source_session_revision_number" => session_document.dig("revision", "revision_number"),
        "source_session_status" => session_document["status"],
        "source_session_file_sha256" => digests["source_session_file_sha256"],
        "package_id" => package_document["package_id"],
        "draft_package_file_sha256" => digests["draft_package_file_sha256"],
        "compilation_proposal_id" => proposal_document["compilation_proposal_id"],
        "compilation_proposal_file_sha256" => digests["compilation_proposal_file_sha256"],
        "draft_package_handoff_ready" => package_document.dig("handoff", "ready")
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its confirmed source" unless document[field] == value
      end

      validate_choice(document, package_document, path)
      validate_response_digest(document, path)
      validate_time(proposal_document, document, path)
      validate_data_policy(session_document, proposal_document, document, path)
    end

    def validate_choice(document, package_document, path)
      expected_authorization = document["confirmation_decision"] == "confirmed" &&
                               package_document.dig("handoff", "ready") == true
      unless document["package_creation_authorized"] == expected_authorization
        errors << "#{path}: package_creation_authorized must be true only for a confirmed, Handoff-ready draft Package"
      end
    end

    def validate_response_digest(document, path)
      expected = Digest::SHA256.hexdigest(document["user_response"])
      unless document["user_response_sha256"] == expected
        errors << "#{path}: user response digest does not match"
      end
    end

    def validate_time(proposal_document, document, path)
      proposal_time = parse_time(proposal_document["created_at"])
      confirmation_time = parse_time(document["captured_at"])
      if proposal_time && confirmation_time && confirmation_time < proposal_time
        errors << "#{path}: Compilation Confirmation Receipt cannot predate its Proposal"
      end
    end

    def validate_data_policy(session_document, proposal_document, document, path)
      source_ranks = [
        CLASSIFICATION_RANK[session_document.dig("intake", "data_classification")],
        CLASSIFICATION_RANK[proposal_document["data_classification"]]
      ].compact
      confirmation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if confirmation_rank && !source_ranks.empty? && confirmation_rank < source_ranks.max
        errors << "#{path}: Compilation Confirmation Receipt data classification cannot downgrade its sources"
      end

      source_has_personal_data = session_document.dig("intake", "contains_personal_data") == true ||
                                 proposal_document["contains_personal_data"] == true
      if source_has_personal_data && document["contains_personal_data"] != true
        errors << "#{path}: Compilation Confirmation Receipt cannot drop a source personal-data declaration"
      end
      if document["contains_personal_data"] == true && document["data_classification"] == "public"
        errors << "#{path}: personal data cannot use public classification"
      end
    end

    def render_copy(document, package_document)
      case document.fetch("confirmation_decision")
      when "confirmed"
        if package_document.dig("handoff", "ready") == true
          render_confirmed_ready_copy(package_document)
        else
          render_confirmed_not_ready_copy
        end
      when "modify_requested"
        [
          "# 已收到 Package 修改请求，当前编译提案不会继续",
          "",
          "Session revision 和候选 Package 均未修改，也不会创建最终 Package。请修改候选内容，重新校验并形成新的 Compilation Proposal。",
          "",
          "本次修改请求不授权 Handoff，也不会改变任何 Approval Point。"
        ].join("\n")
      when "rejected"
        [
          "# 已拒绝本次 Package 编译，Session revision 保持不变",
          "",
          "当前候选 Package 不会成为最终 Package，也不会发生 Handoff。若要继续，必须从新的候选 Package 和 Compilation Proposal 开始。",
          "",
          "本次拒绝不会改变任何 Approval Point。"
        ].join("\n")
      end
    end

    def render_confirmed_ready_copy(package_document)
      lines = [
        "# 已收到 Package 创建确认，尚未创建最终 Package",
        "",
        "已确认当前候选内容。Session revision 和候选 Package 均未修改。",
        "",
        "## 当前结果",
        "",
        "- 候选 Package 已通过结构化 Quality Gate",
        "- 后续只允许受控本地创建，不允许自动 Handoff"
      ]
      append_approvals(lines, package_document.fetch("approval_points"))
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "可由后续 confirmed-only、no-overwrite creator 创建最终 Package。此确认不授权 Handoff，也不批准任何仍待处理的高风险动作。"
                   ])
      lines.join("\n")
    end

    def render_confirmed_not_ready_copy
      [
        "# 已确认当前编译理解，但候选 Package 尚未就绪",
        "",
        "已记录对当前理解的确认，但不会授权创建可交接 Package，也不会发生 Handoff。",
        "",
        "请修正 Quality Gate，重新校验候选 Package，并形成新的 Compilation Proposal 和 Confirmation Receipt。"
      ].join("\n")
    end

    def append_approvals(lines, approvals)
      return if approvals.empty?

      lines.concat(["", "## 审批边界保持不变", ""])
      approvals.each do |approval|
        scope = MarkdownSafety.inline(approval.fetch("scope"))
        lines << "- #{scope}：#{APPROVAL_COPY.fetch(approval.fetch("status"))}"
      end
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
    warn "Usage: ruby scripts/preview_prompt_package_compilation_confirmation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::PromptPackageCompilationConfirmationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
