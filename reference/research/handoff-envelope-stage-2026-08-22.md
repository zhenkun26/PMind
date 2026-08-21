# Handoff Envelope stage — 2026-08-22

- Status: implemented local contract slice
- Scope: repository-local product and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, Prompt Package/Handoff contracts, existing creator and lineage patterns, repository safety policy

## Decision

The next smallest valuable boundary after Handoff Confirmation is a local,
provider-neutral Handoff Envelope, not an executor adapter. The Envelope
packages one exact final Prompt Package with the confirmation lineage needed
to prove why future controlled transfer is permitted.

This boundary closes the portability gap without prematurely selecting Codex,
an Agents SDK, MCP, a message queue, or another delivery channel. It also keeps
channel-specific network, process, notification, cost, identity, retry, and
receipt semantics out of the product-neutral core.

## Implemented invariants

- only `confirmed` plus `handoff_authorized: true` can create an Envelope;
- the complete seven-file confirmation chain is replayed before output opens;
- output is deterministic, exclusive, no-overwrite, and mode `0600`;
- the Envelope embeds the exact final Prompt Package and seven file digests;
- `created_at` comes from the immutable Confirmation Receipt;
- `envelope_id` is deterministically mapped from `handoff_confirmation_id`;
- delivery state is exactly `prepared`;
- external-effect and inferred high-risk authorization remain false;
- no source path or raw confirmation response is embedded;
- personal-data and secrets flags are explicitly scoped to the Confirmation
  Receipt text and are not presented as a scan of the embedded Package;
- the Creator does not launch an Agent, model, process, network request,
  notification, or external service call.

## Copy plan

The success title is “Handoff Envelope 已创建，尚未交接”. The copy may show the
human-readable recipient, prohibited actions, stop conditions, and Approval
Point scopes after Markdown sanitization. It must explicitly say prepared-not-
delivered and must not expose paths, digests, IDs, raw Intent, answers, Evidence
sources, user confirmation text, or internal references.

## Risks and trade-offs

The Envelope intentionally contains the complete Prompt Package, which may
include sensitive business context. Mode `0600` is suitable only as the local
experiment minimum; a commercial runtime still needs tenant isolation,
encryption, retention policy, access audit, and channel-specific data controls.

The Envelope Schema validates the outer contract while the existing full
Prompt Package validator validates the embedded package. This avoids copying a
large Schema into a second contract and preserves one source of truth, at the
cost of requiring composed validation in the Creator and future verifier.

## Next boundary

Implement an independent Handoff Envelope lineage verifier that accepts the
seven sources plus the persisted Envelope, rebuilds the expected Envelope
without writing, validates the embedded Package independently, and compares
metadata and complete business content field by field. Equivalent YAML layout
may pass; source or semantic drift must fail. Only after that gate should PMind
explore a provider-specific delivery adapter and its separate external-effect
authorization model.
