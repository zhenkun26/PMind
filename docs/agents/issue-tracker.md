# Issue Tracker: Local Markdown

PMind uses local Markdown until a remote tracker is explicitly configured and
the user authorizes its use.

## Layout

```text
.scratch/<feature-slug>/
├── spec.md
└── issues/
    ├── 01-<slug>.md
    └── 02-<slug>.md
```

- A spec starts with `Status: draft`.
- One ticket lives in each issue file.
- Ticket numbers follow dependency order, blockers first.
- Each ticket records `Status`, `Blocked by`, and observable acceptance
  criteria.
- Conversation notes append under `## Comments`; do not overwrite history.

Suggested local states are `draft`, `ready-for-agent`, `in-progress`,
`blocked`, and `done`. A user must approve a spec or ticket breakdown before
it becomes `ready-for-agent`.

## Remote boundary

“Publish” means “write a local file” in this repository. Do not create or
modify GitHub, GitLab, Linear, Jira, or other remote records unless the user
explicitly authorizes that external write in the current task.
