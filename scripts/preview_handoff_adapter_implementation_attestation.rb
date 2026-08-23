#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "time"
require "yaml"
require_relative "markdown_safety"
require_relative "preview_handoff_adapter_effect_authorization_confirmation"

module PMind
  class HandoffAdapterImplementationAttestationPreview
    SCHEMA_PATH = "schemas/handoff-adapter-implementation-attestation-v0.yaml"
    CLASSIFICATION_RANK = HandoffPayloadDataAttestationPreview::CLASSIFICATION_RANK
    REVIEW_METHOD_COPY = HandoffPayloadDataAttestationPreview::REVIEW_METHOD_COPY
    COVERAGE_FIELDS = %w[
      delivery_mode_covered
      receipt_mode_covered
      idempotency_covered
      retry_covered
      effect_boundaries_covered
      data_policy_covered
      cost_policy_covered
    ].freeze
    COVERAGE_COPY = {
      "delivery_mode_covered" => "交付方式",
      "receipt_mode_covered" => "回执方式",
      "idempotency_covered" => "幂等边界",
      "retry_covered" => "重试边界",
      "effect_boundaries_covered" => "副作用边界",
      "data_policy_covered" => "数据策略",
      "cost_policy_covered" => "费用策略"
    }.freeze
    IMPLEMENTATION_KIND_COPY = {
      "source_tree" => "源码树",
      "package" => "软件包",
      "container_image" => "容器镜像",
      "managed_service" => "托管服务"
    }.freeze

    attr_reader :errors, :envelope, :profile, :selection_proposal,
                :selection_confirmation, :payload_attestation, :effect_proposal,
                :effect_confirmation, :implementation_attestation,
                :input_digests, :implementation_attestation_file_sha256

    def initialize(root)
      @root = File.realpath(root)
      @errors = []
      reset_state
    end

    def preview_files(session_path, draft_path, compilation_proposal_path, compilation_confirmation_path, package_path, handoff_proposal_path, handoff_confirmation_path, envelope_path, profile_path, selection_proposal_path, selection_confirmation_path, payload_attestation_path, effect_proposal_path, effect_confirmation_path, implementation_attestation_path)
      errors.clear
      reset_state

      confirmation_preview = HandoffAdapterEffectAuthorizationConfirmationPreview.new(@root)
      confirmation_copy = confirmation_preview.preview_files(
        session_path,
        draft_path,
        compilation_proposal_path,
        compilation_confirmation_path,
        package_path,
        handoff_proposal_path,
        handoff_confirmation_path,
        envelope_path,
        profile_path,
        selection_proposal_path,
        selection_confirmation_path,
        payload_attestation_path,
        effect_proposal_path,
        effect_confirmation_path
      )
      errors.concat(confirmation_preview.errors)
      return nil unless confirmation_copy

      copy_confirmation_state(confirmation_preview)
      return nil unless validate_confirmed_authorization(effect_confirmation_path)

      document, bytes = load_yaml_file_with_bytes(implementation_attestation_path)
      return nil unless document

      @implementation_attestation = document
      @input_digests = confirmation_preview.input_digests.merge(
        "adapter_effect_authorization_confirmation_receipt_file_sha256" => confirmation_preview.confirmation_file_sha256
      )
      @implementation_attestation_file_sha256 = Digest::SHA256.hexdigest(bytes)
      return nil unless validate_schema(document, implementation_attestation_path)

      validate_binding(document, implementation_attestation_path)
      validate_review_provenance(document, implementation_attestation_path)
      validate_effect_contract(document, implementation_attestation_path)
      validate_contract_evidence(document, implementation_attestation_path)
      validate_overall_result(document, implementation_attestation_path)
      validate_time(document, implementation_attestation_path)
      validate_data_policy(document, implementation_attestation_path)
      return nil unless errors.empty?

      render_copy(document)
    end

    private

    def reset_state
      @envelope = nil
      @profile = nil
      @selection_proposal = nil
      @selection_confirmation = nil
      @payload_attestation = nil
      @effect_proposal = nil
      @effect_confirmation = nil
      @implementation_attestation = nil
      @input_digests = nil
      @implementation_attestation_file_sha256 = nil
    end

    def copy_confirmation_state(preview)
      @envelope = preview.envelope
      @profile = preview.profile
      @selection_proposal = preview.selection_proposal
      @selection_confirmation = preview.selection_confirmation
      @payload_attestation = preview.attestation
      @effect_proposal = preview.effect_proposal
      @effect_confirmation = preview.confirmation
    end

    def validate_confirmed_authorization(path)
      valid = effect_confirmation["confirmation_decision"] == "confirmed" &&
              effect_confirmation["effect_authorization_confirmed"] == true &&
              effect_confirmation["all_requested_effects_authorized"] == true
      return true if valid

      errors << "#{path}: Adapter Implementation Attestation requires confirmed exact effect authorization"
      false
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
    rescue SystemCallError, Psych::Exception => e
      errors << "#{path}: cannot load YAML (#{e.message})"
      [nil, nil]
    end

    def validate_schema(document, path)
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

    def validate_binding(document, path)
      expected = input_digests.merge(
        "package_id" => envelope["package_id"],
        "envelope_id" => envelope["envelope_id"],
        "adapter_profile_id" => profile["adapter_profile_id"],
        "adapter_selection_proposal_id" => selection_proposal["adapter_selection_proposal_id"],
        "adapter_selection_confirmation_id" => selection_confirmation["adapter_selection_confirmation_id"],
        "payload_data_attestation_id" => payload_attestation["payload_data_attestation_id"],
        "adapter_effect_authorization_proposal_id" => effect_proposal["adapter_effect_authorization_proposal_id"],
        "adapter_effect_authorization_confirmation_id" => effect_confirmation["adapter_effect_authorization_confirmation_id"],
        "envelope_delivery_state" => envelope["delivery_state"],
        "adapter_profile_status" => profile["status"],
        "adapter_selection_proposal_status" => selection_proposal.dig("confirmation", "status"),
        "selection_confirmation_decision" => selection_confirmation["confirmation_decision"],
        "adapter_selected" => selection_confirmation["adapter_selected"],
        "payload_data_attestation_completed" => payload_attestation["payload_data_attestation_completed"],
        "overall_data_compatibility" => payload_attestation["overall_data_compatibility"],
        "adapter_effect_authorization_proposal_status" => effect_proposal["proposal_status"],
        "effect_authorization_confirmation_decision" => effect_confirmation["confirmation_decision"],
        "effect_authorization_confirmed" => effect_confirmation["effect_authorization_confirmed"],
        "all_requested_effects_authorized" => effect_confirmation["all_requested_effects_authorized"],
        "recipient" => envelope["recipient"],
        "profile_declared_effects" => profile_declared_effects,
        "authorized_effects" => effect_confirmation["effect_authorizations_granted"],
        "retention_export_purpose_compatibility" => effect_confirmation["retention_export_purpose_compatibility"]
      )
      expected.each do |field, value|
        errors << "#{path}: #{field} does not match its attested source" unless document[field] == value
      end
    end

    def validate_review_provenance(document, path)
      reviewer_present = document["reviewer_ref"] != "not_applicable"
      scanner_present = document["scanner_ref"] != "not_applicable" && document["scanner_version"] != "not_applicable"
      valid = case document["review_method"]
              when "manual"
                reviewer_present && !scanner_present && document["scanner_ref"] == "not_applicable" && document["scanner_version"] == "not_applicable"
              when "automated"
                !reviewer_present && document["reviewer_ref"] == "not_applicable" && scanner_present
              when "hybrid"
                reviewer_present && scanner_present
              end
      return if valid

      errors << "#{path}: implementation review provenance must match manual, automated, or hybrid method"
    end

    def validate_effect_contract(document, path)
      declared = profile_declared_effects
      observed = document["implementation_observed_effects"]
      expected_missing = declared.reject { |effect| observed.include?(effect) }
      expected_undeclared = observed.reject { |effect| declared.include?(effect) }
      expected_conformance = expected_missing.empty? && expected_undeclared.empty? ? "conformant" : "nonconformant"

      unless document["missing_declared_effects"] == expected_missing
        errors << "#{path}: missing_declared_effects must be derived from Profile and observed implementation effects"
      end
      unless document["undeclared_effects_detected"] == expected_undeclared
        errors << "#{path}: undeclared_effects_detected must be derived from Profile and observed implementation effects"
      end
      unless document["profile_effect_conformance"] == expected_conformance
        errors << "#{path}: profile_effect_conformance must be derived from missing and undeclared effects"
      end
      unless canonical_effect_order?(observed) && canonical_effect_order?(document["undeclared_effects_detected"])
        errors << "#{path}: observed and undeclared effects must use canonical Profile order with other last"
      end
    end

    def validate_contract_evidence(document, path)
      expected = document["contract_test_status"] == "passed" && COVERAGE_FIELDS.all? { |field| document[field] == true }
      compatibility = expected ? "compatible" : "incompatible"
      return if document["provider_contract_compatibility"] == compatibility

      errors << "#{path}: provider_contract_compatibility must be derived from submitted test status and coverage declarations"
    end

    def validate_overall_result(document, path)
      expected = document["profile_effect_conformance"] == "conformant" &&
                 document["provider_contract_compatibility"] == "compatible"
      compatibility = expected ? "compatible" : "incompatible"
      return if document["overall_implementation_compatibility"] == compatibility

      errors << "#{path}: overall_implementation_compatibility must combine effect and contract evidence"
    end

    def validate_time(document, path)
      confirmation_time = parse_time(effect_confirmation["captured_at"])
      review_time = parse_time(document["reviewed_at"])
      return unless confirmation_time && review_time && review_time < confirmation_time

      errors << "#{path}: Adapter Implementation Attestation cannot predate effect authorization confirmation"
    end

    def validate_data_policy(document, path)
      source_rank = CLASSIFICATION_RANK[effect_confirmation["data_classification"]]
      attestation_rank = CLASSIFICATION_RANK[document["data_classification"]]
      if source_rank && attestation_rank && attestation_rank < source_rank
        errors << "#{path}: Adapter Implementation Attestation data classification cannot downgrade its source"
      end
    end

    def profile_declared_effects
      HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |effect|
        profile.dig("effects", effect) == true
      end
    end

    def canonical_effect_order?(effects)
      order = HandoffAdapterSelectionPreview::EFFECT_FIELDS + ["other"]
      effects == order.select { |effect| effects.include?(effect) }
    end

    def render_copy(document)
      if document["overall_implementation_compatibility"] == "compatible"
        render_compatible_copy(document)
      else
        render_incompatible_copy(document)
      end
    end

    def render_compatible_copy(document)
      lines = [
        "# Adapter 实现声明符合 Profile，仍未达到运行时就绪",
        "",
        "已完成对一个精确实现身份及其 provider contract-test 证据的声明式审核。PMind 预演没有装载实现，也没有运行该测试套件。",
        "",
        "## 审核结果",
        "",
        "- 已选择的 Adapter：#{MarkdownSafety.inline(profile.fetch("display_name"))}",
        "- 实现类型：#{IMPLEMENTATION_KIND_COPY.fetch(document.fetch("implementation_kind"))}",
        "- 审核方式：#{REVIEW_METHOD_COPY.fetch(document.fetch("review_method"))}",
        "- Profile 副作用边界：符合",
        "- provider contract-test 证据：声明通过且七项覆盖完整",
        "- 实现兼容性：通过"
      ]
      append_effects(lines, document)
      append_runtime_gates(lines)
      lines.concat([
                     "",
                     "## 下一步",
                     "",
                     "建立独立 Adapter Runtime Readiness Attestation，核验凭据引用、provider 健康与运行时条件；之后仍需单独 dispatch 确认。本 Attestation 不能启动 Adapter。"
                   ])
      lines.join("\n")
    end

    def render_incompatible_copy(document)
      lines = [
        "# Adapter 实现声明不符合要求，运行时路径已阻断",
        "",
        "实现审核已完成，但提交的声明至少存在一项 Profile 副作用或 provider contract-test 不兼容。PMind 预演没有装载实现，也没有运行测试套件。",
        "",
        "## 阻断原因",
        ""
      ]
      unless document["missing_declared_effects"].empty?
        lines << "- 缺少 Profile 声明的具名副作用实现"
      end
      unless document["undeclared_effects_detected"].empty?
        lines << "- 发现 Profile 未声明的实现副作用"
      end
      lines << "- provider contract-test 证据声明失败" if document["contract_test_status"] == "failed"
      incomplete = COVERAGE_FIELDS.reject { |field| document[field] == true }
      incomplete.each { |field| lines << "- provider contract-test 未覆盖：#{COVERAGE_COPY.fetch(field)}" }
      append_runtime_gates(lines)
      lines.concat([
                     "",
                     "请修复实现或重新建立受影响的 Profile、授权与证明链；当前不得进入 Runtime Readiness 或 dispatch。"
                   ])
      lines.join("\n")
    end

    def append_effects(lines, document)
      lines.concat(["", "## 已证明符合且已具名授权的副作用", ""])
      if document["authorized_effects"].empty?
        lines << "- 零副作用集合：符合；仍不可执行"
      else
        document["authorized_effects"].each do |effect|
          lines << "- #{HandoffAdapterSelectionPreview::EFFECT_COPY.fetch(effect)}：实现声明符合且已具名授权；仍不可执行"
        end
      end
    end

    def append_runtime_gates(lines)
      lines.concat([
                     "",
                     "## 仍未满足的运行时门禁",
                     "",
                     "- 实现文件：本预演未装载或独立核验",
                     "- provider contract test：本预演未执行，只校验提交的证据声明",
                     "- provider 凭据：未核验",
                     "- provider 健康：未核验",
                     "- runtime readiness：未核验",
                     "- 当前 effects executable：否",
                     "- 当前 dispatch：未授权"
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
  if ARGV.length != 15
    warn "Usage: ruby scripts/preview_handoff_adapter_implementation_attestation.rb SESSION_REVISION.yaml DRAFT_PACKAGE.yaml COMPILATION_PROPOSAL.yaml COMPILATION_CONFIRMATION.yaml FINAL_PACKAGE.yaml HANDOFF_PROPOSAL.yaml HANDOFF_CONFIRMATION.yaml HANDOFF_ENVELOPE.yaml ADAPTER_PROFILE.yaml ADAPTER_SELECTION_PROPOSAL.yaml ADAPTER_SELECTION_CONFIRMATION.yaml PAYLOAD_DATA_ATTESTATION.yaml ADAPTER_EFFECT_AUTHORIZATION_PROPOSAL.yaml ADAPTER_EFFECT_AUTHORIZATION_CONFIRMATION.yaml ADAPTER_IMPLEMENTATION_ATTESTATION.yaml"
    exit 1
  end

  project_root = File.expand_path("..", __dir__)
  preview = PMind::HandoffAdapterImplementationAttestationPreview.new(project_root)
  copy = preview.preview_files(*ARGV)
  if copy
    puts copy
    exit 0
  end

  warn preview.errors.join("\n")
  exit 1
end
