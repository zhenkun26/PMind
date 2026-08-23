# Calibration and landing decision options — 2026-08-23

- Status: decision analysis only; no gate was changed
- Scope: calibration roles, frozen Executor Profile, external workspaces,
  production Adapter authority, and Ruby engineering gates
- Retrieval date: 2026-08-23 (Asia/Shanghai)

## Executive recommendation

Treat the five requested inputs as three sequential decisions, not one blanket
authorization:

1. unblock the current three-case calibration with four real, distinct role
   holders, a balanced frozen Executor Profile, and a durable external
   workspace root;
2. run and review the calibration before selecting a production Adapter;
3. modernize the Ruby toolchain and add read-only CI after the product evidence
   boundary is clear, without relabeling CI as calibration or product-effect
   evidence.

The recommended calibration baseline is the exact locally installed Codex CLI
build, a currently available balanced model, medium reasoning, disabled
network, arm-only file/shell/test tools, 30 minutes per arm, and one scored
attempt. At freeze time, account availability and the exact effective model
must be observed rather than inferred.

## 1. Opaque role references

### Problem solved

The four refs demonstrate role separation without committing unnecessary names,
emails, or other personal data. The facilitator controls the protocol, the
PMind operator runs the PMind arm, and two reviewers score independently. This
reduces oracle leakage, operator self-scoring, and false consensus.

### Options

- Four internal humans: strongest practical starting point and lowest external
  coordination cost, but internal reviewers may share organizational bias.
- Two internal operators plus two external reviewers: stronger commercial
  credibility and neutrality, but higher scheduling, confidentiality, and
  review cost.
- Mixed human/agent or one person acting sequentially: useful only for a
  separately labelled protocol dry-run. It is not equivalent to the current
  blinded Wave and must not be used to claim independent product effect.

Recommended: four real, distinct humans for Wave 01; use external reviewers in
a later pilot. Generate a random assignment-scoped identifier for each role
and keep the identity mapping outside Git. Do not use names, emails, job titles,
or invented placeholders as the committed refs.

## 2. Frozen Executor Profile

### Problem solved by each field

- `executor_version`: makes client/harness behavior reproducible.
- `model_version`: prevents an alias or silent model change from confounding
  baseline-versus-PMind differences.
- `reasoning_settings`: fixes the amount of model deliberation.
- `tool_policy`: prevents oracle, other-arm, Git, dependency, network, or
  external-write leakage.
- `time_limit_minutes`: equalizes effort and bounds schedule/cost.
- `max_attempts`: prevents one arm from receiving hidden retries; a single
  scored attempt matches First-pass Delivery Success most directly.

### Candidate profiles

| Profile | Model tier | Reasoning | Network | Time | Attempts | Trade-off |
| --- | --- | --- | --- | ---: | ---: | --- |
| Economy | Luna | medium | disabled | 20 min | 1 | Lowest cost and fastest; higher risk of underestimating PMind value on harder cases |
| Balanced | Terra | medium | disabled | 30 min | 1 | Best default for protocol calibration; meaningful capability without flagship cost |
| Quality-first | Sol | high | disabled | 45 min | 1 | Highest expected capability; slower and more expensive, and may compress the observable gap between arms |

Recommended: Balanced. The locally observed executable is
`codex-cli 0.149.0-alpha.4.1`; because it is an alpha build, freeze its exact
version and do not update it mid-Wave. Confirm the selected model is actually
available to the account before freezing. Use generic allowed-tool identities
that map to the real executor, limited to arm file read/write, shell, and local
tests. Keep Git, dependency installation, external writes, oracle access,
other-arm access, and network prohibited.

OpenAI's current official model guidance positions Sol for flagship complex
work, Terra for intelligence/cost balance, and Luna for high-volume cost-
sensitive work. It recommends medium reasoning as a balanced starting point and
requires representative evals before increasing effort. Current listed API
prices are $4/$20, $2/$12, and $0.20/$1.20 per million input/output tokens for
Sol, Terra, and Luna respectively. Codex subscription accounting may differ,
so those API prices are comparison evidence, not a forecast of this Wave's
bill.

## 3. External workspace root

### Problem solved

Each case needs a baseline copy and a PMind copy with the same frozen digest,
without `oracle/`, the other arm, or repository state. The preparer also refuses
relative paths, repository-nested paths, existing targets, symlink roots, and
silent overwrite. File copies alone are not an operating-system sandbox, so
each executor must still be restricted to its assigned arm.

### Options

- `/private/tmp/pmind-calibration-001`: fastest and naturally disposable;
  suitable for a rehearsal, but vulnerable to cleanup/reboot and weak for
  durable audit.
- `/Users/yuzheng/PMind-Calibration/calibration-001`: durable and easy to
  inspect; requires explicit permission to create/use an external parent and a
  cleanup policy.
- Encrypted external volume or enterprise-controlled workspace: strongest
  operational separation; unnecessary cost for the current synthetic fixtures,
  but appropriate for future confidential customer cases.

Recommended: the durable user-local path for Wave 01, with permission limited
to creating and verifying that exact workspace set. The parent must exist and
the final `calibration-001` target must not exist before preparation. After
acceptance evidence is copied into its governed record, retain the workspace
for a defined short period, then remove it through a separately approved,
recoverable cleanup.

## 4. Production Adapter scope

### Problem solved

A production Adapter turns a verified local Handoff Envelope into an actual
external delivery. It therefore needs separate decisions for provider,
credential reference, live health check, destination write, idempotency,
retention/export/purpose policy, cost ceiling, dispatch window, attempts, and
stop conditions. Runtime readiness, dispatch authorization, and execution
receipt must remain distinct.

