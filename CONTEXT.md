# PMind Domain Glossary

This file defines product language only. Architecture and implementation
decisions belong in specs or ADRs.

## Core terms

### Intent

A user's initial expression of the outcome they want. An Intent may be vague,
incomplete, contradictory, or unsupported by evidence.

Avoid: using “prompt” when referring to the user's underlying need.

### Clarification

A question or resolved answer that reduces a material gap in an Intent. PMind
prioritizes Clarifications by information gain and stops when remaining gaps no
longer change the result materially.

### Evidence

A source-backed fact used to shape or validate a result. Evidence records its
source, retrieval date, version, license where relevant, and confidence.

Avoid: treating an unsupported model statement as Evidence.

### Reference

A reviewed external artifact retained for Evidence or adaptation, such as a
repository, Skill, framework, specification, or official document. A Reference
is untrusted until its provenance, license, and safety have been assessed.

### Prompt Package

PMind's structured handoff artifact. It combines the resolved Intent, scope,
constraints, Evidence, assumptions, execution instructions, output contract,
acceptance criteria, Evals, risks, and Approval Points.

Avoid: “optimized prompt” when the artifact contains more than prompt text.

### Quality Gate

The review and Eval boundary a Prompt Package must pass before Handoff. A
Quality Gate checks executability, traceability, risk, and acceptance evidence.

### Eval

A repeatable case and scoring rule that measures whether a Prompt Package or
downstream result meets an observable criterion.

Avoid: using subjective writing quality as the only Eval.

### Downstream Executor

The Agent, development team, workflow, or system that receives a Prompt
Package and attempts delivery.

### Handoff

The controlled transfer of an approved Prompt Package and its context to a
Downstream Executor.

### Handoff Proposal

A pending decision artifact that presents the boundaries of one exact,
Handoff-ready Prompt Package. A Handoff Proposal is not a Handoff or an
authorization to perform one.

Avoid: “Handoff authorization” or “Handoff” when the user has only been shown
the proposal.

### Handoff Confirmation Receipt

An immutable record of a user's choice about one exact Handoff Proposal. A
confirmed Receipt authorizes a future controlled Handoff, but does not prove
that the Handoff occurred or that any external effect was approved.

Avoid: “completed Handoff” when only the choice has been recorded.

### Handoff Envelope

A local, provider-neutral bundle containing one exact Prompt Package and the
confirmed authorization lineage for its future controlled Handoff. A Handoff
Envelope with delivery state `prepared` has not been transferred to or
accepted by a Downstream Executor.

Avoid: “delivered,” “received,” or “running” when only a local Envelope exists.

### Handoff Adapter

A channel-specific component capable of transferring a verified Handoff
Envelope to a Downstream Executor. Describing or selecting an Adapter does not
run it or authorize its effects.

Avoid: “Handoff” or “dispatch” when only Adapter metadata has been inspected.

### Adapter Capability Profile

A reviewed, declarative account of one Handoff Adapter's delivery mode,
receipt, idempotency, retry, data, cost, and side-effect boundaries. A Profile
is evidence for a decision, not an authorization or proof of implementation.

Avoid: “Adapter configuration” when no executable Adapter has been configured.

### Adapter Selection Proposal

A pending, zero-effect decision artifact bound to one exact verified Handoff
Envelope and one exact reviewed Adapter Capability Profile. It does not mean an
Adapter has been selected, authorized, or run.

Avoid: “Adapter selection” when only a Proposal exists.

### Adapter Selection Confirmation Receipt

An immutable record of a user's choice about one exact Adapter Selection
Proposal. A confirmed Receipt records which reviewed Profile was selected for
which verified Envelope, but never authorizes dispatch or Adapter effects.

Avoid: “Adapter authorized,” “ready to dispatch,” or “Adapter running” when
only the selection has been recorded.

### Payload Data Attestation

An immutable result of a completed review of one exact Handoff Envelope
payload against the selected Adapter Capability Profile's data policy. It
records compatibility or a data blocker, but never authorizes dispatch or
Adapter effects.

Avoid: “dispatch approved” or “payload delivered” when only data compatibility
has been established.

### Adapter Effect Authorization Proposal

A pending, zero-authority decision artifact bound to one exact compatible
Payload Data Attestation and its selected Adapter Capability Profile. It
enumerates exactly the Profile's true effects and required disclosures, but
does not record a user choice, grant an effect, or authorize dispatch.

Avoid: “effects authorized,” “dispatch approved,” or “Adapter activated” when
only the Proposal has been previewed.

### Adapter Effect Authorization Confirmation Receipt

