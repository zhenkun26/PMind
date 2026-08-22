# Handoff Adapter effect authorization proposal stage — 2026-08-22

- Status: immutable thirteen-file Adapter Effect Authorization Proposal preview implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, selected Adapter Profile, compatible Payload Data Attestation, and repository authorization policy

## Decision

The next smallest valuable boundary is a provider-neutral, pending Effect Authorization Proposal. It converts the selected Profile's exact true-effect set into a reviewable disclosure without recording a choice or granting authority. A Confirmation Receipt, executable Adapter, and dispatch are deliberately separate future boundaries.

## Scope decisions

- the Proposal binds all twelve prior files by byte-level SHA-256 and stable identities;
- only a completed compatible Payload Data Attestation can enter this stage;
- requested effects must exactly equal the selected Profile's true effects; missing and extra effects are both rejected;
- an empty effect set is legal but does not bypass later dispatch confirmation;
- cost is disclosed as possible and not estimated, never as an invented amount;
- production-data access receives its own mandatory disclosure;
- retention/export/purpose compatibility remains `not_attested` because Profile v0 does not define those policies;
- Proposal, user choice, granted effects, dispatch, external effects, and inferred high-risk authority stay pending/empty/false;
- a source byte, Profile effect, selection, or Attestation change invalidates the Proposal.

## Copy plan

The title is “Adapter 副作用授权提案待确认，当前零授权.” Controlled effect names are listed individually as awaiting authorization. Cost, production data, zero-authority status, and the known data-policy gap are shown before confirm/modify/reject choices.

The confirm choice says only that an independent Receipt may be created. It must not say authorized, ready to dispatch, configured, activated, delivered, or running.

## Implementation and test seam

The shared test chain now creates twelve deterministic files through Payload Data Attestation. The Effect preview reuses the twelve-file preview and same-replay digests, validates compatibility before loading the thirteenth Proposal, then validates exact effects, controlled disclosures, time, classification, and zero-authority state.

Focused tests cover one, zero, and all true effects; missing/extra effects; incompatible Attestation; all twelve source drifts and declared digests; identity/state binding; no-cost, cost, and contradictory Profile disclosures; production-data disclosure; illegal authorization transitions; time and classification; the retention/export/purpose gap; personal-data/secret exclusion; malformed input; information minimization; exact Proposal bytes; and thirteen-file CLI zero-write behavior.

## Remaining risk

A valid Proposal does not authenticate the user, approve any effect, prove the Profile matches executable code, estimate cost, validate runtime credentials, prove provider availability, or establish retention/export/purpose compliance. Synthetic Fixtures are contract evidence only.

## Verification summary

- focused Adapter Effect Authorization regression: 23 runs, 230 assertions, zero failures/errors/skips;
- full repository suite: 445 runs, 2,684 assertions, zero failures/errors/skips;
- Eval validation: 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, and 0 Acceptance Results remain structurally valid;
- warning-level Ruby compilation: 58 files passed;
- safe YAML loading: 55 files passed;
- all repository-local Markdown links resolved and the product Schema inventory is exactly 15;
- the production preview contains no file-write, network, process, notification, cost, or production-data execution primitive;
- line-by-line authorization review confirmed that only controlled disclosure changes with the Profile: Proposal/user-choice authority remains pending/not-recorded and effect/dispatch/external/high-risk authority remains empty or false.

Calibration preflight remains honestly BLOCKED at 3/6 because four real roles, six Executor Profile decisions, and an isolated workspace set are absent. Ruby static typing, RuboCop/Standard lint, and CI remain BLOCKED because the repository has not adopted corresponding configuration. These are blocked checks, not PASS claims; the alternative local evidence above does not replace the missing gates.

## Next boundary

The immutable Adapter Effect Authorization Confirmation Receipt is now implemented and documented in `handoff-adapter-effect-authorization-confirmation-stage-2026-08-22.md`. It records confirm/modify/reject and exact named grants while keeping effects non-executable and dispatch false. The next boundary is a provider-neutral Adapter Implementation Attestation; credentials, health checks, and dispatch remain deferred.
