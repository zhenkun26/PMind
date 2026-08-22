# Handoff Adapter selection stage — 2026-08-22

- Status: provider-neutral Capability Profile and zero-effect Selection Proposal implemented
- Scope: repository-local product, copy, and implementation exploration
- External sources used: none
- Evidence basis: PMind glossary, existing Envelope lineage contract, repository authorization policy, prior Handoff research

## Decision

The next smallest valuable boundary after Envelope lineage verification is not a real Adapter. It is a reviewed Adapter Capability Profile plus a pending Adapter Selection Proposal that binds one exact Envelope and one exact Profile.

This preserves provider neutrality while exposing the channel decisions that were intentionally excluded from the Envelope: delivery mode, receipt, idempotency, retry, data limits, cost, and concrete side effects. A synthetic local-file candidate proves the contract without implementing file transfer or choosing PMind's first commercial provider.

## Implemented invariants

- the complete eight-file Envelope lineage is replayed first;
- the Proposal binds verifier-read Envelope bytes and separately read Profile bytes by SHA-256;
- only a `reviewed` Profile can be proposed;
- every declared true effect exactly matches one required future effect authorization;
- reviewed Profiles require a receipt and internally consistent idempotency, retry, and cost policies;
- Profile and Proposal data classification cannot be lower than the Envelope;
- Proposal time cannot predate either source;
- Proposal status is exactly `pending`;
- Adapter selection, dispatch, external effects, and inferred high-risk authorization remain false;
- the preview has no file, model, network, process, notification, cost, production-data, or external-service effect;
- success copy hides paths, digests, IDs, raw Intent/answers, Evidence sources, decision owners, and internal field paths.

## Copy plan

The title is “Handoff Adapter 选择提案待确认，尚未选择或交付”. Copy may show the Profile display name, delivery/receipt/idempotency/retry capabilities, true effects as still unauthorized, data classification, and three choices. It must explicitly say that selection is unsaved and no dispatch or channel effect is authorized.

## Newly exposed data gap

The Envelope has a whole-artifact data classification, but its personal-data and secret declarations are scoped only to the Handoff Confirmation response. They do not attest to the embedded Prompt Package. Therefore the Proposal cannot honestly claim personal-data or secret compatibility, even when the Profile declares a policy.

The v0 Proposal records both compatibility results as `unknown` and copy requires a separate payload review before dispatch. This is a product finding, not a test limitation: a commercial Adapter boundary needs content-level data attestation or an equivalent service-enforced scan.

## Risks and trade-offs

The Profile's `reviewed` state proves only that its declaration passed PMind's deterministic checks; it does not prove an executable Adapter matches those claims. Provider-specific implementation will need contract and integration tests, authentication/tenant controls, receipt validation, bounded failure cleanup, idempotency and retry drills, observability, and secret management.

The Profile uses a closed v0 vocabulary. New channel effects require a deliberate Schema version rather than silently accepting arbitrary strings. This makes authorization coverage testable at the cost of extending the contract when a truly new effect appears.

## Next boundary

Create an immutable Adapter Selection Confirmation Receipt that binds all ten files and captures confirm/modify/reject without dispatch. A confirmed Receipt may record which reviewed Profile was selected, but must keep dispatch and every effect authorization false. Before any real Adapter, add payload data attestation for personal-data/secret compatibility and obtain explicit authorization for every true Profile effect.
