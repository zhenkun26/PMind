# Calibration role Briefing and Runtime Arm Isolation — 2026-08-23

- Status: role-copy slice implemented; scored launch remains blocked
- Scope: Wave 01 human Briefings and the filesystem boundary of the frozen
  Codex CLI launch
- Retrieval date: 2026-08-23 (Asia/Shanghai)
- External code executed: none
- Model calls performed for this slice: none

## Decision

The next useful PMind slice is a read-only, least-privilege role Briefing
renderer, not another Adapter contract and not a fabricated calibration run.
It prepares facilitator, PMind-operator, and independent-reviewer copy while
preserving zero run records.

Do not print or execute a scored Codex command yet. The existing external
Workspace Set proves clean copies and oracle exclusion, but not the read scope
of a live executor process. Runtime Arm Isolation must become separate launch
evidence bound to the frozen binary/Profile.

## Sourced facts

- Official OpenAI CLI documentation describes `codex exec` as the stable
  non-interactive interface, `--ephemeral` as disabling persisted rollout
  files, `--ask-for-approval` as the approval policy, and `workspace-write` as
  the recommended unattended local-write sandbox rather than a claim that all
  non-workspace reads are denied.
- The official configuration reference defines named permission profiles with
  `:minimal`, `:workspace_roots`, explicit `read`/`write`/`deny` filesystem
  rules, and a separate network policy.
- The same configuration reference says workspace-write can exclude `/tmp`
  and `$TMPDIR` from writable roots and can disable sandboxed command network;
  these settings govern command permissions, not the provider transport needed
  for the model request.

## Local observations

Evidence was collected against the frozen
`codex-cli 0.149.0-alpha.4.1` binary without invoking a model:

1. the current binary exposes `codex sandbox` directly, while the fetched
   command page still displayed a platform-qualified form in one section;
2. a named profile extending broad read access and adding current-workspace
   write successfully read a sibling arm, proving that a working directory and
   write sandbox alone are insufficient;
3. a named profile containing only `:minimal` read plus current workspace write
   rejected `../pmind/README.md` with `Operation not permitted` while allowing
   the current arm read;
4. the frozen `codex exec --help` output does not expose the sandbox helper's
   `--permission-profile` option, so the successful shell probe is not evidence
   that the identical profile governs an authenticated non-interactive agent
   run;
5. Docker CLI is installed, but the current managed environment cannot access
   the Docker daemon. No image was pulled, container started, dependency
   installed, credential mounted, or external workspace changed.

Items 2–4 are local observations, not claims made by OpenAI documentation.

## Product and copy implications

- `6/6 READY` must be qualified as Workspace Set/startup-contract readiness.
- The facilitator receives both arm paths and oracle locations but also the
  explicit launch blocker.
- The PMind operator receives only sanitized Intake fields and PMind paths;
  no oracle, Acceptance Criteria, baseline path, or role ref is rendered.
- Each reviewer receives only its own opaque ref, the Rubric, and oracle paths
  to use after receiving a blinded result; no arm label, order, path, raw
  Intent, or other reviewer ref is rendered.
- Renderer success remains zero-effect and cannot be promoted into a run,
  review, consensus, or First-pass Delivery Success claim.

## Next isolation options

| Option | Strength | Cost / limitation | Recommendation |
| --- | --- | --- | --- |
| Dedicated container/VM or OS identity mounting one arm only | Clear kernel-level filesystem boundary and repeatable probe | Requires runtime setup, authenticated model transport, and explicit environment authority | Preferred operational direction |
| Managed Codex named permission profile applied to the actual agent launch | Native policy vocabulary and least extra machinery | Must establish a documented/observed `exec` application path and protect auth material from tool reads | Explore if available to this account/build |
| Prompt-only prohibition plus working directory | No setup | Sibling/repository reads remain possible and evidence is not enforceable | Rejected for scored Wave |

The next implementation should define an end-to-end Runtime Isolation Probe
and immutable evidence shape only after selecting one actual launch mechanism.
That choice changes environment and credential handling, so it is not inferred
inside this slice.

## Source register

| Source | Version/date | Trust | Actual reuse |
| --- | --- | --- | --- |
| [OpenAI Codex developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli) | retrieved 2026-08-23 | official primary documentation | `codex exec`, approval, sandbox, ephemeral and command-safety semantics |
| [OpenAI Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) | retrieved 2026-08-23 | official primary documentation | named filesystem permission profiles, workspace roots, deny rules and network settings |

No source content was copied into executable code. Documentation facts,
local observations, product inferences, and recommendations are separated
above.
