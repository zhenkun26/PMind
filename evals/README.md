# PMind Eval Baseline

- Current case schema: `evals/schema/case-v0.yaml` (`0.2.0`)
- Current acceptance-result schema: `evals/schema/acceptance-result-v0.yaml` (`0.1.0`)
- Current rubric: `evals/rubrics/first-pass-success-v0.md` (`0.1.0`)
- Seed set: 10 synthetic, ready, unrun cases under `evals/cases/seed/`
- Calibration fixtures: 3 synthetic, executable fixtures under `evals/fixtures/`
- Calibration: `evals/calibration/wave-01.yaml` remains blocked until roles,
  executor settings, and isolated arm workspaces are ready
- Runtime framework: intentionally not selected

PMind will be evaluated by downstream delivery outcomes, not by whether an
optimized prompt sounds polished.

## Initial experiment

Collect at least 30 paired cases: 10 synthetic calibration cases followed by
20 real, previously unsolved tasks. For each case preserve:

- raw Intent and target Downstream Executor;
- baseline handoff without PMind;
- Clarifications and Evidence used by PMind;
- generated Prompt Package;
- downstream output and human corrections;
- latency, model / search cost, and number of clarification and rework rounds;
- acceptance result and failure reason.

The experiment is paired:

- baseline receives the immutable raw Intent;
- PMind receives a Prompt Package produced under `docs/product/` contracts;
- both arms use the same executor, workspace revision, tools and time policy;
- a case facilitator retains the oracle and answers only questions actually asked;
- the executor never receives oracle fields or the other arm's result.

## Primary metrics

- First-pass Delivery Success;
- material clarification and rework reduction;
- time from Intent to Handoff;
- Evidence citation coverage and validity;
- acceptance-criterion pass rate;
- user acceptance, cost, and latency.

## Case quality rules

- Inputs must be real or explicitly labeled synthetic.
- Expected outcomes must be independently defined, not copied from model
  output.
- Facts, judgement rubrics, and safety requirements are scored separately.
- Model, prompt, Skill, Reference, and dataset versions must be recorded.
- Failed and ambiguous cases remain in the dataset as regression evidence.

## Current assets

