# Handoff Adapter local reference execution stage — 2026-08-23

- Status: atomic local-only reference execution implemented
- Scope: repository-local product, copy, implementation, and failure-recovery exploration
- External sources used: none
- Evidence basis: exact nineteen-file ready chain, ADRs 0002–0004, repository authority policy, and local temporary-directory tests

## Decision

PMind now implements one actual execution seam without pretending to have a production provider. A `local_reference` executor may publish the exact Envelope only inside an explicit caller-supplied local root, and only when the confirmed capability is local-file-only, zero-cost, credential-free, provider-free, and authorized for exactly one local write.

## Scope and copy decisions

- replay and bind all nineteen exact input files;
- use the current wall clock, with no CLI backdating;
- reject non-ready, stale, nested-path, symlink-root, provider, credential, cost, network, process, production-data, and extra-effect cases;
- require a root isolated from the repository and sources, then derive the final directory only from a safe confirmed destination segment;
- atomically reserve, build, fsync, recheck, and rename one two-file bundle;
- record the real local write and attempt while fixing all unperformed capability fields false;
- never overwrite or delete a final bundle;
- verify every persisted field and exact Envelope byte before idempotent reuse;
- disclose “local reference,” the one executed effect, and the remaining production boundary without exposing refs, paths, IDs, digests, or payload.

## Failure and recovery model

Before publish, failures remove only the current operation's validated temp and lock names inside the supplied root. Other root contents and all source files remain untouched. After publish, corruption or drift is reported but preserved for investigation. Recovery from a committed local reference result is an explicit operator action, not an automatic retry or cleanup side effect.

## Acceptance evidence

The focused test seam covers exact delivered bytes, generated Receipt schema and bindings, `0700`/`0600` permissions, idempotent zero-write replay, real-window CLI behavior, not-before/expiry, blocked Preflight, upstream drift, exact terminal Preflight bytes, path traversal/hidden names, symlink and missing roots, provider/credential/cost/process scope rejection, partial-write cleanup, sentinel preservation, corrupted/incomplete/existing destinations, lying Receipt fields, weakened permissions, lock contention, and CLI argument safety.

## Verification summary

- focused contract suite: PASS — 17 runs, 149 assertions;
- repository Minitest suite: PASS — 634 runs, 4,605 assertions;
- Eval structural validation: PASS — 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, 0 acceptance results, 9 gap dimensions, and 12 risk tags;
- Ruby warning compilation: PASS — 64 files;
- safe YAML parsing with aliases disabled: PASS — 80 repository and local Skill files;
- product schema inventory: PASS — 22 schemas;
- local Markdown link audit: PASS — 71 files;
- secret-signature scan: PASS — 252 files;
- AUTH/FILESYSTEM audit: PASS — no network, environment, process, shell, or floating-cost primitive in the executor; every mutator is constrained to the validated isolated root, derived lock/temp/final paths, exclusive `0600` files, atomic rename, or guarded temp/lock cleanup;
- diff whitespace audit: PASS;
- calibration preflight: BLOCKED at 3/6 — four real roles, six frozen Executor decisions, and isolated arm workspaces remain absent;
- static typing, lint, task-runner, and CI checks: BLOCKED — the repository has no corresponding configuration.

The blocked checks remain blocked; none is reported as PASS. The accepted alternative evidence proves deterministic isolated-local execution behavior only, not live Service, provider, calibration, or commercial readiness.

## Remaining risk and next boundary

This capability proves local filesystem execution semantics only. It assumes a non-adversarial caller-owned local root; it does not prove hostile shared-filesystem isolation, real personnel, live remote destination checks, production isolation, shared idempotency storage, provider delivery, remote receipts, credentials, retries, billing, calibration outcomes, user adoption, or First-pass Delivery Success.

The next smallest local boundary is an independent read-only verifier for a persisted local Execution Receipt bundle. Any provider-backed executor remains blocked until explicit external scope, real configuration, and provider-specific acceptance evidence exist.
