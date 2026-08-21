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
