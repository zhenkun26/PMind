# Calibration Role Briefing Copy v0

- Status: Experimental
- Version: `0.1.0`
- Surface: repository-local, read-only Markdown renderer
- Boundary: prepares role-specific briefings; it does not launch an arm or
  create calibration evidence

## Outcome

This copy contract turns one verified Calibration Wave and its exact external
Workspace Set into four least-privilege human briefings:

- the facilitator receives case order, both arm paths, oracle locations, and
  protocol stop conditions;
- the PMind operator receives sanitized Intake fields and only the PMind arm
  path for each case;
- each reviewer receives the frozen Rubric, case-specific oracle location, and
  only that reviewer's own assignment-scoped opaque ref.

The renderer must first obtain a `6/6` ready result from the existing
calibration preflight. A briefing is not a run authorization, a Downstream
Executor input artifact, an Acceptance Result, or product-effect evidence.

## Current launch blocker

The external Workspace Set proves that six clean arm copies exist and exclude
the fixture oracle. It does not prove that a running executor cannot read the
PMind repository or another arm through an absolute path.

The locally frozen Codex CLI supports `workspace-write`, but that mode alone
does not establish arm-only read access. A named minimal filesystem permission
profile can deny a shell probe against a sibling arm, but the current CLI
documentation and local `codex exec --help` do not expose a verified way to
apply that exact named profile to the non-interactive agent run while also
preserving authenticated model transport. Therefore the facilitator briefing
must say that scored launch remains blocked until an end-to-end runtime probe
proves all of the following for the actual launch path:

1. the assigned arm is readable and writable;
2. the PMind repository, oracle, and five other arms are unreadable;
3. local shell and fixture tests work;
4. Git, dependency installation, web/search tools, subprocess network, other
   external writes, and additional writable roots remain unavailable;
5. the probe and scored arm use the same frozen binary, model, reasoning, and
   runtime permission configuration.

The renderer does not print a speculative Codex launch command while this
proof is absent.

## Role disclosure matrix

| Information | Facilitator | PMind operator | Reviewer 1/2 |
| --- | --- | --- | --- |
| Case order | Yes | No | No |
| Baseline workspace path | Yes | No | No |
| PMind workspace path | Yes | Own working path only | No |
| Raw Intent and approved Intake context | May coordinate | Yes | No |
| Oracle location | Yes | No | Yes, after blinded result receipt |
| Other reviewer ref or assessment | No | No | No |
| Own reviewer ref | Not printed | Not printed | Yes |
| Product-effect/result claim | No | No | No |

Dynamic user-controlled text must pass through the shared Markdown safety
layer. The operator briefing may project only `raw_intent`, `user_profile`,
`context_available`, and the declared data policy. It must not render any
`oracle`, Acceptance Criteria, failure trap, material unknown, other-arm path,
or role assignment.

## CLI

```sh
ruby scripts/render_calibration_role_briefing.rb \
  --workspace-set /absolute/path/calibration-001 \
  --role facilitator
```

Valid roles are `facilitator`, `pmind_operator`, `reviewer_1`, and
`reviewer_2`. Output goes only to stdout. The command performs no model call,
does not create a packet file, and does not mutate the repository or Workspace
Set.

## Failure behavior

The renderer fails closed when:

- the role is absent or unsupported;
- the Workspace Set is absent, invalid, drifted, or not the exact Wave set;
- repository validation or any startup gate is blocked;
- a Wave case cannot be resolved to exactly one case definition;
- the repository already contains a run record for a Wave case, because v0 is
  a pre-first-run briefing rather than a progress dashboard.

Failure output uses `PMIND_CALIBRATION_ROLE_BRIEFING_ERROR`, prints no role
refs, raw Intent, oracle content, or submitted workspace path, and exits
nonzero.

## Evidence and non-claims

Tests must cover every role, role-to-role non-disclosure, missing/invalid
Workspace Sets, unsupported roles, Markdown-safe Intake projection, and
read-only Workspace Set verification before and after rendering.

A successful render proves only that the current role copy obeys this
repository contract. Runtime arm isolation, a scored attempt, an executor
result, independent review, First-pass Delivery Success, production Adapter
readiness, and enterprise landing remain unproven.
