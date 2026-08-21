# PMind

PMind explores how to turn a vague product intent into an evidence-backed,
testable Prompt Package that a downstream agent or delivery team can execute.

The repository is currently in a local-first Validation Sprint. Product
contracts, Eval schemas, ten unrun seed cases, and three executable calibration
Fixtures exist; product code and the runtime stack have not been selected yet.

Public repository: [zhenkun26/PMind](https://github.com/zhenkun26/PMind)

## Start here

- [Product and commercialization exploration](PMIND_EXPLORATION.md)
- [Domain glossary](CONTEXT.md)
- [Agent rules](AGENTS.md)
- [Skill adoption policy](docs/agents/skill-policy.md)
- [Third-party source review](reference/github/mattpocock__skills/analysis.md)
- [Eval direction](evals/README.md)
- [First-pass success rubric](evals/rubrics/first-pass-success-v0.md)
- [Prompt Package contract](docs/product/prompt-package-v0.md)
- [Clarification user copy contract](docs/product/clarification-copy-v0.md)
- [Clarification Answer Receipt contract](docs/product/clarification-answer-receipt-v0.md)
- [Clarification Revision Proposal contract](docs/product/clarification-revision-proposal-v0.md)
- [Clarification Confirmation Receipt contract](docs/product/clarification-confirmation-receipt-v0.md)
- [Clarification Revision Lineage Verification contract](docs/product/clarification-revision-lineage-v0.md)
- [Prompt Package Compilation Proposal contract](docs/product/prompt-package-compilation-proposal-v0.md)
- [Prompt Package Compilation Confirmation Receipt contract](docs/product/prompt-package-compilation-confirmation-receipt-v0.md)
- [Prompt Package Creation contract](docs/product/prompt-package-creation-v0.md)
- [Prompt Package Lineage Verification contract](docs/product/prompt-package-lineage-v0.md)
- [Handoff Proposal contract](docs/product/handoff-proposal-v0.md)
- [Handoff Confirmation Receipt contract](docs/product/handoff-confirmation-receipt-v0.md)
- [Machine-readable product schemas](schemas/README.md)
- [Seed calibration readiness](evals/calibration/README.md)
- [Calibration Fixtures](evals/fixtures/README.md)

Validate the current contracts and calibration manifest without installing
dependencies:

```sh
ruby scripts/validate_evals.rb
```

Validate a Prompt Package without installing dependencies or modifying it:

```sh
ruby scripts/validate_prompt_package.rb path/to/package.yaml
```

Validate Clarification Session state, then optionally verify that a compiled
Prompt Package preserves its auditable lineage:

```sh
ruby scripts/validate_clarification_session.rb path/to/session.yaml
ruby scripts/validate_clarification_session.rb path/to/session.yaml --prompt-package path/to/package.yaml
```

Render validated Session state as user-facing Markdown without modifying it:

```sh
ruby scripts/render_clarification_copy.rb path/to/session.yaml
```

Dry-run a user Answer Receipt against the current Session without applying it:

```sh
ruby scripts/preview_clarification_answers.rb path/to/session.yaml path/to/receipt.yaml
```

Validate a proposed answer normalization and preview its candidate Session as
safe user-confirmation Markdown without writing either input:

```sh
ruby scripts/preview_clarification_revision.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml
```

Validate the user's exact choice against all three source files, then create a
new no-overwrite Session revision only when that choice is confirmed:

```sh
ruby scripts/preview_clarification_confirmation.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml
ruby scripts/create_clarification_revision.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml path/to/new-session.yaml
```

Independently replay and verify a persisted revision against the same four
confirmed source files without modifying any of them:

```sh
ruby scripts/verify_clarification_revision_lineage.rb path/to/session.yaml path/to/receipt.yaml path/to/proposal.yaml path/to/confirmation.yaml path/to/new-session.yaml
```

Preview a candidate Prompt Package against a persisted ready Session revision,
without creating or handing off the Package:

```sh
ruby scripts/preview_prompt_package_compilation.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml
```

Validate the user's exact compilation choice against all three bound source
files, then create a new final Package only for the confirmed, ready state:

```sh
ruby scripts/preview_prompt_package_compilation_confirmation.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml
ruby scripts/create_prompt_package.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml
ruby scripts/verify_prompt_package_lineage.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml
ruby scripts/preview_handoff_proposal.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml path/to/handoff-proposal.yaml
ruby scripts/preview_handoff_confirmation.rb path/to/new-session.yaml path/to/draft-package.yaml path/to/compilation-proposal.yaml path/to/compilation-confirmation.yaml path/to/final-package.yaml path/to/handoff-proposal.yaml path/to/handoff-confirmation.yaml
```

The creator replays the full chain, preserves the draft's business content,
adds immutable compilation lineage, refuses overwrite, and creates the final
file with `0600` permissions. It does not perform Handoff.
The verifier then replays the same four sources and compares every persisted
field without modifying any file; success permits only a controlled Handoff
decision, not an automatic Handoff.
The Handoff Proposal preview then binds that exact final file, replays all five
lineage inputs, and shows recipient, scope, action boundaries, stop conditions,
open items, Approval Points, and three choices. It neither saves the choice nor
authorizes or performs Handoff.
The Handoff Confirmation preview then binds the user's exact choice to all six
source files. Only `confirmed` may authorize a future controlled Handoff;
external effects, pending Approval Points, and actual dispatch remain separate.

The repository also contains a no-overwrite preparer for creating six isolated
calibration arm copies outside the repository. See
[Seed calibration readiness](evals/calibration/README.md) before using it; a
prepared copy is not by itself an executor sandbox or a completed experiment.
`scripts/calibration_preflight.rb` combines those receipts with the tracked
Executor Profile and four-role separation gates before any run may start.

## Current boundaries

- Work is local by default.
- GitHub, GitLab, deployment, publishing, commits, and pushes require explicit
  user authorization.
- Third-party Skills are pinned, reviewed, and adapted in the repository.
- A polished prompt is not accepted as quality evidence; PMind is evaluated by
  downstream delivery outcomes.
- Empty `run_records` and a blocked calibration Wave are not reported as
  successful experiments.
- A scored run requires two independent reviewer assessments and either direct
  consensus or a distinct third-reviewer adjudication.
- A Prompt Package cannot mark Handoff ready while a blocking unknown, Review
  Lens block, unresolved reference, or authorization contradiction remains.
- A Clarification Session cannot become ready to compile while a critical gap,
  blocking unknown, question-priority violation, unresolved conflict, or
  unmarked high-risk action remains.
- User-facing Clarification copy never includes raw Intent, saved answers,
  internal priorities, source references, or decision-maker identifiers.
- An Answer Receipt dry-run never normalizes an answer, mutates Session state,
  or treats an ordinary response as high-risk authorization.
- A Revision Proposal preview applies its delta only in memory, revalidates the
  complete candidate Session, and never records confirmation or risk approval.
- A Confirmation Receipt binds exact input-file digests. Only `confirmed` may
  create a new `0600` Session file; inputs are never overwritten and high-risk
  Approval Points remain separate.
- A persisted revision is not trusted by presence alone; lineage verification
  must deterministically replay the confirmed sources and match every Session
  field before the revision proceeds downstream.
- A Compilation Proposal binds one exact ready Session revision and draft
  Package, but its pending confirmation never creates a Package, authorizes
  Handoff, or changes any high-risk Approval Point.
- A Compilation Confirmation Receipt permits future local Package creation
  only for `confirmed` plus a Handoff-ready draft; every choice keeps Handoff
  and high-risk authorization false.
- Final Package creation preserves every draft business field, adds only
  immutable compilation lineage, and cannot overwrite a path or infer Handoff.
  Independent persisted-Package lineage replay must pass before a controlled
  Handoff decision; verification itself does not authorize or perform Handoff.
- A Handoff Proposal is valid only for the exact byte digest of a lineage-
  verified, Handoff-ready final Package. It remains pending with Handoff,
  external effects, and inferred high-risk authorization all set to false.
- A Handoff Confirmation Receipt binds all six proposal-chain files and the
  user's response digest. Confirmation permits only a future controlled
  transfer of that exact Package to its declared recipient; it does not execute
  Handoff or authorize external effects and pending high-risk actions.
