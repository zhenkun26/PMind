# ADR 0003: Separate dispatch authorization from execution

- Status: Accepted
- Date: 2026-08-23

## Context

PMind can now describe one exact Adapter dispatch without starting the Adapter or calling a provider. The next user choice must cover the exact payload, destination, idempotency boundary, time window, attempt/timeout limits, authorized effects, stop conditions, and cost ceiling. Treating that choice as an execution result would collapse human authorization, Service preflight, provider activity, delivery, and cost into one unauditable state.

## Decision

PMind defines Adapter Dispatch Confirmation Receipt as an immutable choice over one exact Dispatch Proposal. `confirmed` sets `dispatch_authorized: true` only for the bound dispatch and, when a cost effect is present, authorizes only the bound fixed-point ceiling and currency. `modify_requested` and `rejected` authorize neither dispatch nor cost.

Every valid Receipt keeps effects non-executable and records that the Adapter was not started, the provider was not called, dispatch was not attempted, no delivery receipt exists, no external write occurred, and no cost was incurred. For confirmed only, a later Service execution request and execution receipt remain mandatory and must replay the exact chain plus live validity, credential, health, idempotency, budget, and stop-condition gates. Modify and reject terminate the path before that request.

## Consequences

- Authorization becomes auditable without fabricating execution evidence.
- Cost consent is exact-dispatch scoped and cannot be inherited by another destination, payload, time window, or idempotency key.
- A confirmed Receipt may expire before execution; a Service must reject stale authority rather than refreshing it implicitly.
- Modification requires a new Proposal and Receipt chain.
- Provider calls, runtime access, effects, delivery, and billing remain outside repository-local previews.
