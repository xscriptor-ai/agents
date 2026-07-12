---
description: Create an Architecture Decision Record (ADR) for a design choice
agent: software-architect
subtask: true
---

Create an Architecture Decision Record for: $ARGUMENTS

!`git log --oneline -5`

Follow the standard ADR format:

```
# ADR-NNN: Title

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-NNN]

## Context
Forces, constraints, and rationale that require a decision.
Include the problem statement and any evaluated alternatives.

## Decision
The chosen approach — what and why. Reference specific patterns, libraries, or conventions.

## Consequences
Trade-offs, migration effort, operational burden.
```

Consider:
- System context and constraints
- Evaluated alternatives with pros/cons
- Impact on performance, security, maintainability
- Migration path if replacing an existing solution
