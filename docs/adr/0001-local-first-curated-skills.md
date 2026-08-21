# ADR 0001: Use a Local-first Curated Skill Workflow

- Status: Accepted
- Date: 2026-08-21

## Context

PMind is a greenfield exploration with no remote tracker or implementation
stack. The selected upstream Skills contain useful engineering methods, but
some assume remote issue publication, cross-agent syntax, or commit-oriented
workflows. Loading the entire upstream collection would also consume discovery
context and widen the supply-chain surface.

## Decision

Use a curated subset of `mattpocock/skills`, pinned to one upstream commit and
copied into `.agents/skills/`. Keep specs and tickets in local Markdown. Adapt
side-effect language so remote writes and Git commits require explicit user
authorization. Record provenance, license, security findings, and local
changes under `reference/`.

## Consequences

- PMind can use mature engineering methods without allowing them to own the
  complete product process.
- Local copies are reviewable and work without a remote tracker.
- Upstream updates require a deliberate diff and may need manual conflict
  resolution.
- PMind must maintain its local safety adaptations.

## Alternatives considered

- Install every upstream Skill: rejected because it expands context and risk
  before a demonstrated need.
- Use the upstream collection unchanged: rejected because remote publication
  and authorization semantics do not match PMind's policy.
- Recreate every method from scratch: rejected because the reviewed upstream
  methods provide useful, licensed prior art.
