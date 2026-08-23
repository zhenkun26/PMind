# ADR 0004: Use atomic local reference execution bundles

- Status: Accepted
- Date: 2026-08-23

## Context

PMind can validate an exact nineteen-file dispatch chain, but a ready Preflight is still only submitted evidence. The repository needs one executable seam that proves attempt reservation, exact-byte delivery, immutable receipts, idempotent replay, failure cleanup, and truthful effect accounting without silently expanding into provider, credential, network, process, production-data, or cost scope.

Writing a payload and receipt as unrelated files would expose partial success. Accepting an arbitrary output path would let destination metadata escape the caller's intended isolation boundary. Re-running an idempotency key without checking the persisted result could also conceal drift or a prior partial write.

## Decision

PMind provides a deliberately narrow `local_reference` executor. It accepts only a currently valid, ready nineteen-file chain whose exact capability is `local_file` delivery, `local_digest` receipt, one authorized `local_file_write` effect, no credential or provider-health requirement, and zero cost.

The caller supplies an existing non-symlink local execution root that is isolated from the repository and every source file. The confirmed destination ref must be one safe path segment. The executor reserves that destination with an atomic lock directory, builds a `0700` temporary directory inside the same root, writes the exact Envelope and Execution Receipt as `0600` files, rechecks source bytes and time, then renames the directory into place. It never overwrites a final destination.

An existing destination is not treated as success by presence alone. Idempotent replay must validate the exact two-file inventory, permissions, schema, all source bindings, execution time, receipt state, and delivered Envelope bytes. Only an exact match may be reused without another write. Expected failures remove only the executor-created temporary and lock entries; a published final bundle is immutable.

## Consequences

- PMind now has one real local execution capability and can test execution semantics without fabricating provider activity.
- The Execution Receipt truthfully records a local write and dispatch attempt, while provider, credential, network, process, and cost fields remain false.
- The execution root, source files, and repository remain outside executor cleanup and overwrite authority.
- A stale, provider-backed, credentialed, paid, multi-effect, nested-path, or corrupted dispatch is rejected.
- Production Adapter implementations, shared idempotency stores, remote delivery receipts, retries, live health checks, credentials, billing, deployment, and product-effect evidence remain separate future boundaries requiring explicit scope and real configuration.
