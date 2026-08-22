# Handoff Adapter selection confirmation stage — 2026-08-22

- Status: immutable eleven-file Selection Confirmation preview implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, Adapter Selection Proposal contract, existing confirmation-receipt patterns, repository authorization policy

## Decision

The next smallest valuable boundary is an Adapter Selection Confirmation Receipt, not payload scanning and not a real Adapter. It records whether the user confirmed, requested modification, or rejected one exact Selection Proposal while keeping every execution and effect permission false.

This creates an auditable distinction between “the user selected a Profile” and “the system may run that Adapter.” Combining selection with payload attestation or effect authorization would erase that distinction and make later provider-specific controls harder to verify.

## Implemented invariants

- the complete ten-file Selection Proposal chain is replayed before the Receipt is trusted;
- all ten source digests come from the same replay/read seam, not a later independent file read;
- the Receipt binds exact Envelope/Profile/Proposal identities and prepared/reviewed/pending states;
- confirmed requires `adapter_selected: true`; modify and reject require false;
- dispatch, external effects, inferred high-risk authorization, and every effect authorization remain false/empty for all choices;
- personal-data and secret compatibility remain unknown;
- payload data attestation remains required;
- the Receipt cannot predate the Proposal or downgrade Envelope/Proposal classification;
- raw response bytes are digest-bound, independently classified, never echoed, and cannot contain secrets;
- confirmed, modify, and reject copy expose only the minimum safe decision result;
- the preview has no file, model, network, process, notification, cost, production-data, or external-service effect.

## Copy plan

Confirmed uses “已记录 Adapter 选择，尚未 dispatch” and explicitly lists true Profile effects as unauthorized. Modify uses “已收到 Adapter 选择修改请求，当前未选择” and preserves the Envelope. Reject uses “已拒绝当前 Adapter 候选” and states that no Adapter was selected.

No state may say ready, configured, activated, delivered, or running. The confirmed copy directs the workflow to Payload Data Attestation rather than a dispatch command.

## Test seam decision

The existing ten-file synthetic-chain builder was extracted into `test/support/handoff_adapter_chain_fixture.rb` because both Selection Proposal and Selection Confirmation tests now need the same deterministic lineage. This is test-only reuse; production contracts remain composed through the existing preview/verifier seams.

The Selection Preview now exposes ten digests derived from the Envelope reconstruction plus the exact Profile and Proposal bytes it read. The Confirmation Preview consumes those values directly, avoiding a time-of-check/time-of-use gap from hashing the sources again after validation.

## Remaining risk

A confirmed Receipt proves only the consistency of the supplied files and state declarations. It does not authenticate the human, scan the payload, prove the Profile matches executable code, configure credentials, test availability, or authorize effects.

## Verification evidence

- focused Selection Proposal regression: 21 runs, 170 assertions, zero failures/errors/skips;
- focused Selection Confirmation regression: 21 runs, 179 assertions, zero failures/errors/skips;
- full repository suite: 396 runs, 2,232 assertions, zero failures/errors/skips;
- Eval validation: 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, and 0 Acceptance Results remain structurally valid;
- warning-level Ruby compilation: 54 files passed;
- safe YAML loading: 52 files passed;
- all repository-local Markdown links resolved;
- changed-file scans found no high-confidence secret, bypass marker, or new-script write/network/process primitive;
- line-by-line authorization review confirmed that every dispatch/effect/high-risk field is fixed false or empty and confirmed changes only `adapter_selected`.

Calibration preflight remains honestly BLOCKED at 3/6 because four real roles, six Executor Profile decisions, and an isolated workspace set are absent. Ruby static typing, RuboCop/Standard lint, and CI remain BLOCKED because the repository has not adopted corresponding configuration. These are recorded as blocked checks, not PASS claims; the alternative local evidence above does not replace the missing gates.

## Next boundary

The provider-neutral Handoff Payload Data Attestation is now implemented and documented in `handoff-payload-data-attestation-stage-2026-08-22.md`. It binds the exact eleven-file chain, derives classification/personal-data/secret compatibility from the selected Profile policy, and remains read-only with zero Adapter effects or dispatch authority. Retention/export/purpose compatibility is explicitly not claimed because Profile v0 lacks those policy fields. The next boundary is a pending, zero-authorization Adapter Effect Authorization Proposal; a real Adapter remains deferred.
