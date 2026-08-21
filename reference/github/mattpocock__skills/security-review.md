# Security Review: mattpocock/skills

- Reviewed commit: `0ab1b63a410a03d3627979a109c8695de27af954`
- Review date: 2026-08-21
- Scope: the 12 installed Skill directories only
- Result: accepted with local overrides

## Findings

### Remote tracker writes

Upstream setup templates document `gh` and `glab` commands. `to-spec` and
`to-tickets` originally describe publication to the configured tracker.

Mitigation: PMind configures local Markdown, centralizes the external-write
rule in `AGENTS.md`, and locally modifies both Skills so remote publication
requires explicit authorization.

### Git commits and pull requests

The selected set does not include upstream `implement`. `diagnosing-bugs`
mentions recording the root cause in a commit / PR message.

Mitigation: the local copy treats this as suggested text and explicitly
forbids commit, push, or PR creation without authorization.

### Scripts

The selected set contains
`.agents/skills/diagnosing-bugs/scripts/hitl-loop.template.sh`. It is a template
for human-in-the-loop diagnosis and was not executed during installation or
review.

Mitigation: all Skill scripts are treated as inert data until their exact
inputs, outputs, and side effects are separately reviewed and execution is
authorized.

### Prompt injection and retrieved content

The research method reads external sources, which may contain instructions
aimed at the Agent.

Mitigation: the local research Skill treats retrieved text as untrusted
evidence, restricts output to `reference/research/`, records provenance, and
forbids executing retrieved code by default.

### Cross-Skill and agent assumptions

Some upstream text says “Skill tool” or uses slash-command conventions. Some
methods request background or parallel agents.

Mitigation: installed direct dependencies are present, cross-Skill references
are localized to `$skill-name`, and all agent use remains subject to active
platform and repository instructions.

Five orchestration Skills used an unsupported legacy
`disable-model-invocation` frontmatter key. The local copies remove it and
preserve explicit-only invocation through `agents/openai.yaml` policy.

## Residual risk

- Natural-language rules can still be misinterpreted and are not a hard
  security boundary.
- Future upstream updates may reintroduce side effects or change dependencies.
- The unused GitHub and GitLab templates remain in the setup Skill as reference
  material and must not be treated as authorization.

Enterprise enforcement must eventually live in code: tool allowlists, tenant
isolation, approvals, audit, budget gates, and data policy.
