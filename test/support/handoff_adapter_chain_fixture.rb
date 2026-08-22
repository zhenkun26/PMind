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
