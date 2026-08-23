# Calibration Wave 01 ready stage — 2026-08-23

- Status: startup gates ready; no calibration arm has run
- Scope: roles, balanced Executor Profile, isolated workspace evidence, and
  repository status-path integration
- External sources used: none; evidence is the authorized user declaration,
  observed local binary/model response, repository contracts, and generated
  external workspace receipt

## Authorized decisions

- The user confirmed four different real participants hold the four Wave roles
  and keeps the identity mapping offline.
- Four random assignment-scoped opaque refs were generated with Ruby
  `SecureRandom`; no name, email, job title, or mapping was written to Git.
- The balanced profile uses the exact observed `codex-cli
  0.149.0-alpha.4.1` binary with SHA-256
  `09db9560f6f9dec139d3324254fb3c8fdbad5ecce1d8c794113dc15294f6aefd`.
- `gpt-5.6-terra` was requested through an ephemeral, read-only, no-tool Codex
  run with `model_reasoning_effort=medium`; the request returned the exact
  expected marker and usage metadata. This proves request-time availability of
  the selected identifier, not an immutable backend snapshot or product effect.
- The frozen policy is standard mode, medium reasoning, fresh context per arm,
  disabled network, arm-only file/shell/local-test capability, prohibited Git,
  dependency install, oracle, other-arm and external-write access, 30 minutes
  per arm, and one scored attempt.
- Production Adapter work remains deferred. Ruby 3.4, RuboCop, Steep/RBS, and
  read-only GitHub Actions remain authorized for a later stage after Wave 01
  starts; no dependency or workflow was installed in this slice.

## Workspace evidence

The repository-owned preparer created one previously absent workspace set at
the exact user-authorized external path. It produced three cases and six arm
copies, then verified the published result again. The receipt reports
`status=ready`, `oracle_included=false`, three cases, and six arms. The target
was not overwritten and no deletion was performed.

File copying is not an operating-system sandbox. Each real executor must still
be rooted in only its assigned arm and must be prevented from accessing the
other arm, the PMind repository, and external state.

## Status interface decision

The prior Rake task had no way to submit an external workspace path, so a ready
Wave could only appear blocked to `rake status`. The smallest bounded repair is
the task-specific `PMIND_CALIBRATION_WORKSPACE_SET` input. Rake passes it as one
argv value to the existing preflight and performs no shell expansion, lookup,
or persistence.

- with the verified path: calibration preflight is `READY gates=6/6`, exit 0;
- without a path: preflight remains `BLOCKED gates=5/6`, exit 2;
- neither result is a calibration case result, Acceptance Result, First-pass
  Delivery Success measurement, provider proof, or enterprise landing claim.

## Focused evidence

- safe Eval repository validation: PASS — 10 cases, 3 fixtures, 1 frozen
  Executor Profile, 1 ready Wave, 0 acceptance results;
- profile digest binding: PASS — Wave revision matches the exact frozen Profile;
- external workspace creation: PASS — 3 cases, 6 arms;
- independent external workspace verification: PASS — 3 cases, 6 arms;
- workspace manifest audit: PASS — ready, no oracle, exact case/arm counts;
- Rake task-runner contract: PASS — 8 runs, 63 assertions;
- readiness-copy contract: PASS — 6 runs, 58 assertions;
- complete repository Minitest suite: PASS — 680 runs, 4,956 assertions,
  0 failures/errors/skips;
- deterministic repository marker: PASS — emitted after strict compilation,
  safe YAML, local Markdown links, the complete tests, and Eval validation;
- explicit-workspace Rake calibration: PASS — 6/6, exit 0;
- missing-workspace Rake calibration: truthful BLOCKED — 5/6, exit 2;
- static typing, dedicated lint, remote CI: BLOCKED — deliberately deferred;
- calibration execution and product effect: NOT_APPLICABLE — no arm has run.

## Post-ready runtime finding

A later same-day role-launch exploration narrowed the meaning of this stage:
the 6/6 result proves the frozen repository and copied Workspace Set layer, not
the read scope of an authenticated Codex process. Broad read plus workspace
write could still read a sibling arm. Until the actual launch mechanism passes
the Runtime Arm Isolation probe described in
`calibration-role-briefing-and-runtime-isolation-2026-08-23.md`, scored launch
remains blocked. This clarification does not invalidate the Workspace Set
digests or oracle-exclusion receipt.

## Recovery and next boundary

The Wave can start only while the binary digest, selected model configuration,
four-role separation, workspace receipt, Rubric, and fixture digests remain
unchanged. The next boundary is an end-to-end Runtime Arm Isolation mechanism;
only after it passes may the three cases execute in the frozen arm order,
followed by two independent reviews and real
`run_records`/Acceptance Results. Any drift returns the Wave to blocked; it
must not be patched around or recorded as a successful run.
