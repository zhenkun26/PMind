# Error Memory

## 2026-08-21 — Bootstrap PMind agent workflow

- [2026-08-21T17:16:30+08:00] install selected skills environment: referenced a nonexistent bundled Python path, fix: resolve and use `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`, prevention: run `command -v python3` before invoking repository-external helper scripts
- [2026-08-21T17:16:52+08:00] install selected skills transport: Python ZIP download failed CA certificate verification before writing destination files, fix: use the installer's supported `--method git` transport, prevention: prefer the already-verified Git transport in this workspace
- [2026-08-21T17:21:41+08:00] validate selected skills environment: system Python lacked the validator's PyYAML dependency, fix: resolve and reuse the read-only bundled workspace Python before considering any install, prevention: load workspace dependencies before running bundled validation scripts with non-stdlib imports
- [2026-08-21T17:22:04+08:00] validate selected skills environment: bundled workspace Python also lacked PyYAML, fix: stop Python retries, inspect `quick_validate.py`, and run an equivalent Ruby YAML validation, prevention: probe the required import once before selecting a Python runtime and keep a dependency-free fallback
- [2026-08-21T17:23:21+08:00] validate selected skills references: strict link and dependency checks treated three example context links and a `$skill-name` syntax placeholder as real targets, fix: express examples and syntax without fake resolvable targets, prevention: keep template examples visually distinct from live repository links and concrete Skill references

## 2026-08-21 — Define PMind validation contracts

- [2026-08-21T17:59:46+08:00] seed case coverage L1: the first contract check found no seed case covering the `handoff` clarification dimension, fix: add a report-versus-implementation Handoff decision to `seed-006`, prevention: validate the union of required gap dimensions before considering the seed set complete
- [2026-08-21T18:01:00+08:00] protocol documentation edit L0: a multi-file patch had a malformed hunk boundary and was rejected before changing files, fix: split the edit into one valid hunk per target file, prevention: keep each `Update File` section self-contained and close its hunk before the next file header
- [2026-08-21T18:50:22+08:00] Eval validator regression L1: the first test expected JSON Schema validation to reject a cross-field outcome/failure inconsistency, fix: assert Schema acceptance and case-set business-rule rejection separately, prevention: keep structural Schema assertions distinct from cross-field protocol invariants in tests
- [2026-08-21T18:51:35+08:00] archive safety scan L1: an over-broad `sk-` pattern treated the Skill name `ask-matt` as an API key, fix: require a non-word prefix and at least 20 token characters, prevention: use length- and boundary-aware secret signatures instead of short substring matches
- [2026-08-21T18:52:43+08:00] archive staged diff L0: `git diff --cached --check` found an extra blank line at EOF in 16 new files that unstaged checks could not see, fix: normalize only the reported file endings and restage, prevention: run staged diff checks after adding untracked files because ordinary `git diff --check` excludes them

## 2026-08-21 — Prepare executable calibration Fixtures

- [2026-08-21T19:06:00+08:00] calibration readiness regression L1: a ready-wave test still expected the former `fixture must be ready` error after all three Fixture manifests became ready, fix: narrow the assertion to the still-unsatisfied role and executor gates, prevention: make transition tests assert the invariant being protected rather than a temporary blocker that the change intentionally removes

## 2026-08-21 — Prepare isolated calibration workspaces

- [2026-08-21T19:32:00+08:00] generated-root inventory L1: the verifier sorted actual root entries but compared them with an unsorted expected array, so every valid prepared set was rejected before publication, fix: compare against the expected lexical order, prevention: sort both sides or define inventory constants in canonical order when enforcing exact directory layouts

## 2026-08-21 — Archive calibration execution readiness

- [2026-08-21T20:05:00+08:00] staged EOF regression L0: `git diff --cached --check` again found double-newline EOFs in 21 newly staged Fixture and Schema files, fix: normalize the exact reported files and recompute every affected frozen workspace digest, prevention: run a whole-file EOF normalizer before first staging whenever a phase adds generated or bulk-created files
- [2026-08-21T20:06:00+08:00] EOF normalizer L0: the first `ruby -pi` formatter was line-oriented and therefore could not collapse a separate blank line at file end, fix: read and rewrite each exact file as a whole byte string, prevention: do not use line-loop editing modes for whole-file boundary invariants

## 2026-08-21 — Harden calibration measurement contract

- [2026-08-21T20:35:00+08:00] validator edit L0: one patch declared two update operations for the same file and was rejected before changing it, fix: combine all validator hunks under one update operation, prevention: use one `Update File` section per target in each patch
- [2026-08-21T20:48:00+08:00] receipt-integrity edit L0: a multi-file patch used a stale test hunk context and was rejected before changing files, fix: re-read the exact helper layout and apply smaller target-specific patches, prevention: refresh nearby context after adding tests before batching follow-up edits

## 2026-08-21 — Validate Clarification Session lineage

- [2026-08-21T22:00:00+08:00] Clarification Session tests L0: the initial test draft attempted assignment through `Hash#dig`, which Ruby does not allow, fix: assign through the parent Hash returned by `dig` or direct indexing, prevention: reserve `dig` for reads and use explicit parent indexing for every nested mutation
- [2026-08-21T22:20:00+08:00] Clarification documentation edit L0: a multi-file patch expected an unwrapped sentence that is split across Markdown lines and was rejected before changing files, fix: re-read exact sections and apply smaller file-specific hunks, prevention: refresh wrapped prose context before batching documentation updates

## 2026-08-21 — Preview Clarification revisions

- [2026-08-21T23:10:00+08:00] revision preview test Fixtures L1: the first test run supplied a priority score below the existing deterministic formula and used a single backslash in a double-quoted Ruby Markdown assertion, fix: align the Fixture score with the formula and escape the literal backslash twice, prevention: construct priority Fixtures from the shared scoring rule and assert Markdown escapes with Ruby string semantics in mind
- [2026-08-21T23:20:00+08:00] full YAML verification command L0: the safe-load one-liner permitted `Date` before requiring Ruby's date library, fix: require `date` before building the permitted class list, prevention: explicitly load every non-core class named in standalone verification one-liners
- [2026-08-21T23:21:00+08:00] full YAML verification compatibility L0: the workspace Ruby/Psych does not provide `YAML.safe_load_file`, fix: pass `File.read(path)` to the supported `YAML.safe_load` API, prevention: reuse the repository's dependency-free parsing pattern instead of assuming newer Psych convenience methods
- [2026-08-21T23:22:00+08:00] aggregate test loader compatibility L0: `require_relative` cannot infer a base path from a Ruby `-e` program, fix: require each test through `File.expand_path`, prevention: use absolute loads in command-line aggregate runners and reserve `require_relative` for file-backed scripts
- [2026-08-21T23:25:00+08:00] preflight exit assertion shell L0: the wrapper assigned zsh's read-only `status` variable after the expected blocked exit, fix: use the task-specific `pmind_preflight_exit` variable, prevention: never reuse shell-reserved or common system variable names in verification wrappers
- [2026-08-21T23:28:00+08:00] staged secret scanner compatibility L0: the workspace Ruby lacks `Hash#filter_map`, fix: collect matches with `map` followed by `compact`, prevention: keep archive verification one-liners compatible with the repository's oldest supported Ruby surface
