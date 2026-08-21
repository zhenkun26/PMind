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

## 2026-08-21 — Create confirmed Clarification revisions

- [2026-08-21T23:16:06+08:00] Session revision test edit L0: the first multi-hunk patch used an inaccurate helper-method context and was rejected without changing the test, fix: re-read the exact insertion points and split the test and helper additions into smaller hunks, prevention: refresh exact helper boundaries before patching a long existing test file
- [2026-08-21T23:16:46+08:00] Session revision time test L1: the first regression value equaled rather than predated the Fixture's latest round time, fix: move the revision timestamp one minute before the actual boundary, prevention: read the concrete Fixture timestamp before choosing temporal boundary values
- [2026-08-21T23:18:00+08:00] Confirmation Receipt Schema assertion L1: the secret-declaration test expected a shortened generic Schema error instead of the validator's `expected constant false` contract, fix: assert the exact stable substring emitted by the shared validator, prevention: reuse existing Schema error vocabulary when adding structural rejection tests

## 2026-08-21 — Verify Clarification revision lineage

- [2026-08-21T23:45:00+08:00] archive audit command L0: a dense zsh one-liner embedded conflicting Ruby and shell quote forms and failed before running any audit, fix: split the checks into small commands with simple literal patterns, prevention: avoid nested regex literals inside single-quoted shell programs during final archive verification

## 2026-08-21 — Preview Prompt Package compilation

- [2026-08-21T23:43:00+08:00] ready revision Fixture rehearsal L0: repeated the known `require_relative` failure inside a Ruby `-e` program, fix: load the repository script through `require File.expand_path(...)`, prevention: copy the existing absolute-load aggregate runner pattern whenever Ruby code has no backing file

## 2026-08-22 — Create confirmed Prompt Packages

- [2026-08-22T00:08:16+08:00] final Package safe-copy test L1: the first assertion expected Markdown safety to escape both link brackets and parentheses even though the shared layer safely breaks link syntax by escaping the brackets, fix: assert the existing safe output contract exactly, prevention: inspect shared sanitizer semantics before specifying character-by-character escaping expectations
- [2026-08-22T00:09:57+08:00] final Package archive docs L0: a multi-file patch used a compressed-snapshot sentence that did not exactly match the long exploration document and was rejected without changes, fix: refresh each document's exact tail and split archival updates by file, prevention: re-read exact long-paragraph context immediately before patching cumulative exploration logs
- [2026-08-22T00:11:17+08:00] compilation metadata validator L1: line-by-line review found that `Hash#dig` could raise when an invalid Package combined compilation metadata with a non-object Handoff, fix: normalize malformed Handoff to an empty Hash before business validation and add a regression test, prevention: business validators must remain total after Schema errors and use shape-safe access for every untrusted nested value
- [2026-08-22T00:12:08+08:00] final Package repository verification static gate: Ruby static typing, RuboCop lint, and CI checks are BLOCKED because the repository defines no corresponding configuration, fix: use the permitted alternative evidence of `ruby -w -c`, full Minitest, safe YAML loading, persistence-path tests, and line-by-line review, prevention: keep missing-tool evidence explicitly BLOCKED until the project deliberately adopts a Ruby static/lint/CI toolchain
- [2026-08-22T00:13:07+08:00] final Package secret audit L1: zsh kept a space-delimited scalar as one filename so the first `rg` scan emitted an IO error while the wrapper incorrectly printed PASS, fix: rerun with an explicit zsh file array and require a clean no-match exit, prevention: never rely on implicit scalar word splitting in zsh audit wrappers and treat any scanner IO error as failure

## 2026-08-22 — Verify Prompt Package lineage

- [2026-08-22T00:21:09+08:00] persisted Package lineage repository verification static gate: Ruby static typing, RuboCop lint, and CI checks remain BLOCKED because the repository has no matching configuration, fix: execute the permitted alternative evidence of `ruby -w -c`, full Minitest, safe YAML loading, real five-file replay, and line-by-line review, prevention: preserve the BLOCKED label until a deliberate Ruby static/lint/CI toolchain decision is made
- [2026-08-22T00:21:37+08:00] Creator-to-verifier CLI rehearsal L1: the Creator success copy still said the lineage verifier was unimplemented after the verifier contract and CLI had been added, fix: replace the stale sentence with the active replay gate and add a copy regression assertion, prevention: search and exercise every user-facing predecessor copy when a deferred capability becomes available

## 2026-08-22 — Preview Handoff proposals

