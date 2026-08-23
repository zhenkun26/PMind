# Handoff Adapter dispatch proposal stage — 2026-08-23

- Status: immutable seventeen-file pending Dispatch Proposal preview implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, exact sixteen-file Runtime Readiness chain, Profile retry/idempotency capabilities, named-effect authorization, and repository authorization policy

## Decision

The next smallest valuable boundary is a provider-neutral Adapter Dispatch Proposal. It turns a ready runtime declaration into one reviewable exact-dispatch decision without inheriting execution authority.

The Proposal binds the exact Envelope payload, Adapter, destination, deterministic idempotency key, attempt/timeout policy, validity window, health-evidence freshness, fixed-point cost ceiling, and canonical stop conditions. It stays pending and zero-dispatch.

## Scope decisions

- only a completed ready Runtime Readiness Attestation may enter this stage;
- all sixteen prior files are bound by byte-level SHA-256 and stable identities;
- the payload is the exact Handoff Envelope bytes, not a reconstructed or summarized payload;
- v0 requires Adapter idempotency support;
- the idempotency key deterministically binds payload, Adapter implementation/runtime, destination, time window, attempts, timeout, and cost ceiling;
- attempt limit cannot exceed the reviewed Profile retry capability;
- validity is bounded to 60 seconds through 24 hours and has an explicit not-before boundary;
- required provider-health evidence must remain current through not-before, without performing a new check;
- the worst-case attempt-count times timeout budget must fit inside the not-before-to-expiry window;
- cost ceilings are positive fixed-point strings with at most four decimals; float, exchange, tax, and billing calculations are absent;
- cost authorization remains pending even though a ceiling is disclosed;
- stop conditions are a complete canonical set derived from credential, health, cost, receipt, and effect boundaries;
- every valid Proposal keeps choice unsaved, effects non-executable, Adapter/provider untouched, dispatch false, and external write/cost false.

## Copy plan

The title is “Adapter dispatch 提案待确认，尚未调用 provider.” The copy shows controlled delivery facts, exact limits, named effects, stop conditions, and confirm/modify/reject options.

It hides file paths, destination ref, all digests, idempotency key, internal IDs, implementation/runtime refs, and payload content. Confirm means only “create an independent confirmation receipt later,” never dispatch now.

## Implementation and test seam

The deterministic chain fixture builds seventeen files. The preview reuses the complete sixteen-file Runtime Attestation replay, rejects blocked runtime or unsupported idempotency, validates exact binding and pending authority, and renders safe Markdown.

Focused tests cover default, zero/all effects, fixed-point cost ceiling legal/illegal forms, no-cost state, deterministic idempotency, unsupported idempotency, destination derivation, retry limits, time-window ordering, health freshness, canonical conditional stops, blocked upstream, all sixteen source drifts and declared digests, identity/capability/runtime binding, payload digest, classification, all authority/privacy constants, malformed YAML, Markdown safety, information minimization, exact Proposal bytes, and seventeen-file CLI zero-write behavior.

## Remaining risk

A valid synthetic Proposal does not prove a destination exists, a credential works, provider health remains live, a cost ceiling was authorized, a user made a choice, the Adapter can start, dispatch can succeed, a receipt can be obtained, or PMind improves delivery outcomes.

## Verification summary

- focused contract suite: PASS — 30 runs, 304 assertions;
- repository Minitest suite: PASS — 562 runs, 3,868 assertions;
- Eval structural validation: PASS — 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, 0 acceptance results, 9 gap dimensions, and 12 risk tags;
- Ruby warning compilation: PASS — 58 files;
- safe YAML parsing with aliases disabled: PASS — 63 files;
- product schema inventory: PASS — 19 schemas;
- local Markdown link audit: PASS — 62 files;
- secret-signature scan: PASS — 233 files;
- line-by-line AUTH/FINANCE alternative audit: PASS — all 12 zero-authority constants fixed false, no network/process/environment/write primitive, and no float conversion in the new preview;
- diff whitespace audit: PASS;
- calibration preflight: BLOCKED at 3/6 — four real roles, six frozen Executor decisions, and isolated arm workspaces remain absent;
- static typing, lint, task-runner, and CI checks: BLOCKED — the repository has no corresponding configuration.

The blocked checks remain blocked; none is reported as PASS. The accepted alternative evidence proves only deterministic local contract behavior, not real dispatch readiness or product effect.

## Next boundary

Define an immutable Adapter Dispatch Confirmation Receipt bound to this exact seventeen-file Proposal chain. It records confirmed, modify-requested, or rejected and the exact cost-ceiling consent where applicable, but still performs no provider call. A later Service-enforced dispatch request/execution receipt boundary remains required.
