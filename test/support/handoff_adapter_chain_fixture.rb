# frozen_string_literal: true

require "digest"
require "yaml"

class HandoffAdapterChainFixture
  def initialize(root)
    @root = root
  end

  def write_ten_files(directory, envelope_classification: nil)
    session, package, compilation_proposal, compilation_confirmation,
      handoff_proposal, handoff_confirmation, profile, proposal = fixture_documents
    paths = artifact_paths(directory)

    write_yaml(paths.fetch(0), session)
    write_yaml(paths.fetch(1), package)
    compilation_proposal["source_session_file_sha256"] = digest(paths.fetch(0))
    compilation_proposal["draft_package_file_sha256"] = digest(paths.fetch(1))
    write_yaml(paths.fetch(2), compilation_proposal)
    compilation_confirmation["source_session_file_sha256"] = digest(paths.fetch(0))
    compilation_confirmation["draft_package_file_sha256"] = digest(paths.fetch(1))
    compilation_confirmation["compilation_proposal_file_sha256"] = digest(paths.fetch(2))
    write_yaml(paths.fetch(3), compilation_confirmation)

    create_final_package(paths)
    final_package = load_yaml(paths.fetch(4))
    handoff_proposal["package_id"] = final_package["package_id"]
    handoff_proposal["final_package_file_sha256"] = digest(paths.fetch(4))
    handoff_proposal["package_handoff_ready"] = final_package.dig("handoff", "ready")
    handoff_proposal["recipient"] = final_package.dig("handoff", "recipient")
    write_yaml(paths.fetch(5), handoff_proposal)

    bind_handoff_confirmation(paths, final_package, handoff_proposal, handoff_confirmation)
    handoff_confirmation["data_classification"] = envelope_classification if envelope_classification
    write_yaml(paths.fetch(6), handoff_confirmation)
    create_handoff_envelope(paths)
    write_yaml(paths.fetch(8), profile)
    write_yaml(paths.fetch(9), proposal)
    refresh_proposal_bindings(paths)
    paths
  end

  def write_eleven_files(directory, envelope_classification: nil)
    paths = write_ten_files(directory, envelope_classification: envelope_classification)
    confirmation_path = File.join(directory, "adapter-selection-confirmation.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-adapter-selection-confirmation-receipt-valid.yaml")
    write_yaml(confirmation_path, load_yaml(fixture_path))
    paths << confirmation_path
    refresh_selection_confirmation_bindings(paths)
    paths
  end

  def write_twelve_files(directory, envelope_classification: nil)
    paths = write_eleven_files(directory, envelope_classification: envelope_classification)
    attestation_path = File.join(directory, "payload-data-attestation.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-payload-data-attestation-valid.yaml")
    write_yaml(attestation_path, load_yaml(fixture_path))
    paths << attestation_path
    refresh_payload_data_attestation_bindings(paths)
    paths
  end

  def write_thirteen_files(directory, envelope_classification: nil)
    paths = write_twelve_files(directory, envelope_classification: envelope_classification)
    proposal_path = File.join(directory, "adapter-effect-authorization-proposal.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-adapter-effect-authorization-proposal-valid.yaml")
    write_yaml(proposal_path, load_yaml(fixture_path))
    paths << proposal_path
    refresh_adapter_effect_authorization_proposal_bindings(paths)
    paths
  end

  def write_fourteen_files(directory, envelope_classification: nil)
    paths = write_thirteen_files(directory, envelope_classification: envelope_classification)
    confirmation_path = File.join(directory, "adapter-effect-authorization-confirmation.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-adapter-effect-authorization-confirmation-receipt-valid.yaml")
    write_yaml(confirmation_path, load_yaml(fixture_path))
    paths << confirmation_path
    refresh_effect_authorization_confirmation_bindings(paths)
    paths
  end

  def write_fifteen_files(directory, envelope_classification: nil)
    paths = write_fourteen_files(directory, envelope_classification: envelope_classification)
    attestation_path = File.join(directory, "adapter-implementation-attestation.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-adapter-implementation-attestation-valid.yaml")
    write_yaml(attestation_path, load_yaml(fixture_path))
    paths << attestation_path
    refresh_adapter_implementation_attestation_bindings(paths)
    paths
  end

  def write_sixteen_files(directory, envelope_classification: nil)
    paths = write_fifteen_files(directory, envelope_classification: envelope_classification)
    attestation_path = File.join(directory, "adapter-runtime-readiness-attestation.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-adapter-runtime-readiness-attestation-valid.yaml")
    write_yaml(attestation_path, load_yaml(fixture_path))
    paths << attestation_path
    refresh_adapter_runtime_readiness_attestation_bindings(paths)
    paths
  end

  def write_seventeen_files(directory, envelope_classification: nil)
    paths = write_sixteen_files(directory, envelope_classification: envelope_classification)
    proposal_path = File.join(directory, "adapter-dispatch-proposal.yaml")
    fixture_path = File.join(@root, "test/fixtures/handoff-adapter-dispatch-proposal-valid.yaml")
    write_yaml(proposal_path, load_yaml(fixture_path))
    paths << proposal_path
    refresh_adapter_dispatch_proposal_bindings(paths)
    paths
  end

  def refresh_proposal_bindings(paths)
    envelope = load_yaml(paths.fetch(7))
    profile = load_yaml(paths.fetch(8))
    proposal = load_yaml(paths.fetch(9))
    proposal["envelope_id"] = envelope["envelope_id"]
    proposal["handoff_envelope_file_sha256"] = digest(paths.fetch(7))
    proposal["envelope_delivery_state"] = envelope["delivery_state"]
    proposal["recipient"] = envelope["recipient"]
    proposal["adapter_profile_id"] = profile["adapter_profile_id"]
    proposal["adapter_profile_file_sha256"] = digest(paths.fetch(8))
    proposal["data_classification"] = envelope["data_classification"]
    write_yaml(paths.fetch(9), proposal)
  end

  def refresh_profile_digest(paths)
    proposal = load_yaml(paths.fetch(9))
    proposal["adapter_profile_file_sha256"] = digest(paths.fetch(8))
    write_yaml(paths.fetch(9), proposal)
  end

  def refresh_selection_confirmation_bindings(paths)
    preview = PMind::HandoffAdapterSelectionPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(10))

    receipt = load_yaml(paths.fetch(10))
    preview.input_digests.each { |field, digest_value| receipt[field] = digest_value }
    receipt["envelope_id"] = preview.envelope["envelope_id"]
    receipt["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    receipt["adapter_selection_proposal_id"] = preview.proposal["adapter_selection_proposal_id"]
    receipt["envelope_delivery_state"] = preview.envelope["delivery_state"]
    receipt["adapter_profile_status"] = preview.profile["status"]
    receipt["adapter_selection_proposal_status"] = preview.proposal.dig("confirmation", "status")
    receipt["recipient"] = preview.envelope["recipient"]
    receipt["data_classification"] = preview.proposal["data_classification"]
    write_yaml(paths.fetch(10), receipt)
  end

  def refresh_payload_data_attestation_bindings(paths)
    preview = PMind::HandoffAdapterSelectionConfirmationPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(11))

    document = load_yaml(paths.fetch(11))
    preview.input_digests.each { |field, digest_value| document[field] = digest_value }
    document["adapter_selection_confirmation_receipt_file_sha256"] = preview.confirmation_file_sha256
    document["package_id"] = preview.envelope["package_id"]
    document["envelope_id"] = preview.envelope["envelope_id"]
    document["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    document["adapter_selection_proposal_id"] = preview.proposal["adapter_selection_proposal_id"]
    document["adapter_selection_confirmation_id"] = preview.confirmation["adapter_selection_confirmation_id"]
    document["envelope_delivery_state"] = preview.envelope["delivery_state"]
    document["adapter_profile_status"] = preview.profile["status"]
    document["adapter_selection_proposal_status"] = preview.proposal.dig("confirmation", "status")
    document["selection_confirmation_decision"] = preview.confirmation["confirmation_decision"]
    document["adapter_selected"] = preview.confirmation["adapter_selected"]
    document["recipient"] = preview.envelope["recipient"]
    document["adapter_maximum_data_classification"] = preview.profile.dig("data_policy", "maximum_data_classification")
    document["adapter_personal_data_handling"] = preview.profile.dig("data_policy", "personal_data_handling")
    document["adapter_secret_handling"] = preview.profile.dig("data_policy", "secret_handling")
    document["data_classification"] = preview.confirmation["data_classification"]
    write_yaml(paths.fetch(11), document)
  end

  def refresh_adapter_effect_authorization_proposal_bindings(paths)
    preview = PMind::HandoffPayloadDataAttestationPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(12))

    proposal = load_yaml(paths.fetch(12))
    preview.input_digests.each { |field, digest_value| proposal[field] = digest_value }
    proposal["payload_data_attestation_file_sha256"] = preview.attestation_file_sha256
    proposal["package_id"] = preview.envelope["package_id"]
    proposal["envelope_id"] = preview.envelope["envelope_id"]
    proposal["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    proposal["adapter_selection_proposal_id"] = preview.proposal["adapter_selection_proposal_id"]
    proposal["adapter_selection_confirmation_id"] = preview.selection_confirmation["adapter_selection_confirmation_id"]
    proposal["payload_data_attestation_id"] = preview.attestation["payload_data_attestation_id"]
    proposal["envelope_delivery_state"] = preview.envelope["delivery_state"]
    proposal["adapter_profile_status"] = preview.profile["status"]
    proposal["adapter_selection_proposal_status"] = preview.proposal.dig("confirmation", "status")
    proposal["selection_confirmation_decision"] = preview.selection_confirmation["confirmation_decision"]
    proposal["adapter_selected"] = preview.selection_confirmation["adapter_selected"]
    proposal["payload_data_attestation_completed"] = preview.attestation["payload_data_attestation_completed"]
    proposal["overall_data_compatibility"] = preview.attestation["overall_data_compatibility"]
    proposal["recipient"] = preview.envelope["recipient"]
    proposal["data_classification"] = preview.attestation["data_classification"]
    write_yaml(paths.fetch(12), proposal)
  end

  def refresh_effect_authorization_confirmation_bindings(paths)
    preview = PMind::HandoffAdapterEffectAuthorizationPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(13))

    receipt = load_yaml(paths.fetch(13))
    preview.input_digests.each { |field, digest_value| receipt[field] = digest_value }
    receipt["adapter_effect_authorization_proposal_file_sha256"] = preview.effect_proposal_file_sha256
    receipt["package_id"] = preview.envelope["package_id"]
    receipt["envelope_id"] = preview.envelope["envelope_id"]
    receipt["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    receipt["adapter_selection_proposal_id"] = preview.selection_proposal["adapter_selection_proposal_id"]
    receipt["adapter_selection_confirmation_id"] = preview.selection_confirmation["adapter_selection_confirmation_id"]
    receipt["payload_data_attestation_id"] = preview.attestation["payload_data_attestation_id"]
    receipt["adapter_effect_authorization_proposal_id"] = preview.effect_proposal["adapter_effect_authorization_proposal_id"]
    receipt["envelope_delivery_state"] = preview.envelope["delivery_state"]
    receipt["adapter_profile_status"] = preview.profile["status"]
    receipt["adapter_selection_proposal_status"] = preview.selection_proposal.dig("confirmation", "status")
    receipt["selection_confirmation_decision"] = preview.selection_confirmation["confirmation_decision"]
    receipt["adapter_selected"] = preview.selection_confirmation["adapter_selected"]
    receipt["payload_data_attestation_completed"] = preview.attestation["payload_data_attestation_completed"]
    receipt["overall_data_compatibility"] = preview.attestation["overall_data_compatibility"]
    receipt["adapter_effect_authorization_proposal_status"] = preview.effect_proposal["proposal_status"]
    receipt["recipient"] = preview.envelope["recipient"]
    receipt["requested_effect_authorizations"] = preview.effect_proposal["requested_effect_authorizations"]
    receipt["cost_disclosure_before_dispatch_required"] = preview.effect_proposal["cost_disclosure_required"]
    receipt["data_classification"] = preview.effect_proposal["data_classification"]
    write_yaml(paths.fetch(13), receipt)
  end

  def refresh_adapter_implementation_attestation_bindings(paths)
    preview = PMind::HandoffAdapterEffectAuthorizationConfirmationPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(14))

    document = load_yaml(paths.fetch(14))
    preview.input_digests.each { |field, digest_value| document[field] = digest_value }
    document["adapter_effect_authorization_confirmation_receipt_file_sha256"] = preview.confirmation_file_sha256
    document["package_id"] = preview.envelope["package_id"]
    document["envelope_id"] = preview.envelope["envelope_id"]
    document["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    document["adapter_selection_proposal_id"] = preview.selection_proposal["adapter_selection_proposal_id"]
    document["adapter_selection_confirmation_id"] = preview.selection_confirmation["adapter_selection_confirmation_id"]
    document["payload_data_attestation_id"] = preview.attestation["payload_data_attestation_id"]
    document["adapter_effect_authorization_proposal_id"] = preview.effect_proposal["adapter_effect_authorization_proposal_id"]
    document["adapter_effect_authorization_confirmation_id"] = preview.confirmation["adapter_effect_authorization_confirmation_id"]
    document["envelope_delivery_state"] = preview.envelope["delivery_state"]
    document["adapter_profile_status"] = preview.profile["status"]
    document["adapter_selection_proposal_status"] = preview.selection_proposal.dig("confirmation", "status")
    document["selection_confirmation_decision"] = preview.selection_confirmation["confirmation_decision"]
    document["adapter_selected"] = preview.selection_confirmation["adapter_selected"]
    document["payload_data_attestation_completed"] = preview.attestation["payload_data_attestation_completed"]
    document["overall_data_compatibility"] = preview.attestation["overall_data_compatibility"]
    document["adapter_effect_authorization_proposal_status"] = preview.effect_proposal["proposal_status"]
    document["effect_authorization_confirmation_decision"] = preview.confirmation["confirmation_decision"]
    document["effect_authorization_confirmed"] = preview.confirmation["effect_authorization_confirmed"]
    document["all_requested_effects_authorized"] = preview.confirmation["all_requested_effects_authorized"]
    document["recipient"] = preview.envelope["recipient"]
    declared_effects = PMind::HandoffAdapterSelectionPreview::EFFECT_FIELDS.select do |effect|
      preview.profile.dig("effects", effect) == true
    end
    document["profile_declared_effects"] = declared_effects.dup
    document["authorized_effects"] = preview.confirmation["effect_authorizations_granted"].dup
    document["implementation_observed_effects"] = declared_effects.dup
    document["missing_declared_effects"] = []
    document["undeclared_effects_detected"] = []
    document["data_classification"] = preview.confirmation["data_classification"]
    write_yaml(paths.fetch(14), document)
  end

  def refresh_adapter_runtime_readiness_attestation_bindings(paths)
    preview = PMind::HandoffAdapterImplementationAttestationPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(15))

    document = load_yaml(paths.fetch(15))
    preview.input_digests.each { |field, digest_value| document[field] = digest_value }
    document["adapter_implementation_attestation_file_sha256"] = preview.implementation_attestation_file_sha256
    document["package_id"] = preview.envelope["package_id"]
    document["envelope_id"] = preview.envelope["envelope_id"]
    document["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    document["adapter_selection_proposal_id"] = preview.selection_proposal["adapter_selection_proposal_id"]
    document["adapter_selection_confirmation_id"] = preview.selection_confirmation["adapter_selection_confirmation_id"]
    document["payload_data_attestation_id"] = preview.payload_attestation["payload_data_attestation_id"]
    document["adapter_effect_authorization_proposal_id"] = preview.effect_proposal["adapter_effect_authorization_proposal_id"]
    document["adapter_effect_authorization_confirmation_id"] = preview.effect_confirmation["adapter_effect_authorization_confirmation_id"]
    document["adapter_implementation_attestation_id"] = preview.implementation_attestation["adapter_implementation_attestation_id"]
    document["envelope_delivery_state"] = preview.envelope["delivery_state"]
    document["adapter_profile_status"] = preview.profile["status"]
    document["adapter_selection_proposal_status"] = preview.selection_proposal.dig("confirmation", "status")
    document["selection_confirmation_decision"] = preview.selection_confirmation["confirmation_decision"]
    document["adapter_selected"] = preview.selection_confirmation["adapter_selected"]
    document["payload_data_attestation_completed"] = preview.payload_attestation["payload_data_attestation_completed"]
    document["overall_data_compatibility"] = preview.payload_attestation["overall_data_compatibility"]
    document["adapter_effect_authorization_proposal_status"] = preview.effect_proposal["proposal_status"]
    document["effect_authorization_confirmation_decision"] = preview.effect_confirmation["confirmation_decision"]
    document["effect_authorization_confirmed"] = preview.effect_confirmation["effect_authorization_confirmed"]
    document["all_requested_effects_authorized"] = preview.effect_confirmation["all_requested_effects_authorized"]
    document["adapter_implementation_attestation_completed"] = preview.implementation_attestation["adapter_implementation_attestation_completed"]
    document["overall_implementation_compatibility"] = preview.implementation_attestation["overall_implementation_compatibility"]
    document["recipient"] = preview.envelope["recipient"]
    %w[implementation_kind implementation_ref implementation_version declared_implementation_sha256].each do |field|
      document[field] = preview.implementation_attestation[field]
    end
    document["profile_declared_effects"] = preview.implementation_attestation["profile_declared_effects"].dup
    document["authorized_effects"] = preview.implementation_attestation["authorized_effects"].dup
    remote_effects = %w[network_access notification external_service_write cost_incurred production_data_access]
    credential_effects = %w[notification external_service_write cost_incurred production_data_access]
    credential_required = (document["authorized_effects"] & credential_effects).any?
    health_required = (document["authorized_effects"] & remote_effects).any?
    if credential_required
      document["credential_requirement"] = "required"
      document["credential_reference_status"] = "available"
      document["credential_ref"] = "synthetic-secret-manager-ref-001"
      document["credential_scope_compatibility"] = "compatible"
      document["credential_expiry_status"] = "valid"
      document["credential_readiness"] = "ready"
    else
      document["credential_requirement"] = "not_required"
      document["credential_reference_status"] = "not_applicable"
      document["credential_ref"] = "not_applicable"
      document["credential_scope_compatibility"] = "not_applicable"
      document["credential_expiry_status"] = "not_applicable"
      document["credential_readiness"] = "not_applicable"
    end
    if health_required
      document["provider_health_check_requirement"] = "required"
      document["provider_health_evidence_status"] = "healthy"
      document["provider_health_evidence_ref"] = "synthetic-health-evidence-001"
      document["provider_health_evidence_sha256"] = "c" * 64
      document["provider_health_checked_at"] = "2026-08-23T09:30:00+08:00"
      document["provider_health_readiness"] = "ready"
    else
      document["provider_health_check_requirement"] = "not_required"
      document["provider_health_evidence_status"] = "not_applicable"
      document["provider_health_evidence_ref"] = "not_applicable"
      document["provider_health_evidence_sha256"] = "not_applicable"
      document["provider_health_checked_at"] = "not_applicable"
      document["provider_health_readiness"] = "not_applicable"
    end
    cost_required = document["authorized_effects"].include?("cost_incurred")
    document["cost_limit_authorization_required"] = cost_required
    document["dispatch_cost_gate_status"] = cost_required ? "pending_authorization" : "not_applicable"
    document["data_classification"] = preview.implementation_attestation["data_classification"]
    write_yaml(paths.fetch(15), document)
  end

  def refresh_adapter_dispatch_proposal_bindings(paths)
    preview = PMind::HandoffAdapterRuntimeReadinessAttestationPreview.new(@root)
    raise preview.errors.join("\n") unless preview.preview_files(*paths.first(16))

    document = load_yaml(paths.fetch(16))
    preview.input_digests.each { |field, digest_value| document[field] = digest_value }
    document["adapter_runtime_readiness_attestation_file_sha256"] = preview.runtime_attestation_file_sha256
    document["package_id"] = preview.envelope["package_id"]
    document["envelope_id"] = preview.envelope["envelope_id"]
    document["adapter_profile_id"] = preview.profile["adapter_profile_id"]
    document["adapter_selection_proposal_id"] = preview.selection_proposal["adapter_selection_proposal_id"]
    document["adapter_selection_confirmation_id"] = preview.selection_confirmation["adapter_selection_confirmation_id"]
    document["payload_data_attestation_id"] = preview.payload_attestation["payload_data_attestation_id"]
    document["adapter_effect_authorization_proposal_id"] = preview.effect_proposal["adapter_effect_authorization_proposal_id"]
    document["adapter_effect_authorization_confirmation_id"] = preview.effect_confirmation["adapter_effect_authorization_confirmation_id"]
    document["adapter_implementation_attestation_id"] = preview.implementation_attestation["adapter_implementation_attestation_id"]
    document["adapter_runtime_readiness_attestation_id"] = preview.runtime_attestation["adapter_runtime_readiness_attestation_id"]
    document["envelope_delivery_state"] = preview.envelope["delivery_state"]
    document["adapter_profile_status"] = preview.profile["status"]
    document["adapter_selection_proposal_status"] = preview.selection_proposal.dig("confirmation", "status")
    document["selection_confirmation_decision"] = preview.selection_confirmation["confirmation_decision"]
    document["adapter_selected"] = preview.selection_confirmation["adapter_selected"]
    document["payload_data_attestation_completed"] = preview.payload_attestation["payload_data_attestation_completed"]
    document["overall_data_compatibility"] = preview.payload_attestation["overall_data_compatibility"]
    document["adapter_effect_authorization_proposal_status"] = preview.effect_proposal["proposal_status"]
    document["effect_authorization_confirmation_decision"] = preview.effect_confirmation["confirmation_decision"]
    document["effect_authorization_confirmed"] = preview.effect_confirmation["effect_authorization_confirmed"]
    document["all_requested_effects_authorized"] = preview.effect_confirmation["all_requested_effects_authorized"]
    document["adapter_implementation_attestation_completed"] = preview.implementation_attestation["adapter_implementation_attestation_completed"]
    document["overall_implementation_compatibility"] = preview.implementation_attestation["overall_implementation_compatibility"]
    document["adapter_runtime_readiness_attestation_completed"] = preview.runtime_attestation["adapter_runtime_readiness_attestation_completed"]
    document["runtime_evidence_reviewed"] = preview.runtime_attestation["runtime_evidence_reviewed"]
    document["overall_runtime_readiness"] = preview.runtime_attestation["overall_runtime_readiness"]
    document["recipient"] = preview.envelope["recipient"]
    document["adapter_key"] = preview.profile["adapter_key"]
    %w[implementation_kind implementation_ref implementation_version declared_implementation_sha256].each do |field|
      document[field] = preview.implementation_attestation[field]
    end
    document["runtime_environment_kind"] = preview.runtime_attestation["runtime_environment_kind"]
    document["runtime_environment_ref"] = preview.runtime_attestation["runtime_environment_ref"]
    document["delivery_mode"] = preview.profile.dig("capabilities", "delivery_mode")
    document["receipt_mode"] = preview.profile.dig("capabilities", "receipt_mode")
    document["adapter_idempotency_supported"] = preview.profile.dig("capabilities", "idempotency", "supported")
    document["adapter_idempotency_key_source"] = preview.profile.dig("capabilities", "idempotency", "key_source")
    document["adapter_retry_mode"] = preview.profile.dig("capabilities", "retry", "mode")
    document["adapter_maximum_attempts"] = preview.profile.dig("capabilities", "retry", "maximum_attempts")
    document["authorized_effects"] = preview.runtime_attestation["authorized_effects"].dup
    document["dispatch_payload_file_sha256"] = preview.input_digests["handoff_envelope_file_sha256"]
    document["dispatch_destination_kind"] = PMind::HandoffAdapterDispatchProposalPreview::DESTINATION_KIND.fetch(document["delivery_mode"])
    document["dispatch_destination_ref"] = "synthetic-dispatch-destination-001"
    document["dispatch_attempt_limit"] = 1
    health_required = preview.runtime_attestation["provider_health_check_requirement"] == "required"
    document["provider_health_freshness_requirement"] = health_required ? "required" : "not_required"
    document["maximum_health_evidence_age_seconds"] = health_required ? 3600 : 0
    document["provider_health_evidence_freshness"] = health_required ? "current" : "not_applicable"
    cost_required = document["authorized_effects"].include?("cost_incurred")
    document["cost_ceiling_required"] = cost_required
    document["cost_ceiling_amount"] = cost_required ? "10.00" : "not_applicable"
    document["cost_ceiling_currency"] = cost_required ? "USD" : "not_applicable"
    document["cost_limit_authorization_status"] = cost_required ? "pending_confirmation" : "not_applicable"
    stop_conditions = %w[
      source_bytes_changed
      authorization_changed
      runtime_readiness_changed
      proposal_not_yet_valid
      proposal_expired
      idempotency_conflict
      unlisted_effect_requested
      delivery_failure
    ]
    stop_conditions << "credential_not_ready" if preview.runtime_attestation["credential_requirement"] == "required"
    stop_conditions << "provider_health_not_current" if health_required
    stop_conditions << "cost_ceiling_would_be_exceeded" if cost_required
    stop_conditions << "receipt_failure" unless document["receipt_mode"] == "none"
    order = PMind::HandoffAdapterDispatchProposalPreview::STOP_CONDITION_ORDER
    document["stop_conditions"] = order.select { |condition| stop_conditions.include?(condition) }
    document["data_classification"] = preview.runtime_attestation["data_classification"]
    document["idempotency_key_sha256"] = PMind::HandoffAdapterDispatchProposalPreview.derived_idempotency_key(document)
    write_yaml(paths.fetch(16), document)
  end

  def load_yaml(path)
    YAML.safe_load(
      File.read(path),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def write_yaml(path, document)
    File.open(path, "wb", 0o600) { |file| file.write(YAML.dump(document)) }
  end

  private

  def fixture_documents
    fixture_paths.map { |path| load_yaml(path) }
  end

  def fixture_paths
    %w[
      clarification-session-revision-ready.yaml
      prompt-package-valid.yaml
      prompt-package-compilation-proposal-valid.yaml
      prompt-package-compilation-confirmation-receipt-valid.yaml
      handoff-proposal-valid.yaml
      handoff-confirmation-receipt-valid.yaml
      handoff-adapter-profile-valid.yaml
      handoff-adapter-selection-proposal-valid.yaml
    ].map { |name| File.join(@root, "test/fixtures", name) }
  end

  def artifact_paths(directory)
    %w[
      session-revision.yaml
      draft-package.yaml
      compilation-proposal.yaml
      compilation-confirmation.yaml
      final-package.yaml
      handoff-proposal.yaml
      handoff-confirmation.yaml
      handoff-envelope.yaml
      adapter-profile.yaml
      adapter-selection-proposal.yaml
    ].map { |name| File.join(directory, name) }
  end

  def create_final_package(paths)
    creator = PMind::PromptPackageCreator.new(@root)
    return if creator.create_files(*paths.first(4), paths.fetch(4))

    raise creator.errors.join("\n")
  end

  def bind_handoff_confirmation(paths, final_package, handoff_proposal, confirmation)
    fields = %w[
      source_session_file_sha256
      draft_package_file_sha256
      compilation_proposal_file_sha256
      compilation_confirmation_receipt_file_sha256
      final_package_file_sha256
      handoff_proposal_file_sha256
    ]
    paths.first(6).zip(fields).each { |source_path, field| confirmation[field] = digest(source_path) }
    confirmation["package_id"] = final_package["package_id"]
    confirmation["handoff_proposal_id"] = handoff_proposal["handoff_proposal_id"]
    confirmation["package_handoff_ready"] = final_package.dig("handoff", "ready")
    confirmation["recipient"] = final_package.dig("handoff", "recipient")
    confirmation["handoff_proposal_status"] = handoff_proposal.dig("confirmation", "status")
  end

  def create_handoff_envelope(paths)
    creator = PMind::HandoffEnvelopeCreator.new(@root)
    return if creator.create_files(*paths.first(7), paths.fetch(7))

    raise creator.errors.join("\n")
  end

  def digest(path)
    Digest::SHA256.file(path).hexdigest
  end
end
