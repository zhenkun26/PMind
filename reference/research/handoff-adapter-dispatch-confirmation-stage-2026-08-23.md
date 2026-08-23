# Handoff Adapter dispatch confirmation stage — 2026-08-23

- Status: immutable eighteen-file Dispatch Confirmation Receipt preview implemented
- Scope: repository-local product, copy, domain-decision, and implementation exploration
- External sources used: none
- Evidence basis: exact seventeen-file Dispatch Proposal chain, existing PMind confirmation state machines, ADR 0002, and repository authority policy

## Decision

The next smallest valuable boundary is an independent Adapter Dispatch Confirmation Receipt. It records one exact confirm, modify, or reject choice without conflating authorization with execution.

Confirmed authorizes only the exact bound dispatch. If the Proposal contains a cost effect, it also authorizes only the exact positive fixed-point amount ceiling and currency. Every valid Receipt remains a zero-execution artifact and requires a later Service execution request plus execution receipt.

## Scope decisions

- all seventeen source files are bound by byte-level SHA-256 and stable identities;
- payload, Adapter, destination, idempotency key, delivery/receipt mode, time window, attempts, timeout, authorized effects, stop conditions, and cost ceiling must exactly mirror the Proposal;
- confirmed derives dispatch authorization true; modify and reject derive it false;
- cost authorization is true only for a confirmed cost-bearing Proposal;
- Service execution request and execution receipt requirements are true only for confirmed and false for terminated paths;
- confirmed must be captured after proposal creation and strictly before expiry;
- a scheduled dispatch may be confirmed before not-before, but execution may not start early;
- modify/reject may be recorded after expiry because neither establishes authority;
- all decisions keep effects non-executable and execution/provider/delivery/write/cost facts false;
- a later Service must reject stale authorization rather than refreshing the Receipt.

## Copy plan

Confirmed copy says “已记录 Adapter dispatch 确认，尚未执行,” shows only controlled exact limits, and lists the future Service gates. Modify and reject explicitly preserve zero authority.

All three paths hide paths, refs, digests, idempotency keys, IDs, user response, and source content. No copy claims provider contact, dispatch attempt, delivery, billing, or effect.

## Implementation and test seam

The deterministic chain fixture builds eighteen files. The preview replays the complete seventeen-file Proposal chain, validates the Receipt from the same loaded bytes, derives choice/cost authority, validates capture time and classification, and renders safe Markdown.

Focused tests cover all three decisions, forged authority matrices, exact cost consent, no-cost and zero/all-effect paths, proposal/expiry/not-before timing, all seventeen source drifts and declared digests, stable identities and copied dispatch fields, invalid upstream Proposal, response digest, data classification, all zero-execution constants, required future gates, malformed YAML, Markdown safety, information minimization, exact Receipt bytes, and eighteen-file CLI zero-write behavior.

## Remaining risk

A valid synthetic Receipt does not prove a person made the choice, the Proposal remains current, credentials work, provider health is live, the destination exists, idempotency storage is available, budget remains, the Adapter can start, dispatch succeeds, delivery is acknowledged, cost is billed correctly, or PMind improves outcomes.

## Verification summary

- focused contract suite: PASS — 28 runs, 305 assertions;
- repository Minitest suite: PASS — 590 runs, 4,173 assertions;
- Eval structural validation: PASS — 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, 0 acceptance results, 9 gap dimensions, and 12 risk tags;
- Ruby warning compilation: PASS — 60 files;
- safe YAML parsing with aliases disabled: PASS — 65 files;
- product schema inventory: PASS — 20 schemas;
- local Markdown link audit: PASS — 65 files;
- secret-signature scan: PASS — 240 files;
- line-by-line AUTH/FINANCE alternative audit: PASS — all 10 zero-execution constants fixed false, no network/process/environment/write primitive, and no float conversion in the new preview;
- diff whitespace audit: PASS;
- calibration preflight: BLOCKED at 3/6 — four real roles, six frozen Executor decisions, and isolated arm workspaces remain absent;
- static typing, lint, task-runner, and CI checks: BLOCKED — the repository has no corresponding configuration.

The blocked checks remain blocked; none is reported as PASS. The accepted alternative evidence proves deterministic local authorization-contract behavior only, not a real user choice, live Service readiness, dispatch, delivery, billing, or product effect.

## Next boundary

Define a provider-neutral Service Adapter Dispatch Execution Request / Preflight bound to this exact eighteen-file chain. It should accept only confirmed, unexpired authority and deterministically return ready or blocked after declared Service checks, without fabricating a provider call. Actual dispatch and its delivery/cost receipt remain separate.
