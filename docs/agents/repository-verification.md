# Repository Verification Runner

PMind uses the system-provided Rake already available with Ruby 2.6. No Gemfile, Bundler install, external package, network access, provider call, credential, remote CI, or deployment is required.

## Two distinct outcomes

```sh
rake verify
```

Runs dependency-free deterministic repository gates in order:

1. `compile` — `ruby -wc` for every Ruby file plus `Rakefile`; any stderr warning, unexpected stdout, or nonzero exit fails;
2. `yaml` — safe-load every YAML file with no permitted classes/symbols and aliases disabled;
3. `links` — verify repository-local Markdown targets;
4. `test` — load the complete Minitest suite in one Ruby process;
5. `evals` — run the canonical Eval repository validator.

Only after all five pass does it print `PMIND_LOCAL_DETERMINISTIC_VERIFICATION_PASS`. This proves the checked local contracts and tests, not calibration readiness, provider integration, production operation, or product effect.

```sh
PMIND_CALIBRATION_WORKSPACE_SET=/absolute/path/calibration-001 rake
# equivalent to:
PMIND_CALIBRATION_WORKSPACE_SET=/absolute/path/calibration-001 rake status
```

Runs `verify` and then the real calibration preflight. The task-specific
environment variable supplies the external evidence path as one argv value; it
is not stored in Git. The command deliberately preserves the preflight outcome:

- exit `0`: local gates and the frozen Workspace Set/startup-contract layer pass;
- exit `2`: local gates pass but calibration is blocked;
- other nonzero: a deterministic gate or preflight execution failed.

The current authoritative result with the verified external workspace set is
exit `0` with `PMIND_CALIBRATION_PREFLIGHT_READY gates=6/6`. Omitting the path
still exits `2` with `gates=5/6`, because a ready Wave manifest is not a
substitute for presenting the exact external workspace evidence to the current
process. Neither result proves any case, product effect, provider integration,
or enterprise outcome.

The 6/6 result verifies the frozen Workspace Set layer, not the filesystem
read boundary of a future Codex process. Scored launch remains separately
blocked until the actual launch path proves that the assigned arm is the only
readable project workspace and that repository/oracle/other-arm reads fail.
`scripts/render_calibration_role_briefing.rb` preserves this distinction and
does not emit a speculative launch command.

## Individual tasks

```sh
rake compile
rake yaml
rake links
rake test
rake evals
rake calibration
rake -T
```

`rake calibration` accepts the same environment variable and preserves exit
`2` whenever its six-gate evidence is blocked. Exit `0` does not cover the
separate Runtime Arm Isolation launch boundary. `rake -T` is task discovery
only and proves no gate result.

## Remaining configured-tool boundaries

Rake establishes a real task runner, so “no task-runner configuration” is no longer a blocker. Ruby static typing, a dedicated lint tool, and remote CI remain unconfigured and must continue to be reported `BLOCKED`; warning compilation and tests are alternative evidence, not substitutes labeled PASS.

Adding gems, a Gemfile, Steep/RBS, RuboCop/Standard, or a GitHub Actions workflow requires a deliberate toolchain decision and any applicable install or remote-execution authorization. The runner must not silently install or fetch them.
