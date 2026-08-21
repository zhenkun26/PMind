# mattpocock/skills Adoption Analysis

## Decision

Adopt a curated, pinned, locally modified subset as PMind's engineering method
library. Do not use it as PMind's complete product-management, evaluation, or
enterprise-governance layer.

## Installed selection

| Skill | PMind use | Local adaptation |
| --- | --- | --- |
| `setup-matt-pocock-skills` | Repository workflow configuration | Local Markdown default; no automatic remote writes or commits |
| `grill-with-docs` | Clarification plus glossary / ADR upkeep | Codex `$skill-name` invocation |
| `grilling` | Decision-tree questioning | Installed as a direct dependency of `grill-with-docs` |
| `domain-modeling` | Canonical vocabulary and selective ADRs | Upstream method retained |
| `research` | Primary-source investigation | Fixed `reference/research/` location; provenance and no-execution rule |
| `to-spec` | Conversation-to-spec synthesis | Local draft and approval before ready / remote publication |
| `to-tickets` | Tracer-bullet task decomposition | Local default; explicit authorization before remote publication |
| `tdd` | Red-green vertical slices | Codex `$codebase-design` invocation |
| `diagnosing-bugs` | Repro-first diagnosis | Commit / PR text is a suggestion until authorized |
| `codebase-design` | Deep-module vocabulary | Upstream method retained |
| `code-review` | Standards and spec review | Codex setup invocation syntax |
| `handoff` | Cross-session compaction | Codex `$skill-name` invocation syntax |

The five explicit orchestration Skills also drop the upstream
`disable-model-invocation` frontmatter field, which the current Codex
validator does not support. Their existing `agents/openai.yaml` files retain
`allow_implicit_invocation: false`, so invocation remains explicit-only.
The local `handoff` copy also drops the unsupported `argument-hint`
frontmatter field; its behavior remains described in the Skill body.

The local copy also converts three illustrative multi-context paths in
`domain-modeling/CONTEXT-FORMAT.md` from Markdown links to code-formatted
examples so repository link validation does not treat nonexistent example
contexts as real references.

## Deferred upstream Skills

- `triage`: no remote tracker or label lifecycle yet.
- `wayfinder`: no large codebase or multi-session implementation map yet.
- `improve-codebase-architecture`: no implemented architecture to survey.
- `prototype`: install when a concrete design question needs it.
- `implement`: deferred until its commit behavior is fully adapted to PMind's
  explicit authorization rule.
- `resolving-merge-conflicts`: install when a real conflict exists.

## Update procedure

1. Fetch a candidate upstream commit into a temporary review directory.
2. Compare only installed paths against the current pinned version.
3. Re-run license, script, external command, cross-Skill reference, and
   side-effect scans.
4. Reapply or revise PMind adaptations deliberately.
5. Update `source.yaml`, this analysis, and the security review.
6. Validate before any commit or publication.
