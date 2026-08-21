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