- `docs/product/prompt-package-v0.md`: semantic Handoff contract;
- `schemas/prompt-package-v0.yaml`: machine-readable Prompt Package structure and Handoff authorization contract;
- `docs/product/clarification-policy-v0.md`: gap and stopping policy;
- `docs/product/clarification-copy-v0.md`: five-state user-facing copy and disclosure contract;
- `docs/product/clarification-answer-receipt-v0.md`: immutable raw-answer capture, current-round binding, and confirmation-copy contract;
- `schemas/clarification-answer-receipt-v0.yaml`: machine-readable Answer Receipt structure and data declaration;
- `docs/product/clarification-revision-proposal-v0.md`: in-memory Session revision, state-transition, and user-confirmation contract;
- `schemas/clarification-revision-proposal-v0.yaml`: machine-readable answer normalization, gap/knowledge delta, and candidate Compile Gate structure;
- `docs/product/clarification-confirmation-receipt-v0.md`: exact-file choice capture, safe outcome copy, and no-overwrite revision creation contract;
- `schemas/clarification-confirmation-receipt-v0.yaml`: machine-readable confirm/modify/reject choice, source-file digests, privacy declarations, and creation authorization;
- `docs/product/clarification-revision-lineage-v0.md`: persisted revision replay, deterministic content comparison, and safe audit-copy contract;
- `docs/product/prompt-package-compilation-proposal-v0.md`: exact ready-revision/draft-Package binding, pending confirmation, and safe compilation-review copy;
- `schemas/prompt-package-compilation-proposal-v0.yaml`: machine-readable Compilation Proposal digests, revision binding, privacy declarations, and zero-authorization contract;
- `docs/product/prompt-package-compilation-confirmation-receipt-v0.md`: exact compilation-choice capture, ready-aware creation permission, and safe outcome-copy contract;
- `schemas/prompt-package-compilation-confirmation-receipt-v0.yaml`: machine-readable confirm/modify/reject state, three source digests, privacy declarations, and no-Handoff boundary;
- `docs/product/prompt-package-creation-v0.md`: confirmed-only final-Package persistence, exact draft preservation, and safe success-copy contract;
- `docs/product/prompt-package-lineage-v0.md`: persisted final-Package replay, full content comparison, and safe audit-copy contract;
- `docs/product/handoff-proposal-v0.md`: exact final-Package binding, pending zero-authority state, and safe Handoff-decision copy contract;
- `schemas/handoff-proposal-v0.yaml`: machine-readable final-Package digest, recipient, data declaration, and no-authorization contract;
- `docs/product/handoff-confirmation-receipt-v0.md`: exact six-source choice capture, Handoff-only authorization, and safe three-state result-copy contract;
- `schemas/handoff-confirmation-receipt-v0.yaml`: machine-readable six-file digests, confirm/modify/reject state, personal-data declaration, and no-external-effect boundary;
- `docs/product/handoff-envelope-creation-v0.md`: confirmed-only local bundle creation, deterministic seven-file lineage, and prepared-not-delivered copy contract;
- `docs/product/handoff-envelope-lineage-v0.md`: read-only persisted-Envelope reconstruction, semantic comparison, and still-not-delivered audit-copy contract;
- `schemas/handoff-envelope-v0.yaml`: machine-readable embedded final Package, authorization lineage, prepared state, and no-external-effect boundary;
- `docs/product/handoff-adapter-profile-v0.md`: provider-neutral Adapter capability, receipt, retry, data, cost, effect, and authorization contract;
- `schemas/handoff-adapter-profile-v0.yaml`: machine-readable reviewed Adapter capability and exact true-effect authorization requirements;
- `docs/product/handoff-adapter-selection-proposal-v0.md`: exact Envelope/Profile binding, pending zero-effect selection, and safe decision-copy contract;
- `schemas/handoff-adapter-selection-proposal-v0.yaml`: machine-readable exact-byte bindings, compatibility unknowns, and no-selection/no-dispatch state;
- `docs/product/handoff-adapter-selection-confirmation-receipt-v0.md`: exact ten-source choice capture, selected-not-dispatchable semantics, and safe three-state copy contract;
- `schemas/handoff-adapter-selection-confirmation-receipt-v0.yaml`: machine-readable confirm/modify/reject state, ten source digests, privacy declarations, and zero dispatch/effect authorization boundary;
- `docs/product/handoff-payload-data-attestation-v0.md`: exact eleven-source complete-payload review, derived compatibility matrix, provenance rules, and safe compatible/blocked copy contract;
- `schemas/handoff-payload-data-attestation-v0.yaml`: machine-readable payload facts, controlled categories, selected-Profile policy binding, derived compatibility, and zero dispatch/effect authorization boundary;
- `docs/product/handoff-adapter-effect-authorization-proposal-v0.md`: exact twelve-source true-effect disclosure, cost/production-data boundary, and pending zero-authority copy contract;
- `schemas/handoff-adapter-effect-authorization-proposal-v0.yaml`: machine-readable true-effect set, disclosure, pending state, and zero effect/dispatch authorization boundary;
- `docs/product/handoff-adapter-effect-authorization-confirmation-receipt-v0.md`: exact thirteen-source named-effect choice, non-executable grants, and safe three-state result-copy contract;
- `schemas/handoff-adapter-effect-authorization-confirmation-receipt-v0.yaml`: machine-readable exact-grant state machine, derived sensitive effects, and preserved implementation/dispatch gates;
- `docs/product/handoff-adapter-implementation-attestation-v0.md`: exact fourteen-source implementation review, effect/contract derivation, and compatible-or-blocked copy contract;
- `schemas/handoff-adapter-implementation-attestation-v0.yaml`: machine-readable implementation identity/provenance, observed-effect deltas, contract evidence, and false runtime/executable/dispatch boundary;
- `docs/product/handoff-adapter-runtime-readiness-attestation-v0.md`: exact fifteen-source runtime review, credential/health/lifecycle derivation, and ready-or-blocked copy contract;
- `schemas/handoff-adapter-runtime-readiness-attestation-v0.yaml`: machine-readable runtime configuration, credential-reference, provider-health, lifecycle, cost-gate, and false executable/dispatch boundary;
- `docs/product/handoff-adapter-dispatch-proposal-v0.md`: exact sixteen-source dispatch decision, idempotency/time/cost/stop contract, and pending zero-dispatch copy;
- `schemas/handoff-adapter-dispatch-proposal-v0.yaml`: machine-readable exact payload/destination, deterministic idempotency, fixed-point ceiling, canonical stops, and false execution/dispatch boundary;
- `docs/product/handoff-adapter-dispatch-confirmation-receipt-v0.md`: exact seventeen-source dispatch choice, exact cost-ceiling consent, and authorization-without-execution contract;
- `schemas/handoff-adapter-dispatch-confirmation-receipt-v0.yaml`: machine-readable confirm/modify/reject state, exact dispatch mirrors, derived cost authority, and false execution-result boundary;
- `docs/product/handoff-adapter-dispatch-execution-preflight-v0.md`: exact eighteen-source submitted evidence, fixed-point budget, canonical blocker, and ready-or-blocked zero-execution contract;
- `schemas/handoff-adapter-dispatch-execution-preflight-v0.yaml`: machine-readable point-in-time gate evidence, deterministic active stops, and false live-check/reservation/execution boundary;
- `schemas/clarification-session-v0.yaml`: machine-readable Intake, nine-gap, question-round, Compile Gate, and lineage contract;
- `docs/product/review-lenses-v0.md`: six-lens Quality Gate;
- `docs/product/concierge-runbook-v0.md`: manual operating and paired-test protocol;
- `evals/schema/case-v0.yaml`: provider-neutral case definition;
- `evals/schema/acceptance-result-v0.yaml`: two-reviewer decisions, adjudication state, and derived primary outcome;
- `evals/rubrics/first-pass-success-v0.md`: binary primary outcome and diagnostic scores;
- `evals/cases/seed/`: calibration cases. All have empty `run_records` until actually run.
- `evals/schema/calibration-wave-v0.yaml`: calibration readiness contract;
- `evals/schema/fixture-v0.yaml`: Fixture isolation, inventory, digest, and check contract;
- `evals/schema/workspace-set-v0.yaml`: generated isolated-arm receipt contract;
- `evals/schema/executor-profile-v0.yaml`: executor fairness, safety, and freeze contract;
- `evals/fixtures/`: three ready synthetic workspaces with executor-excluded oracles;
- `evals/calibration/executor-profiles/`: truthful draft/frozen executor decisions;
- `evals/calibration/wave-01.yaml`: first three-case Wave and honest blockers;
- `scripts/validate_evals.rb`: dependency-free structural, artifact-path, success-formula, and adjudication-state checks.
- `scripts/prepare_calibration_workspaces.rb`: no-overwrite preparation and verification of external arm copies.
- `scripts/calibration_preflight.rb`: read-only readiness report across contracts, roles, executor, and arm copies.
- `scripts/validate_prompt_package.rb`: read-only Prompt Package structure, reference, Review Lens, approval, and Handoff validator.
- `scripts/validate_clarification_session.rb`: read-only Clarification Session state and optional Session-to-Package lineage validator.
- `scripts/render_clarification_copy.rb`: read-only validated Session-to-user-Markdown renderer.
- `scripts/preview_clarification_answers.rb`: read-only Answer Receipt applicability and no-echo confirmation renderer.
- `scripts/preview_clarification_revision.rb`: read-only three-file binding, in-memory delta application, candidate Session validation, and safe confirmation renderer.
- `scripts/preview_clarification_confirmation.rb`: read-only exact-file confirmation binding and three-choice outcome renderer.
- `scripts/create_clarification_revision.rb`: confirmed-only, deterministic, no-overwrite Session revision creator with audit lineage.
- `scripts/verify_clarification_revision_lineage.rb`: read-only five-file replay verifier for persisted revision metadata and full Session content.
- `scripts/preview_prompt_package_compilation.rb`: read-only Session/Package/Proposal binding, cross-lineage validation, and safe confirmation renderer.
- `scripts/preview_prompt_package_compilation_confirmation.rb`: read-only four-file compilation choice binding and ready-aware outcome renderer.
- `scripts/create_prompt_package.rb`: deterministic, confirmed-only, no-overwrite `0600` final-Package creator with compilation lineage.
- `scripts/verify_prompt_package_lineage.rb`: read-only five-file replay verifier for final-Package metadata and full business content.
- `scripts/preview_handoff_proposal.rb`: read-only six-file lineage replay, exact final-Package binding, and safe pending Handoff renderer.
- `scripts/preview_handoff_confirmation.rb`: read-only seven-file Proposal replay, exact choice binding, and explicit Handoff-authorization renderer.
- `scripts/create_handoff_envelope.rb`: deterministic, confirmed-only, no-overwrite `0600` local Envelope creator that performs no dispatch.
- `scripts/verify_handoff_envelope_lineage.rb`: read-only eight-file replay verifier for Envelope metadata, authorization lineage, and complete embedded Package content.
- `scripts/preview_handoff_adapter_selection.rb`: read-only ten-file Envelope replay, reviewed Profile consistency validation, exact dual binding, and safe pending selection renderer.
- `scripts/preview_handoff_adapter_selection_confirmation.rb`: read-only eleven-file Selection replay, exact choice binding, and selected-without-dispatch renderer.
- `scripts/preview_handoff_payload_data_attestation.rb`: read-only twelve-file confirmed-Selection replay, complete-review provenance and compatibility validator, and compatible-without-authorization or blocked renderer.
- `scripts/preview_handoff_adapter_effect_authorization.rb`: read-only thirteen-file compatible-Attestation replay, exact true-effect and disclosure validator, and pending zero-authorization renderer.
- `scripts/preview_handoff_adapter_effect_authorization_confirmation.rb`: read-only fourteen-file Effect Proposal replay, exact named-grant state-machine validator, and non-executable/non-dispatch result renderer.
- `scripts/preview_handoff_adapter_implementation_attestation.rb`: read-only fifteen-file confirmed-effect replay, implementation provenance/effect/contract declaration validator, and compatible-or-blocked renderer.
- `scripts/preview_handoff_adapter_runtime_readiness_attestation.rb`: read-only sixteen-file compatible-implementation replay, submitted runtime-evidence validator, and ready-or-blocked renderer.
- `scripts/preview_handoff_adapter_dispatch_proposal.rb`: read-only seventeen-file ready-runtime replay, exact pending-dispatch validator, and zero-dispatch decision renderer.
- `scripts/preview_handoff_adapter_dispatch_confirmation.rb`: read-only eighteen-file Dispatch Proposal replay, exact choice/cost validator, and authorized-without-execution renderer.
- `scripts/preview_handoff_adapter_dispatch_execution_preflight.rb`: read-only nineteen-file confirmed-Receipt replay, submitted preflight evidence validator, and ready-or-blocked zero-execution renderer.