### Options

- No production Adapter yet; continue local-file concierge: no credentials or
  network cost and easiest to audit, but no remote integration evidence.
- GitHub App adapter to a sandbox repository: concrete value for coding teams,
  reviewable receipts, and narrow repository permissions; risks include data
  disclosure, unwanted issue/PR creation, token scope, and workflow triggers.
- Owned generic webhook adapter: provider-neutral and easy to contract-test;
  lower immediate user value and requires an owned test service.
- OpenAI Responses API executor: can perform the downstream work directly and
  capture model usage, but introduces API credentials, token cost, provider
  availability, and a materially larger execution/safety boundary.

Recommended: do not authorize a production Adapter until the three-case
calibration yields reviewable results. Then use a GitHub App in a dedicated
sandbox repository as the first concrete remote adapter, with read metadata and
create-only delivery permissions, no production repo, no secret in Git, one
exact dispatch per confirmation, no automatic PR merge/deploy, and a zero
provider-usage cost ceiling unless the dispatch intentionally triggers a paid
executor. Add an API executor only after this receipt path is proven.

## 5. Dependencies, static analysis, and remote CI

### Problem solved

The existing Rake runner proves deterministic local contracts, but not a
supported Ruby runtime, dedicated lint policy, static interface consistency,
or reproducibility on a clean remote machine. CI is engineering evidence only;
it cannot manufacture calibration roles, workspaces, acceptance results, or
provider readiness.

### Options

- Keep dependency-free Rake only: zero installation and lowest maintenance;
  static typing, dedicated lint, and clean-machine CI remain blocked.
- Balanced modernization: pin a maintained Ruby version, Bundler lockfile,
  RuboCop, gradual Steep/RBS coverage, and a read-only GitHub Actions job. This
  has moderate adoption cost and fits the current Ruby code without runtime
  annotation dependencies.
- Strict Sorbet program: fast, scalable, gradual static and optional runtime
  checks; more source annotations, RBI/Tapioca machinery, and toolchain surface
  than this small contract-heavy repository currently justifies.

Recommended: Balanced modernization, but after calibration is launched. Move
from the current system Ruby 2.6.10, which Ruby lists as EOL, to Ruby 3.4.x
rather than adopting Ruby 4.0 immediately; Ruby 3.4 remains under normal
maintenance and is a more conservative compatibility target. Pin dependency
versions in `Gemfile.lock`; configure RuboCop explicitly; introduce Steep first
at stable contract/library seams and publish the actual checked scope rather
than calling partial coverage full typing.

For GitHub Actions, use a standard hosted runner, `permissions: contents: read`,
no repository secrets, no write/deploy step, and pin third-party actions to
reviewed full commit SHAs. Run deterministic `rake verify`, lint, and the
declared type scope. Do not run default `rake status` as an all-green CI gate,
because calibration legitimately needs real external roles and workspaces.
GitHub states that standard hosted Actions usage is free for public
repositories, while larger runners and storage can still incur charges.

## Proposed approval sequence

1. Confirm the four real role holders and permit creation of random opaque
   assignment refs with an off-repository mapping.
2. Freeze the Balanced Executor Profile after observing the exact model/account
   availability.
3. Authorize the exact durable workspace path and create/verify the six arm
   copies.
4. Run Wave 01 and review its acceptance evidence.
5. Decide whether the evidence justifies a sandbox GitHub Adapter.
6. Authorize Ruby modernization, pinned dependencies, and read-only CI as a
   separate engineering change.

## Source register

| Source | Version/date | Trust | Actual reuse |
| --- | --- | --- | --- |
| [OpenAI model catalog](https://developers.openai.com/api/docs/models) | retrieved 2026-08-23 | official primary documentation | Current Sol/Terra/Luna positioning, model IDs, reasoning levels, context and listed API prices |
| [OpenAI GPT-5.6 model guidance](https://developers.openai.com/api/docs/guides/latest-model) | retrieved 2026-08-23 | official primary documentation | Medium reasoning baseline and representative-eval selection guidance |
| [Ruby maintenance branches](https://www.ruby-lang.org/en/downloads/branches/) | retrieved 2026-08-23 | official primary documentation | Ruby 2.6 EOL and maintained 3.4/4.0 comparison |
| [RuboCop installation](https://docs.rubocop.org/rubocop/installation.html) and [configuration](https://docs.rubocop.org/rubocop/latest/configuration.html) | retrieved 2026-08-23 | official project documentation | Pinned Bundler dependency and explicit target/config recommendation |
| [Steep repository documentation](https://github.com/soutaro/steep) | retrieved 2026-08-23 | official project repository | RBS-based gradual type-checking trade-off |
| [Sorbet official documentation](https://sorbet.org/docs/overview) | retrieved 2026-08-23 | official project documentation | Alternative static/runtime typing trade-off |
| [GitHub Actions secure-use reference](https://docs.github.com/en/actions/reference/security/secure-use) | retrieved 2026-08-23 | official primary documentation | Least privilege and full-SHA action pinning |
| [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) | retrieved 2026-08-23 | official primary documentation | Public standard-runner cost boundary |

## Assumptions and limits

- Role holders have not been identified; no opaque ref in this document is an
  assignment or evidence.
- The local Codex CLI version was observed read-only, but selected model
  availability, effective model identity, subscription limits, and cost were
  not tested.
- No dependency compatibility test, install, workflow run, provider call,
  credential access, workspace creation, or dispatch occurred.
- Recommendations are inferences from PMind's present synthetic fixtures and
  sources above; calibration results may change the production choice.
