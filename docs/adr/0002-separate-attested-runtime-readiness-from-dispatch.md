# ADR 0002: Separate attested runtime readiness from dispatch

- Status: Accepted
- Date: 2026-08-23

## Context

PMind now has an exact chain from vague Intent through a compatible Adapter implementation declaration. The next boundary needs credential-reference, provider-health, runtime-configuration, and data-lifecycle evidence, but PMind has not selected or authorized a Service runtime that may read secrets, probe providers, start processes, incur cost, or dispatch.

Calling a declaration “runtime ready” can easily be misread as a live connection or execution authorization. Treating cost-limit consent as a configuration check would also hide a distinct human Approval Point.

## Decision

PMind defines Adapter Runtime Readiness Attestation as an immutable review result over submitted evidence. The repository-local preview validates exact lineage, controlled provenance, state matrices, and derived ready/blocked outcomes. It never accesses the referenced environment or credential, executes a health check, starts the Adapter, calls a provider, or makes effects executable.

Runtime readiness excludes dispatch authority. Every valid result keeps `effects_executable: false` and `dispatch_authorized: false`, and requires a later Adapter Dispatch Proposal plus independent dispatch confirmation.

When `cost_incurred` is an authorized named effect, a runtime may still be declared ready, but `cost_limit_authorized` remains false and the dispatch cost gate remains pending. Cost consent belongs to the exact dispatch decision, not to a reusable environment attestation.

## Consequences

- A ready Attestation means the submitted review declaration is internally consistent; it does not prove PMind independently verified live state.
- Blocked evidence remains a valid auditable artifact rather than an invalid document.
- Credential material is never stored in the Attestation; only controlled references and statuses are allowed.
- A future Service may perform approved online checks, but its receipts must remain distinct from this preview and bind the exact versions checked.
- A future Dispatch Proposal must bind payload, Adapter, recipient, idempotency, expiry, cost ceiling, and stop conditions without inheriting execution authority from readiness.
- User copy must say “声明已通过” and must not say provider connected, credentials verified by PMind, Adapter running, effects executable, or dispatch ready.