An immutable record of a user's choice about one exact Adapter Effect
Authorization Proposal. A confirmed Receipt grants consent only for the exact
named effects in that Proposal; the effects remain non-executable until all
implementation and dispatch gates pass.

Avoid: “effects executed,” “dispatch authorized,” or “Adapter running” when
only named effect consent has been recorded.

### Adapter Implementation Attestation

An immutable result of a completed review of one exact Adapter implementation
identity against one exact reviewed Capability Profile and confirmed named-
effect Receipt. It records compatibility or an implementation blocker, but
never proves runtime readiness, credentials, provider health, effect
executability, or dispatch.

Avoid: “runtime ready,” “Adapter activated,” or “Adapter running” when only an
implementation review declaration has been validated.

### Adapter Runtime Readiness Attestation

An immutable result of a completed review of one exact compatible Adapter
implementation and runtime configuration against submitted credential-
reference, provider-health, data-lifecycle, and environment evidence. It
records ready or blocked, but never proves PMind performed the checks, makes
effects executable, or authorizes dispatch.

Avoid: “PMind verified the credentials,” “provider connected,” “Adapter
running,” or “dispatch ready” when only a runtime review declaration has been
validated.

### Adapter Dispatch Proposal

A pending, zero-dispatch decision artifact bound to one exact ready Runtime
Readiness Attestation, payload, Adapter, destination, idempotency key, validity
window, cost ceiling, and stop-condition set. It presents one proposed dispatch
for confirmation but never saves a choice, starts the Adapter, or calls the
provider.

Avoid: “dispatch authorized,” “delivery started,” or “provider called” when
only a Dispatch Proposal has been previewed.

### Adapter Dispatch Confirmation Receipt

An immutable confirm, modify, or reject choice bound to one exact Adapter
Dispatch Proposal and all of its source bytes. A confirmed Receipt authorizes
only that dispatch and its exact cost ceiling when applicable; it does not make
effects executable or record an attempt, provider call, delivery, write, or
cost.

Avoid: “dispatch executed,” “provider contacted,” or “delivery complete” when
only a Dispatch Confirmation Receipt has been validated.

### Adapter Dispatch Execution Preflight

A point-in-time, submitted-evidence gate over one exact confirmed Dispatch
Receipt. It derives ready or blocked from validity, credential, provider-health,
destination, idempotency, effect-scope, cost-budget, and stop-condition facts,
but does not perform those external checks or execute the dispatch.

Avoid: “live checks passed,” “idempotency reserved,” or “ready means executed”
when only a repository-local Preflight declaration has been validated.

### Adapter Execution Receipt

An immutable outcome record for one actual Adapter dispatch attempt, bound to
the exact authorized chain, payload, destination, idempotency key, executed
effects, delivery evidence, time, and cost facts. The local reference producer
records only an isolated local-file attempt; other producers require their own
provider-specific evidence and authority.

Avoid: “provider delivered,” “production-ready,” or “product effect proven”
when a Receipt records only the local reference capability.

### Execution Verification Report

An immutable record that one exact persisted Adapter Execution Receipt and its
source chain passed an actual verifier at a stated time. A local report proves
only that local audit event and cannot be promoted into provider, production,
calibration, or product-effect evidence.

Avoid: “provider receipt,” “delivery certified,” or “production verified” when
the report covers only a local reference bundle.

### Calibration Workspace Readiness

A repository preflight result proving that the frozen Wave, roles, Executor
Profile, Fixtures, and six external arm copies are internally consistent. It
does not prove that a running Downstream Executor is unable to read another arm
or the repository oracle.

Avoid: “runtime isolated” or “safe to launch” when only Workspace Set copying
and digest verification have passed.

### Runtime Arm Isolation

An enforced execution boundary that lets one scored Downstream Executor read
and write only its assigned arm while denying the PMind repository, oracle,
other arms, network tools, Git, dependency installation, and external writes.
It requires an end-to-end probe of the actual launch path, not a prompt-level
instruction or working-directory convention.

### Calibration Role Briefing

A read-only, least-privilege projection of one ready Wave for exactly one real
participant role. A Briefing coordinates responsibilities and allowed inputs;
it does not start an arm, persist a run, or prove Runtime Arm Isolation.

### First-pass Delivery Success

A Handoff that the Downstream Executor completes without material
re-specification or large-scale rework. This is PMind's proposed north-star
outcome.

### Approval Point

A decision that requires explicit human authorization before PMind or a
Downstream Executor may continue, especially for external writes, sensitive
data, cost, permissions, or irreversible actions.

### External Write

Any action that changes state outside the local PMind working tree, including
creating issues, pushing Git, publishing, messaging, deploying, or modifying a
connected service.
