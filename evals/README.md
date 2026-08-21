# PMind Eval Baseline

- Current case schema: `evals/schema/case-v0.yaml` (`0.2.0`)
- Current acceptance-result schema: `evals/schema/acceptance-result-v0.yaml` (`0.1.0`)
- Current rubric: `evals/rubrics/first-pass-success-v0.md` (`0.1.0`)
- Seed set: 10 synthetic, ready, unrun cases under `evals/cases/seed/`
- Calibration fixtures: 3 synthetic, executable fixtures under `evals/fixtures/`
- Calibration: `evals/calibration/wave-01.yaml` remains blocked until roles,
  executor settings, and isolated arm workspaces are ready
- Runtime framework: intentionally not selected

PMind will be evaluated by downstream delivery outcomes, not by whether an
optimized prompt sounds polished.

## Initial experiment

Collect at least 30 paired cases: 10 synthetic calibration cases followed by
20 real, previously unsolved tasks. For each case preserve:

- raw Intent and target Downstream Executor;
- baseline handoff without PMind;
- Clarifications and Evidence used by PMind;
- generated Prompt Package;
- downstream output and human corrections;
- latency, model / search cost, and number of clarification and rework rounds;
- acceptance result and failure reason.

The experiment is paired:

- baseline receives the immutable raw Intent;
- PMind receives a Prompt Package produced under `docs/product/` contracts;
- both arms use the same executor, workspace revision, tools and time policy;
- a case facilitator retains the oracle and answers only questions actually asked;
- the executor never receives oracle fields or the other arm's result.

## Primary metrics

- First-pass Delivery Success;
- material clarification and rework reduction;
- time from Intent to Handoff;
- Evidence citation coverage and validity;
- acceptance-criterion pass rate;
- user acceptance, cost, and latency.

## Case quality rules

- Inputs must be real or explicitly labeled synthetic.
- Expected outcomes must be independently defined, not copied from model
  output.
- Facts, judgement rubrics, and safety requirements are scored separately.
- Model, prompt, Skill, Reference, and dataset versions must be recorded.
- Failed and ambiguous cases remain in the dataset as regression evidence.

## Current assets

- `docs/product/prompt-package-v0.md`: semantic Handoff contract;
- `docs/product/clarification-policy-v0.md`: gap and stopping policy;
- `docs/product/review-lenses-v0.md`: six-lens Quality Gate;
- `docs/product/concierge-runbook-v0.md`: manual operating and paired-test protocol;
- `evals/schema/case-v0.yaml`: provider-neutral case definition;
- `evals/schema/acceptance-result-v0.yaml`: two-reviewer decisions, adjudication state, and derived primary outcome;
- `evals/rubrics/first-pass-success-v0.md`: binary primary outcome and diagnostic scores;
- `evals/cases/seed/`: calibration cases. All have empty `run_records` until actually run.
- `evals/schema/calibration-wave-v0.yaml`: calibration readiness contract;
- `evals/schema/fixture-v0.yaml`: Fixture isolation, inventory, digest, and check contract;
- `evals/schema/workspace-set-v0.yaml`: generated isolated-arm receipt contract;
- `evals/schema/executor-profile-v0.yaml`: executor fairness, safety, and freeze contract;
- `evals/fixtures/`: three ready synthetic workspaces with executor-excluded oracles;
- `evals/calibration/executor-profiles/`: truthful draft/frozen executor decisions;
- `evals/calibration/wave-01.yaml`: first three-case Wave and honest blockers;
- `scripts/validate_evals.rb`: dependency-free structural, artifact-path, success-formula, and adjudication-state checks.
- `scripts/prepare_calibration_workspaces.rb`: no-overwrite preparation and verification of external arm copies.
- `scripts/calibration_preflight.rb`: read-only readiness report across contracts, roles, executor, and arm copies.

The executable runner will be selected only after the manual protocol and
Rubric are calibrated. No framework is assumed or installed at this stage.

Run the current deterministic checks with:

```sh
ruby scripts/validate_evals.rb
ruby test/validate_evals_test.rb
ruby test/acceptance_result_test.rb
ruby scripts/calibration_preflight.rb
```

The last command currently exits with a blocked status by design; it must not be
treated as a failed experiment.

## Measurement contract status

Case Schema `0.2.0` adds immutable executor/model/profile/workspace receipts,
separate Handoff and result durations, and executor/material rework counts. A
real `run_record` is valid only when its `input.md`, `result.md`,
`acceptance.yaml`, frozen `executor-profile.yaml`, and `workspace-set.yaml`
receipt exist under the directory encoded by its run ID. The validator hashes
the two preserved YAML receipts and rejects stale run-record digests.

The acceptance result preserves two independent assessments and permits only
three states:

- `consensus`: both primary decisions match and the matching final decision is locked;
- `needs_adjudication`: primary decisions differ and no final decision exists;
- `adjudicated`: primary decisions differ and a distinct third reviewer records the final decision.

The validator derives First-pass Delivery Success from the frozen blocking
criteria and Rubric gates, then cross-checks it against the run outcome. There
are currently zero acceptance results and zero real runs; the contract being
ready is not product-effect evidence.
