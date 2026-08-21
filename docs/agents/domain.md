# Domain Document Rules

PMind currently uses a single context:

- Canonical glossary: `CONTEXT.md`
- System decisions: `docs/adr/`

Read the glossary before naming concepts in specs, tickets, interfaces, Evals,
or user-facing output. If a term conflicts with the glossary, surface the
conflict instead of silently inventing a synonym.

`CONTEXT.md` contains domain language only. Put implementation details in a
spec and durable, surprising trade-offs in an ADR. Create an ADR only when a
decision is costly to reverse, surprising without context, and the result of a
real trade-off.
