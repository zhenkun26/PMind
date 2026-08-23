# Handoff Adapter implementation attestation stage — 2026-08-23

- Status: immutable fifteen-file Implementation Attestation preview implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, exact Adapter Profile and Effect Authorization Receipt, prior attestation contracts, and repository authorization policy

## Decision

The next smallest valuable boundary is a provider-neutral Adapter Implementation Attestation. It accepts a completed, declarative review result and separates three claims that must not be conflated: observed effects match the reviewed Profile, submitted provider contract-test evidence covers the Profile, and the runtime is ready.

Only the first two are in scope. Runtime readiness remains false.

## Scope decisions

- the Attestation binds all fourteen prior files by byte-level SHA-256 and stable identities;
- only a confirmed exact Effect Authorization Receipt may enter this stage;
- Profile-declared effects and authorized effects must exactly match their sources;
- observed effects derive missing and undeclared sets, including a controlled `other` category;
- nonconformance and failed/incomplete contract evidence are valid, immutable blocker results;
- compatibility requires both effect conformance and passed seven-dimension contract evidence;
- implementation ref, version and digest are submitted provenance, not independently loaded or verified by the preview;
- manual, automated and hybrid review methods have exact reviewer/scanner rules;
- the preview never loads or executes implementation code and never runs the declared test suite;
- credentials, provider health, runtime readiness, effect executability and dispatch remain false;
- no personal data, secrets or credential material may enter the Attestation.

## Copy plan

Compatible uses “Adapter 实现声明符合 Profile，仍未达到运行时就绪.” It explicitly says the preview neither loaded implementation bytes nor ran the submitted tests, then shows only controlled implementation type, review method, conformance and remaining gates.

Incompatible uses “Adapter 实现声明不符合要求，运行时路径已阻断.” It names controlled blocker categories without exposing paths, refs, digests, IDs or free-text evidence.

No copy may say configured, activated, provider-verified, credential-ready, healthy, dispatch-ready, executing, delivered or running.

## Implementation and test seam

The deterministic chain fixture now builds fifteen files. The preview reuses the complete fourteen-file Effect Authorization Confirmation replay, validates the exact Attestation declaration, deterministically derives effect and contract results, and renders compatible or blocked Markdown.

Focused tests cover compatible, zero/all effects, missing and undeclared effects, controlled `other`, failed test and every coverage gap, derived-result contradictions, canonical effect order, three provenance modes, modify/reject upstream blocks, all fourteen source drifts and declared digests, identity/state binding, all runtime/authority gates, time/classification, malformed YAML, Markdown safety, information minimization, exact Attestation bytes, and fifteen-file CLI zero-write behavior.

## Remaining risk

A valid synthetic Attestation does not prove the referenced implementation exists, prove its declared digest, authenticate a reviewer or scanner, prove a provider contract test actually ran, validate credentials, establish provider health, attest retention/export/purpose, make an effect executable, authorize dispatch, or produce product-effect evidence.

## Verification summary

- focused Implementation Attestation regression: 31 runs, 313 assertions, zero failures/errors/skips;
- full repository suite: 504 runs, 3,264 assertions, zero failures/errors/skips;
- Eval validation: 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, and 0 Acceptance Results remain structurally valid;
- warning-level Ruby compilation: 62 files passed;
- safe YAML loading: 72 repository-visible files passed;
- all repository-local Markdown links resolved and the product Schema inventory is exactly 17;
- secret-signature and production-preview dangerous-primitive scans found no match;
- line-by-line AUTH/STATE_MACHINE review confirmed all compatibility paths keep implementation loading, test execution, credentials, provider health, runtime readiness, effect executability, dispatch, and inferred high-risk authority false.

Calibration preflight remains honestly BLOCKED at 3/6 because four real roles, six Executor Profile decisions, and an isolated workspace set are absent. Ruby static typing, RuboCop/Standard lint, and CI remain BLOCKED because the repository has not adopted corresponding configuration. These are blocked checks, not PASS claims; the alternative evidence above does not replace the missing gates.

## Next boundary

Define a provider-neutral Adapter Runtime Readiness Attestation that accepts only a compatible Implementation Attestation and binds independently produced credential-reference, provider-health, configuration, and environment evidence. It must not store credential material, perform dispatch, or infer authorization. Independent dispatch confirmation remains a later boundary.
