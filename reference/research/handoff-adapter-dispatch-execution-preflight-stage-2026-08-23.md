# Handoff Adapter dispatch execution preflight stage — 2026-08-23

- Status: immutable nineteen-file submitted-evidence Preflight implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: exact eighteen-file confirmed Dispatch Receipt chain, ADR 0003, canonical stop conditions, and repository authority policy

## Decision

The final repository-local boundary before real execution is a provider-neutral Adapter Dispatch Execution Preflight. It accepts only exact confirmed authority, validates submitted point-in-time evidence, and derives ready or blocked without performing live checks or dispatch.

## Scope decisions

- all eighteen prior files are byte-bound;
- confirmed dispatch facts and cost ceiling are mirrored exactly;
- source, authorization, and runtime replay checks must pass structurally;
- validity is derived from checked-at against exact not-before and expiry;
- credential and provider-health requirements follow the Runtime Attestation;
- passed health needs current timestamped submitted evidence;
- destination, idempotency availability, and effect scope remain submitted checks;
- fixed-point cost estimate must use the confirmed currency and ceiling without float;
- canonical active blockers derive overall ready/blocked;
- ready alone requires a future atomic reservation and Execution Receipt;
- blocked terminates those future gates;
- every result remains zero-execution and zero-external-effect.

## Copy plan

Ready says “声明已通过，仍未执行” and labels every check as submitted evidence. Blocked lists only controlled stop-condition copy. Neither path reveals refs, digests, keys, IDs, source content, or evidence internals.

## Test seam

The chain fixture builds nineteen files. Focused tests cover ready, not-before/expiry, confirmation ordering, credential/health required matrices and evidence freshness, destination/idempotency/effect blockers, fixed-point cost comparisons, active/result derivation, ready/blocked future gates, non-confirmed upstream rejection, eighteen source drifts and digests, exact binding, provenance, all zero-execution constants, classification, malformed YAML, Markdown minimization, exact bytes, and nineteen-file CLI zero-write behavior.

## Remaining risk and external boundary

A valid synthetic ready result does not prove live credentials, health, destination reachability, idempotency storage, budget, Adapter behavior, delivery, billing, or product effect. Actual execution requires a selected Service implementation and explicit authority to use credentials, call a provider, write externally, and possibly incur cost. Those actions are intentionally not performed here.

## Verification summary

- focused contract suite: PASS — 27 runs, 283 assertions;
- repository Minitest suite: PASS — 617 runs, 4,456 assertions;
- Eval structural validation: PASS — 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, 0 acceptance results, 9 gap dimensions, and 12 risk tags;
- Ruby warning compilation: PASS — 62 files;
- safe YAML parsing with aliases disabled: PASS — 67 files;
- product schema inventory: PASS — 21 schemas;
- local Markdown link audit: PASS — 67 files;
- secret-signature scan: PASS — 246 files;
- line-by-line AUTH/FINANCE alternative audit: PASS — all 16 zero-live-check/reservation/execution constants fixed false, no network/process/environment/write primitive, no float conversion, and integer fixed-point cost comparison in the new preview;
- diff whitespace audit: PASS;
- calibration preflight: BLOCKED at 3/6 — four real roles, six frozen Executor decisions, and isolated arm workspaces remain absent;
- static typing, lint, task-runner, and CI checks: BLOCKED — the repository has no corresponding configuration.

The blocked checks remain blocked; none is reported as PASS. The accepted alternative evidence proves deterministic local submitted-evidence contract behavior only, not live Service readiness or execution.

## Next boundary

Implementing an actual Service executor and immutable Execution Receipt is now the next technical boundary, but activating it requires explicit provider/runtime/credential/cost scope. Until that authority and real configuration exist, PMind must stop at a validated ready-or-blocked Preflight and must not fabricate execution.
