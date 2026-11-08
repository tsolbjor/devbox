# 0001. Record architecture decisions in docs/adr

- **Date:** 2026-11-08
- **Status:** Accepted

## Context

Most of the reasoning behind this repo lives in long code comments, commit messages
and the script table in CLAUDE.md. That reasoning is hard to find, and it is easy to
undo a decision without noticing that it was one. Examples: why .NET does not come
from apt, or why `/proc/version` is not used to detect WSL.

## Decision

Significant decisions are recorded as numbered, immutable markdown files in
`docs/adr/`, copied from [template.md](template.md). A decision that is reversed gets
a new ADR, and the old one is marked *Superseded by NNNN*. It is not edited away.
ADRs 0002–0013 were recorded retroactively from the code, CLAUDE.md and git history;
their dates are the dates of the commits that introduced them.

Planned work that is not yet decided or built goes in [`docs/plans/`](../plans/).
When a plan is carried out, the decisions it settles become ADRs.

## Consequences

Code comments can point to an ADR instead of re-arguing the case. A change that goes
against an ADR has to say so explicitly.