The executable runner will be selected only after the manual protocol and
Rubric are calibrated. No framework is assumed or installed at this stage.

Run the current deterministic checks with:

```sh
ruby scripts/validate_evals.rb
ruby test/validate_evals_test.rb
ruby test/acceptance_result_test.rb
ruby test/validate_clarification_session_test.rb
ruby test/render_clarification_copy_test.rb
ruby test/preview_clarification_answers_test.rb
ruby test/preview_prompt_package_compilation_test.rb
ruby test/preview_prompt_package_compilation_confirmation_test.rb
ruby test/create_prompt_package_test.rb
ruby test/verify_prompt_package_lineage_test.rb
ruby test/preview_handoff_proposal_test.rb
ruby test/preview_handoff_confirmation_test.rb
ruby test/create_handoff_envelope_test.rb
ruby test/verify_handoff_envelope_lineage_test.rb
ruby test/preview_handoff_adapter_selection_test.rb
ruby test/preview_handoff_adapter_selection_confirmation_test.rb
ruby test/preview_handoff_payload_data_attestation_test.rb
ruby test/preview_handoff_adapter_effect_authorization_test.rb
ruby test/preview_handoff_adapter_effect_authorization_confirmation_test.rb
ruby test/preview_handoff_adapter_implementation_attestation_test.rb
ruby test/preview_handoff_adapter_runtime_readiness_attestation_test.rb
ruby test/preview_handoff_adapter_dispatch_proposal_test.rb
ruby test/preview_handoff_adapter_dispatch_confirmation_test.rb
ruby test/preview_handoff_adapter_dispatch_execution_preflight_test.rb
ruby scripts/calibration_preflight.rb
```

The last command currently exits with a blocked status by design; it must not be
treated as a failed experiment.

## Measurement contract status

Case Schema `0.2.0` adds immutable executor/model/profile/workspace receipts,
separate Handoff and result durations, and executor/material rework counts. A
real `run_record` is valid only when its `input.md`, `result.md`,
`acceptance.yaml`, frozen `executor-profile.yaml`, and `workspace-set.yaml`
receipt exist under the directory encoded by its run ID. The validator hashes
the two preserved YAML receipts and rejects stale run-record digests.

The acceptance result preserves two independent assessments and permits only
three states:

- `consensus`: both primary decisions match and the matching final decision is locked;
- `needs_adjudication`: primary decisions differ and no final decision exists;
- `adjudicated`: primary decisions differ and a distinct third reviewer records the final decision.

The validator derives First-pass Delivery Success from the frozen blocking
criteria and Rubric gates, then cross-checks it against the run outcome. There
are currently zero acceptance results and zero real runs; the contract being
ready is not product-effect evidence.
