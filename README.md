# PMind

PMind explores how to turn a vague product intent into an evidence-backed,
testable Prompt Package that a downstream agent or delivery team can execute.

The repository is currently in a local-first Validation Sprint. Product
contracts, Eval schemas, and ten unrun seed cases exist; product code and the
runtime stack have not been selected yet.

Public repository: [zhenkun26/PMind](https://github.com/zhenkun26/PMind)

## Start here

- [Product and commercialization exploration](PMIND_EXPLORATION.md)
- [Domain glossary](CONTEXT.md)
- [Agent rules](AGENTS.md)
- [Skill adoption policy](docs/agents/skill-policy.md)
- [Third-party source review](reference/github/mattpocock__skills/analysis.md)
- [Eval direction](evals/README.md)
- [Prompt Package contract](docs/product/prompt-package-v0.md)
- [Seed calibration readiness](evals/calibration/README.md)

Validate the current contracts and calibration manifest without installing
dependencies:

```sh
ruby scripts/validate_evals.rb
```

## Current boundaries

- Work is local by default.
- GitHub, GitLab, deployment, publishing, commits, and pushes require explicit
  user authorization.
- Third-party Skills are pinned, reviewed, and adapted in the repository.
- A polished prompt is not accepted as quality evidence; PMind is evaluated by
  downstream delivery outcomes.
- Empty `run_records` and a blocked calibration Wave are not reported as
  successful experiments.
