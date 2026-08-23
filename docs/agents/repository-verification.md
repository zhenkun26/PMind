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
rake
# equivalent to:
rake status
```

Runs `verify` and then the real calibration preflight. The default command deliberately preserves the preflight outcome:

- exit `0`: local gates pass and calibration is actually ready;
- exit `2`: local gates pass but calibration is blocked;
- other nonzero: a deterministic gate or preflight execution failed.

The current authoritative result is exit `2` with `PMIND_CALIBRATION_PREFLIGHT_BLOCKED gates=3/6`. Do not relabel it as a failed test suite or as an all-green project.

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

`rake calibration` preserves exit `2` for a valid blocked Wave. `rake -T` is task discovery only and proves no gate result.

## Remaining configured-tool boundaries

Rake establishes a real task runner, so “no task-runner configuration” is no longer a blocker. Ruby static typing, a dedicated lint tool, and remote CI remain unconfigured and must continue to be reported `BLOCKED`; warning compilation and tests are alternative evidence, not substitutes labeled PASS.

Adding gems, a Gemfile, Steep/RBS, RuboCop/Standard, or a GitHub Actions workflow requires a deliberate toolchain decision and any applicable install or remote-execution authorization. The runner must not silently install or fetch them.
