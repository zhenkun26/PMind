#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "verify_handoff_envelope_lineage"

module PMind
  class HandoffAdapterSelectionPreview
    PROFILE_SCHEMA_PATH = "schemas/handoff-adapter-profile-v0.yaml"
    PROPOSAL_SCHEMA_PATH = "schemas/handoff-adapter-selection-proposal-v0.yaml"
    EFFECT_FIELDS = %w[
      local_file_write
      network_access
      process_start
      notification
      external_service_write
      cost_incurred
      production_data_access
    ].freeze
    ENVELOPE_SOURCE_DIGEST_FIELDS = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
      handoff_confirmation_receipt_file_sha256
    ].freeze
    CLASSIFICATION_RANK = {
      "public" => 0,
      "internal" => 1,
      "confidential" => 2,
      "restricted" => 3
    }.freeze
    DELIVERY_COPY = {
      "local_file" => "本地文件",
      "local_process" => "本地进程",
      "remote_api" => "远程 API",
      "message_channel" => "消息渠道",
      "human_team" => "人工团队"
    }.freeze
    RECEIPT_COPY = {
      "local_digest" => "本地摘要回执",
      "provider_receipt" => "渠道回执",
      "human_acknowledgement" => "人工确认回执",
      "none" => "无回执"
    }.freeze
    EFFECT_COPY = {
      "local_file_write" => "本地文件写入",
      "network_access" => "网络访问",
      "process_start" => "启动进程",
      "notification" => "发送通知",
      "external_service_write" => "修改外部服务",
      "cost_incurred" => "产生费用",
      "production_data_access" => "访问生产数据"
    }.freeze
    CLASSIFICATION_COPY = {
      "public" => "公开",
      "internal" => "内部",
      "confidential" => "机密",
      "restricted" => "受限"
    }.freeze

    attr_reader :errors, :envelope, :profile, :proposal, :input_bytes, :input_digests

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      @envelope = nil
      @profile = nil
      @proposal = nil
      @input_bytes = nil
      @input_digests = nil
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path, profile_path, proposal_path)
      reset_state

      verifier = HandoffEnvelopeLineageVerifier.new(@root)
      lineage_copy = verifier.verify_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path,
        envelope_path
      )
      errors.concat(verifier.errors)
      return nil unless lineage_copy

      profile_document, profile_bytes = load_yaml_file_with_bytes(profile_path)
      proposal_document, proposal_bytes = load_yaml_file_with_bytes(proposal_path)
      return nil unless profile_document && proposal_document

      @envelope = verifier.envelope
      @profile = profile_document
      @proposal = proposal_document
      @input_bytes = {
        "handoff_envelope" => verifier.envelope_bytes,
        "adapter_profile" => profile_bytes,
        "adapter_selection_proposal" => proposal_bytes
      }
      @input_digests = ENVELOPE_SOURCE_DIGEST_FIELDS.to_h do |field|
        [field, verifier.expected_envelope.fetch("authorization").fetch(field)]
      end.merge(
        "handoff_envelope_file_sha256" => Digest::SHA256.hexdigest(verifier.envelope_bytes),
        "adapter_profile_file_sha256" => Digest::SHA256.hexdigest(profile_bytes),
        "adapter_selection_proposal_file_sha256" => Digest::SHA256.hexdigest(proposal_bytes)
      )

      profile_valid = validate_schema(PROFILE_SCHEMA_PATH, profile_document, profile_path)
      proposal_valid = validate_schema(PROPOSAL_SCHEMA_PATH, proposal_document, proposal_path)
      return nil unless profile_valid && proposal_valid

      validate_profile_business_rules(profile_document, profile_path)
      validate_binding(envelope, verifier.envelope_bytes, profile_document, profile_bytes, proposal_document, proposal_path)
      validate_time(envelope, profile_document, proposal_document, proposal_path)
      validate_data_policy(envelope, profile_document, proposal_document, profile_path, proposal_path)
      return nil unless errors.empty?

      render_copy(envelope, profile_document)
    end

    private

    def reset_state
      errors.clear
      @envelope = nil
      @profile = nil
      @proposal = nil
      @input_bytes = nil
      @input_digests = nil
    end

    def load_yaml_file_with_bytes(path)
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

    def validate_schema(schema_path, document, path)
      validator = EvalValidator.new(@root)
      schema = validator.load_yaml(schema_path)
      unless schema
        errors.concat(validator.errors)
        return false
      end

      validator.validate_document(schema, document, path, schema)
      errors.concat(validator.errors)
      document.is_a?(Hash) && validator.errors.empty?
    end

    def validate_profile_business_rules(document, path)
      errors << "#{path}: Adapter Capability Profile must be reviewed before selection" unless document["status"] == "reviewed"

      true_effects = EFFECT_FIELDS.select { |field| document.dig("effects", field) == true }
      required_effects = document.dig("authorization_requirements", "required_effect_authorizations")
      unless required_effects.sort == true_effects.sort
        errors << "#{path}: required_effect_authorizations must exactly match every declared true effect"
      end

      idempotency = document.dig("capabilities", "idempotency")
      if idempotency["supported"] && idempotency["key_source"] == "not_applicable"
        errors << "#{path}: supported idempotency requires a concrete key source"
      elsif !idempotency["supported"] && idempotency["key_source"] != "not_applicable"
        errors << "#{path}: unsupported idempotency must use not_applicable key source"
      end

      retry_policy = document.dig("capabilities", "retry")
      if retry_policy["mode"] == "none" && retry_policy["maximum_attempts"] != 1
        errors << "#{path}: retry mode none requires exactly one attempt"
      elsif retry_policy["mode"] == "bounded" && retry_policy["maximum_attempts"] < 2
        errors << "#{path}: bounded retry requires at least two attempts"
      end

      if document.dig("capabilities", "receipt_mode") == "none"
        errors << "#{path}: a reviewed Adapter Profile must declare a receipt mode"
      end

      created_time = parse_time(document["created_at"])
      reviewed_time = parse_time(document["reviewed_at"])
      if created_time && reviewed_time && reviewed_time < created_time
        errors << "#{path}: Adapter review cannot predate Profile creation"
      end

      can_incur_cost = document.dig("cost_policy", "can_incur_cost")
      effect_incurred = document.dig("effects", "cost_incurred")
      unless can_incur_cost == effect_incurred
        errors << "#{path}: cost policy must match the declared cost effect"
      end
      if can_incur_cost && document.dig("cost_policy", "disclosure_required_before_dispatch") != true
        errors << "#{path}: a cost-incurring Adapter requires disclosure before dispatch"
      end
    end

    def validate_binding(envelope_document, envelope_bytes, profile_document, profile_bytes, proposal_document, path)
      expected = {
        "envelope_id" => envelope_document["envelope_id"],
        "handoff_envelope_file_sha256" => Digest::SHA256.hexdigest(envelope_bytes),
        "envelope_delivery_state" => envelope_document["delivery_state"],
        "recipient" => envelope_document["recipient"],
        "adapter_profile_id" => profile_document["adapter_profile_id"],
        "adapter_profile_file_sha256" => Digest::SHA256.hexdigest(profile_bytes),
        "adapter_profile_status" => profile_document["status"]
      }
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match the exact verified Envelope or reviewed Profile" unless proposal_document[field] == value
      end
    end

    def validate_time(envelope_document, profile_document, proposal_document, path)
      source_times = [envelope_document["created_at"], profile_document["created_at"], profile_document["reviewed_at"]].map { |value| parse_time(value) }.compact
      proposal_time = parse_time(proposal_document["created_at"])
      return unless proposal_time && !source_times.empty? && proposal_time < source_times.max

      errors << "#{path}: Adapter Selection Proposal cannot predate its Envelope or Profile"
    end

    def validate_data_policy(envelope_document, profile_document, proposal_document, profile_path, proposal_path)
      envelope_rank = CLASSIFICATION_RANK[envelope_document["data_classification"]]
      profile_rank = CLASSIFICATION_RANK[profile_document.dig("data_policy", "maximum_data_classification")]
      proposal_rank = CLASSIFICATION_RANK[proposal_document["data_classification"]]
      if envelope_rank && profile_rank && profile_rank < envelope_rank
        errors << "#{profile_path}: Adapter data policy does not accept the Envelope classification"
      end
      if envelope_rank && proposal_rank && proposal_rank < envelope_rank
        errors << "#{proposal_path}: Adapter Selection Proposal data classification cannot downgrade the Envelope"
      end
    end

    def render_copy(envelope_document, profile_document)
      capabilities = profile_document.fetch("capabilities")
      effects = EFFECT_FIELDS.select { |field| profile_document.dig("effects", field) == true }
      lines = [
        "# Handoff Adapter 选择提案待确认，尚未选择或交付",
        "",
        "Handoff Envelope 的来源链已验证，当前仍是 prepared。以下内容只比较一个已审查的 Adapter 能力档案；本步骤不保存选择、不 dispatch，也不产生任何渠道副作用。",
        "",
        "## 候选 Adapter",
        "",
        MarkdownSafety.inline(profile_document.fetch("display_name")),
        "",
        "- 交付方式：#{DELIVERY_COPY.fetch(capabilities.fetch("delivery_mode"))}",
        "- 接收证明：#{RECEIPT_COPY.fetch(capabilities.fetch("receipt_mode"))}",
        "- 幂等支持：#{capabilities.dig("idempotency", "supported") ? "支持" : "不支持"}",
        "- 重试上限：#{capabilities.dig("retry", "maximum_attempts")} 次"
      ]
      append_effects(lines, effects)
      append_data_boundary(lines, envelope_document, profile_document)
      append_choices(lines)
      lines.join("\n")
    end

    def append_effects(lines, effects)
      lines.concat(["", "## 若未来 dispatch，需要分别授权的副作用", ""])
      if effects.empty?
        lines << "- 档案未声明额外副作用；真实实现仍须重新验证。"
      else
        effects.each { |effect| lines << "- #{EFFECT_COPY.fetch(effect)}：未授权" }
      end
      lines << ""
      lines << "本提案不会把既有 Handoff 授权扩大为上述副作用授权。"
    end

    def append_data_boundary(lines, envelope_document, profile_document)
      envelope_classification = CLASSIFICATION_COPY.fetch(envelope_document.fetch("data_classification"))
      maximum_classification = CLASSIFICATION_COPY.fetch(profile_document.dig("data_policy", "maximum_data_classification"))
      personal_policy = profile_document.dig("data_policy", "personal_data_handling") == "allowed" ? "允许" : "禁止"
      lines.concat([
                     "",
                     "## 数据兼容性",
                     "",
                     "- Envelope 数据分类：#{envelope_classification}",
                     "- Adapter 可接受的最高分类：#{maximum_classification}",
                     "- 个人数据策略：#{personal_policy}；Envelope 是否包含个人数据仍未知",
                     "- 密钥策略：禁止；Envelope 是否包含密钥仍未知",
                     "",
                     "数据分类兼容不等于个人数据或密钥兼容。真实 dispatch 前必须完成独立内容审核。"
                   ])
    end

    def append_choices(lines)
      lines.concat([
                     "",
                     "## 请选择",
                     "",
                     "1. 确认候选：允许后续独立 Adapter Selection Confirmation Receipt 记录对当前 Profile 的选择；仍不 dispatch、不批准副作用。",
                     "2. 请求修改：更换或修订 Profile，并生成新的选择提案。",
                     "3. 拒绝候选：保留已验证的 Envelope，但不选择该 Adapter。",
                     "",
                     "当前选择尚未保存；Adapter 未选择，dispatch、外部效果和任何高风险动作均未获授权。"
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
  if ARGV.length != 10
    warn "Usage: ruby scripts/preview_handoff_adapter_selection.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterSelectionPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
