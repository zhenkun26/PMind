# ADR 0005: Separate Calibration Workspace Readiness from Runtime Arm Isolation

- Status: Accepted
- Date: 2026-08-23

## Context

Wave 01 has a frozen Executor Profile and six digest-identical external arm
copies without oracle files. The repository preflight can therefore verify all
six startup gates. Its Workspace Set evidence does not by itself restrict a
future Codex process from reading an absolute path to the PMind repository or a
sibling arm.

A local probe showed that a broad read profile plus current-workspace write can
read a sibling arm. A minimal named filesystem profile can deny that shell
read, but the frozen CLI has no currently verified non-interactive launch path
that applies the same named boundary end to end while preserving authenticated
model transport.

## Decision

Keep Workspace Set readiness and Runtime Arm Isolation as distinct evidence:

- `calibration_preflight.rb` continues to report the six frozen repository and
  copied-workspace gates truthfully;
- no scored Codex launch occurs until the actual launch path passes an
  end-to-end arm-isolation probe using the same runtime permission
  configuration as the scored attempt;
- role Briefings disclose only least-privilege inputs and explicitly withhold
  a launch command while that runtime evidence is absent;
- prompts, working-directory conventions, and file-copy layout cannot satisfy
  the Runtime Arm Isolation requirement.

Future isolation evidence must be bound to the exact binary/Profile and prove
current-arm read/write, local-test execution, denied repository/oracle/other-arm
reads, and denied Git/dependency/network/external-write capabilities.

## Consequences

- A `6/6 READY` workspace preflight remains useful and truthful, but is no
  longer phrased as sufficient launch proof.
- Wave 01 remains at zero runs until a container, VM, dedicated OS identity, or
  documented managed Codex permission path passes the end-to-end probe.
- The role-copy surface can be implemented and reviewed without weakening the
  blind protocol or inventing a command that exceeds current evidence.
- Runtime isolation work becomes the next operational slice; Ruby 3.4 tooling
  and production Adapter work remain deferred as previously decided.

## Alternatives considered

- Treat `workspace-write` plus a prompt prohibition as arm-only isolation:
  rejected because sibling reads remain possible.
- Mark the copied Workspace Set invalid: rejected because its digests,
  inventories, and oracle exclusion are valid evidence for a different layer.
- Start a non-scored rehearsal with combined roles: rejected for this Wave
  because it would not prove the frozen blind protocol and could contaminate
  later scored attempts.
