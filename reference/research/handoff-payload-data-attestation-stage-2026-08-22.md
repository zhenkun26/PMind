# Handoff payload data attestation stage — 2026-08-22

- Status: immutable twelve-file Payload Data Attestation preview implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, Handoff Envelope, selected Adapter Profile, Selection Confirmation contract, and repository authorization policy

## Decision

The next smallest valuable boundary is a provider-neutral Payload Data Attestation, not a Scanner integration and not an Adapter implementation. It verifies an already-produced completed-review declaration against the exact eleven-file selected-Adapter chain and derives compatibility from payload facts plus the selected Profile policy.

The Attestation deliberately records data compatibility without granting authority. Combining it with effect approval or dispatch would make a successful privacy review silently expand into local writes, network access, process starts, notifications, costs, or production-data access.

## Scope decisions

- the review scope is the complete exact Handoff Envelope payload, not only the user's confirmation text;
- the preview validates an Attestation but performs no content scan itself;
- manual, automated, and hybrid reviews have distinct reviewer/scanner provenance requirements;
- no raw finding or sensitive excerpt is retained; only controlled category codes are allowed;
- personal-data compatibility is derived from presence plus the selected Profile's allowed/forbidden policy;
- any detected secret is incompatible because Profile v0 requires `secret_handling: forbidden`;
- Attestation classification above the selected Profile maximum is incompatible and participates in the overall result;
- v0 does not claim retention, geographic/export, or processing-purpose compatibility because Adapter Profile v0 has no corresponding policy fields; those dimensions must be added before any remote or production Adapter can dispatch;
- overall compatibility is the conjunction of classification, personal-data, and secret compatibility;
- both compatible and incompatible results keep dispatch/effect/high-risk authorization false or empty;
- a source byte, Profile policy, selection choice, or review result change requires a new Attestation.

## Copy plan

Compatible uses “Payload 数据审核已通过，仍未授权 dispatch.” It reports the complete review scope, controlled review method, safe presence/compatibility summary, and every true Profile effect as unauthorized. It points to an independent Effect Authorization Proposal.

Incompatible uses “Payload 数据与所选 Adapter 不兼容，dispatch 已阻断.” It reports only whether personal data or secrets caused the blocker, never raw findings or category codes. It explains that the recorded Adapter choice remains but cannot be dispatched.

Neither result may say approved for execution, configured, delivered, received, activated, or running.

## Implementation and test seam

The shared test chain now creates eleven deterministic files through Adapter Selection Confirmation. The Payload preview reuses the existing eleven-file preview and its same-replay digests, then adds the exact Selection Confirmation bytes before validating the twelfth file.

Focused tests cover the compatible and incompatible matrices, all three review methods, invalid provenance, all eleven source drifts, each declared digest, identity/state/policy binding, category-presence rules, time and classification, authorization denial, Markdown safety, information minimization, exact Attestation bytes, CLI arguments, and twelve-file zero-write behavior.

## Remaining risk

A valid Attestation does not authenticate a reviewer, prove Scanner coverage or accuracy, inspect runtime credentials, prove the Profile matches executable Adapter code, or establish retention/export/purpose compliance. A synthetic Fixture is contract evidence only and must never be represented as a real review.

## Verification evidence

- focused Payload Data Attestation regression: 26 runs, 222 assertions, zero failures/errors/skips;
- adjacent Adapter Selection Confirmation regression: 21 runs, 179 assertions, zero failures/errors/skips;
- full repository suite: 422 runs, 2,454 assertions, zero failures/errors/skips;
- Eval validation: 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, and 0 Acceptance Results remain structurally valid;
- warning-level Ruby compilation: 56 files passed;
- safe YAML loading: 54 files passed;
- all repository-local Markdown links resolved and the product Schema inventory is exactly 14;
- changed-file scans found no high-confidence secret, bypass marker, escape hatch, or new-script write/network/process primitive;
- line-by-line authorization review confirmed that compatibility changes only the result copy: dispatch/effect/high-risk authority remains false or empty in every state.

Calibration preflight remains honestly BLOCKED at 3/6 because four real roles, six Executor Profile decisions, and an isolated workspace set are absent. Ruby static typing, RuboCop/Standard lint, and CI remain BLOCKED because the repository has not adopted corresponding configuration. These are blocked checks, not PASS claims; the alternative local evidence above does not replace the missing gates.

## Next boundary

The provider-neutral Adapter Effect Authorization Proposal is now implemented and documented in `handoff-adapter-effect-authorization-stage-2026-08-22.md`. It binds the exact twelve-file chain, enumerates the selected Profile's true effects, discloses cost and production-data implications, and remains pending with every authorization false. The next boundary is an independent Effect Authorization Confirmation Receipt; real Adapter implementation and dispatch remain deferred.