- [2026-08-22T00:29:36+08:00] Handoff Proposal Fixture digest rehearsal L0: a Ruby `-e` command repeated the known `require_relative` base-path failure, fix: load the repository script with `require File.expand_path(...)`, prevention: use absolute `require` for every file loaded from an inline Ruby program
- [2026-08-22T00:35:00+08:00] Handoff Proposal focused tests L1: two rejection tests expected a later reconstruction error and an unquoted Schema constant although existing validators correctly failed earlier and emitted quoted values, fix: align assertions with `persisted compilation lineage requires a Handoff-ready Package` and the stable quoted constant fragment, prevention: inspect shared validator error ordering and exact emitted vocabulary before fixing new negative-test strings
- [2026-08-22T00:36:00+08:00] Handoff Proposal test repair L0: a broad replacement changed the adjacent business-tampering assertion instead of the not-ready assertion and swapped their expected errors, fix: patch both methods with their names as exact context, prevention: use method-scoped hunks when neighboring tests contain the same assertion fragment
- [2026-08-22T00:42:00+08:00] Handoff Proposal repository verification calibration gate: calibration preflight remains BLOCKED at 3/6 because four roles, six Executor Profile decisions, and isolated arm workspaces are not supplied, fix: keep this product-contract slice separate and preserve the honest blocked Wave, prevention: do not interpret Handoff Proposal contract coverage as authorization to invent people, runtime decisions, or real run evidence
- [2026-08-22T00:43:00+08:00] Handoff Proposal repository verification static gate: Ruby static typing, RuboCop lint, and CI checks remain BLOCKED because the repository defines no Gemfile, type configuration, lint configuration, task runner, or CI workflow, fix: use the permitted alternative evidence of `ruby -w -c`, full Minitest, safe YAML loading, six-file CLI zero-write tests, and line-by-line review, prevention: preserve the BLOCKED label until the project deliberately adopts a Ruby static/lint/CI toolchain

## 2026-08-22 — Preview Handoff confirmations

- [2026-08-22T00:47:29+08:00] Handoff Confirmation repository verification calibration gate: calibration preflight remains BLOCKED at 3/6 because four roles, six Executor Profile decisions, and isolated arm workspaces are not supplied, fix: keep the authorization-contract slice independent and preserve the honest blocked Wave, prevention: never treat a valid Handoff Receipt fixture as a real user confirmation, completed calibration run, or product-effect result
- [2026-08-22T00:47:29+08:00] Handoff Confirmation repository verification static gate: Ruby static typing, RuboCop lint, and CI checks remain BLOCKED because the repository has no corresponding configuration, fix: execute alternative evidence with `ruby -w -c`, full Minitest, safe YAML loading, seven-file zero-write/state-matrix tests, and line-by-line authorization review, prevention: preserve the BLOCKED label until a deliberate Ruby static/lint/CI toolchain decision is made
- [2026-08-22T00:47:54+08:00] Handoff Confirmation data-boundary review L2: the initial Receipt shape stored a raw user response without its own personal-data declaration, fix: require `contains_personal_data` and reject public classification when it is true, prevention: every new persisted or validated raw-user-text artifact must carry an independent personal-data declaration even when its upstream Proposal has none

## 2026-08-22 — Create confirmed Handoff Envelopes

- [2026-08-22T00:52:00+08:00] repository context read L0: the initial context command used the nonexistent ADR path `docs/adr/0001-product-boundaries.md`, fix: enumerate `docs/adr/` and read the actual `0001-local-first-curated-skills.md`, prevention: resolve cumulative documentation filenames with `rg --files` before batching required reads
- [2026-08-22T00:53:00+08:00] runbook location lookup L0: a documentation search included the nonexistent path `docs/validation/calibration-runbook.md`, fix: enumerate `docs/` and use the actual `docs/product/concierge-runbook-v0.md`, prevention: discover documentation paths before passing an explicit cumulative file list to `rg`
- [2026-08-22T01:05:00+08:00] Handoff Envelope declaration scope review L2: the initial Envelope draft promoted Confirmation Receipt personal-data and secrets flags to root fields, which could falsely describe the embedded Prompt Package as scanned, fix: move them under authorization with confirmation-specific names and retain data classification as the whole-Envelope control, prevention: scope every inherited privacy declaration to the exact bytes or content it actually attests
- [2026-08-22T01:09:00+08:00] Handoff Envelope repository verification calibration gate: calibration preflight remains BLOCKED at 3/6 because four roles, six Executor Profile decisions, and isolated arm workspaces are not supplied, fix: preserve the honest blocked Wave and keep this local persistence slice separate, prevention: never treat a synthetic confirmed Receipt or prepared Envelope as a real participant assignment, executor decision, run, Handoff, or product-effect result
- [2026-08-22T01:09:00+08:00] Handoff Envelope repository verification static gate: Ruby static typing, RuboCop lint, and CI checks remain BLOCKED because the repository has no corresponding configuration, fix: execute the permitted alternative evidence of `ruby -w -c`, full Minitest, safe loading of all tracked YAML, eight-file persistence-path tests, and line-by-line authorization review, prevention: preserve the BLOCKED label until a deliberate Ruby static/lint/CI toolchain decision is made
- [2026-08-22T01:12:00+08:00] Handoff Envelope secret audit compatibility L0: the first changed-file scanner repeated the documented unsupported `Hash#filter_map` call and stopped before scanning, fix: replace it with `map` followed by `compact`, prevention: search Error Memory for known runtime compatibility limits before composing final archive one-liners
- [2026-08-22T01:13:00+08:00] Handoff Envelope archive staging environment L0: sandboxed `git add` could not create `.git/index.lock`, fix: retry the explicitly authorized staging operation with repository-scoped escalated Git permission, prevention: expect `.git` metadata writes to require escalation even when worktree files are writable
