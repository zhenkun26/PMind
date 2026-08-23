# Handoff Adapter runtime readiness attestation stage — 2026-08-23

- Status: immutable sixteen-file Runtime Readiness Attestation preview implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, exact fifteen-file Implementation Attestation chain, existing Adapter effect taxonomy, and repository authorization policy

## Decision

The next smallest valuable boundary is a provider-neutral Adapter Runtime Readiness Attestation. It reviews submitted runtime configuration, credential-reference, provider-health, and data-lifecycle evidence while keeping a hard distinction between an attested declaration and PMind independently accessing the runtime.

No environment access, credential read, health probe, provider call, process start, cost, effect execution, or dispatch is in scope.

## Scope decisions

- only a completed compatible Implementation Attestation may enter this stage;
- the Attestation binds all fifteen prior files by byte-level SHA-256 and stable identities;
- runtime configuration covers delivery, receipt, idempotency, retry, effect guard, data policy, and cost policy;
- credential evidence stores only a controlled reference and status matrix, never credential material;
- remote-write, notification, cost, and production-data effects require credential evidence;
- network/provider effects require independently submitted health evidence;
- health evidence has a digest and ordered timestamp, but the preview never executes the check;
- retention, export, and purpose are closed as three explicit compatibility dimensions;
- failed configuration, credential, health, or lifecycle evidence is a valid immutable blocker result;
- `cost_incurred` preserves a separate pending cost-limit gate even when runtime readiness is `ready`;
- ready and blocked both keep effects non-executable, dispatch false, and inferred high-risk authority false;
- Adapter Dispatch Proposal and independent dispatch confirmation remain required.

## Copy plan

Ready uses “Adapter 运行时就绪声明已通过，仍未授权 dispatch.” It says the preview did not access the environment or credentials and did not execute a provider health check. It exposes only controlled types and results.

Blocked uses “Adapter 运行时就绪声明未通过，dispatch 路径已阻断.” It names only controlled blocker dimensions and hides paths, digests, IDs, runtime refs, credential refs, health refs, and reviewer/scanner refs.

No copy may say PMind connected to the provider, PMind verified credentials, the Adapter is running, effects are executable, or dispatch is authorized.

## Implementation and test seam

The deterministic chain fixture builds sixteen files. The preview reuses the complete fifteen-file Implementation Attestation replay, rejects incompatible implementations, validates the exact Runtime declaration, derives configuration/credential/health/lifecycle/cost results, and renders ready or blocked Markdown.

Focused tests cover ready and blocked outcomes, seven configuration dimensions, required/optional credential and health matrices, effect-derived minimum requirements, concrete runtime/lifecycle refs, three lifecycle dimensions, cost-limit separation, result derivation, provenance modes, incompatible upstream rejection, all fifteen source drifts and declared digests, identity/state binding, time/classification, authority/privacy constants, malformed YAML, Markdown safety, information minimization, exact Attestation bytes, and sixteen-file CLI zero-write behavior.

## Remaining risk

A valid synthetic Attestation does not prove the referenced runtime exists, prove submitted refs or digests, authenticate a reviewer or scanner, validate or exercise a credential, establish live provider health, confirm external retention/export configuration, authorize a cost limit, make an effect executable, authorize dispatch, or produce product-effect evidence.

## Verification summary

- focused Runtime Readiness Attestation regression: 28 runs, 300 assertions, zero failures/errors/skips;
- full repository suite: 532 runs, 3,564 assertions, zero failures/errors/skips;
- Eval validation: 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, and 0 Acceptance Results remain structurally valid;
- warning-level Ruby compilation: 56 files passed;
- safe YAML loading: 61 repository-visible product/eval files passed;
- all repository-local Markdown links resolved and the product Schema inventory is exactly 18;
- secret-signature and Runtime preview dangerous-primitive scans found no match;
- line-by-line AUTH/STATE_MACHINE review confirmed all ready and blocked paths preserve no environment/credential access, no health execution, effects non-executable, dispatch false, cost-limit false, and inferred high-risk authority false.

Calibration preflight remains honestly BLOCKED at 3/6 because four real roles, six Executor Profile decisions, and an isolated workspace set are absent. Ruby static typing, RuboCop/Standard lint, and CI remain BLOCKED because the repository has not adopted corresponding configuration. These are blocked checks, not PASS claims; the alternative evidence above does not replace the missing gates.

## Next boundary

Define a provider-neutral Adapter Dispatch Proposal that accepts only a ready Runtime Readiness Attestation and binds one exact payload, Adapter, recipient, idempotency key, cost ceiling, expiry, and stop conditions. It must remain pending with zero dispatch. A later independent dispatch confirmation and a Service-enforced executor remain required before any provider call.
