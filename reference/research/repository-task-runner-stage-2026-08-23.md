# Repository task runner stage — 2026-08-23

- Status: dependency-free local runner implemented and executed
- Scope: repository-local engineering verification and status semantics
- External sources used: none
- Evidence basis: installed system Ruby/Rake, current Minitest suite, Eval validator, calibration preflight, safe YAML and local-link audits

## Exploration decision

The repository repeatedly executed the same gates through ad hoc shell commands and therefore reported task-runner verification as BLOCKED. Read-only discovery found `/usr/bin/rake` version 12.3.3 already installed with Ruby 2.6.10. Reusing it removes that blocker without adding a Gemfile, installing a gem, selecting a new language stack, or enabling remote CI.

The runner deliberately separates deterministic repository correctness from operational calibration readiness:

- `rake verify` may pass only compile, YAML, links, Minitest, and Eval validation;
- default `rake` / `rake status` must continue into calibration and propagate exit `2` while the Wave is blocked;
- `rake calibration` exposes the same preflight output and exit, not a converted success.

This avoids both failure modes: treating a valid blocked Wave as broken code, and treating green local tests as enterprise landing evidence.

## Implementation and copy plan

- standard library and installed Rake only;
- serial task order and one-process Minitest execution;
- warning compilation rejects any stderr warning, unexpected stdout, or nonzero exit;
- safe YAML disables aliases and arbitrary classes/symbols;
- local links exclude HTTP/mail/anchor targets and validate decoded filesystem paths;
- no install, Bundler resolution, network, provider, credential, external write, remote CI, or deployment;
- stable machine markers distinguish local PASS from calibration BLOCKED;
- docs state that static typing, dedicated lint, and CI remain separately blocked.

## Executed evidence

- task runner contract suite: PASS — 7 runs, 58 assertions;
- task discovery and dependency graph: PASS — `status` depends on `verify` then `calibration`; default depends on `status`;
- strict warning compilation: PASS — 83 compilation units including `Rakefile`;
- safe YAML: PASS — 82 files;
- local Markdown links: PASS — 106 files after final runner documentation was added;
- complete Minitest suite through default `rake`: PASS — 679 runs, 4,948 assertions, 0 failures/errors/skips;
- Eval structural validation through default `rake`: PASS — 10 cases, 3 fixtures, 1 Executor Profile, 1 calibration Wave, 0 acceptance results, 9 gap dimensions, 12 risk tags;
- `PMIND_LOCAL_DETERMINISTIC_VERIFICATION_PASS`: PASS — emitted only after all local prerequisites;
- calibration through default `rake`: BLOCKED — 3/6, exact existing role/Profile/workspace blockers, process exit `2`;
- secret-signature scan: PASS — 278 repository files;
- task-runner authority audit: PASS — fixed local Ruby calls, no environment/network/install token or shell command chain;
- debug/escape-hatch audit: PASS — none introduced in `Rakefile` or its contract test;
- task-runner configuration: PASS — project-owned `Rakefile` executed with installed Rake 12.3.3;
- Ruby static typing, dedicated lint, and CI: BLOCKED — no corresponding configuration or authorized toolchain; strict warning compilation and line-by-line review remain alternative evidence only;
- dependency installation and remote CI: NOT_APPLICABLE — neither was authorized or used.

## Remaining risk and next boundary

Rake 12.3.3 and Ruby 2.6.10 are old system components; the current runner is intentionally compatible but this does not select the future product runtime. Task-runner configuration is now real, while Ruby static typing, dedicated lint, and CI remain blocked. More importantly, calibration still needs four real role holders, six Executor decisions, and an authorized external workspace set; the runner cannot manufacture them.
