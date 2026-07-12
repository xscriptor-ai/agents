---
name: architecture
version: 1.0.0
description: "Architecture and design patterns — ADR format, C4 model, design patterns catalog, architecture decision records template, system context diagrams"
---

# Architecture & Design Patterns

## C4 Model for Visualizing Architecture

| Level | Audience | Artifact | Detail |
|-------|----------|----------|--------|
| Context | Everyone | System Context Diagram | One box per system, users as stick figures |
| Container | Dev/Operations | Container Diagram | Apps, databases, microservices, queues |
| Component | Developers | Component Diagram | Classes/modules inside a container |
| Code | Developers | Class/Sequence Diagram | Actual implementation details |

Keep diagrams in code (PlantUML, Mermaid, Structurizr) — never hand-draw. Store alongside ADRs.

## Architecture Decision Records

### ADR Template

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

### ADR Conventions

- Use sequential numbers, zero-padded (ADR-001).
- Store in `docs/adr/` at repository root.
- Never delete an ADR — supersede with a new one.
- Link ADRs in pull request descriptions to drive review.

## Design Patterns Catalog

### Creational

| Pattern | Use When | Example |
|---------|----------|---------|
| Factory | Object creation varies by context | Payment gateway factory per region |
| Abstract Factory | Families of related objects | UI theme engine |
| Builder | Complex multi-step construction | SQL query builder |
| Singleton | Exactly one instance needed | Logger, config registry |
| Prototype | Clone instances instead of new | Entity snapshots for auditing |

### Structural

| Pattern | Use When | Example |
|---------|----------|---------|
| Adapter | Interface mismatch | Legacy API wrapper |
| Facade | Simplify complex subsystem | Orchestrator service |
| Proxy | Control access to an object | Lazy-load, auth proxy |
| Decorator | Add responsibilities dynamically | Middleware pipeline |
| Composite | Tree structures with uniform interface | UI component tree |
| Bridge | Decouple abstraction from implementation | Platform-specific renderers |

### Behavioral

| Pattern | Use When | Example |
|---------|----------|---------|
| Strategy | Swappable algorithms | Authentication providers |
| Observer | One-to-many notifications | Event bus, message queue consumers |
| Command | Encapsulate requests as objects | Undo/redo, job queues |
| Template Method | Skeleton algorithm with overridable steps | Data migration pipeline |
| State | Object behavior changes with state | Workflow engine, order lifecycle |
| Chain of Responsibility | Multiple handlers with pass-or-process | Middleware, validation chains |

### Architectural

| Pattern | Use When | Example |
|---------|----------|---------|
| Repository | Abstract data access | UserRepository, OrderRepository |
| Unit of Work | Coordinate multiple writes | Transaction manager |
| Service Layer | Encapsulate business logic | OrderService, PaymentService |
| CQRS | Separate reads from writes | Reporting queries vs command handlers |
| Event Sourcing | Full audit trail | Financial transactions, state rebuild |
| Saga | Distributed transaction coordination | Order fulfillment across services |

## Dependency Management

- Dependency Injection / Inversion of Control: compose at boundaries.
- Avoid service locator — it hides dependencies.
- Prefer constructor injection.
- Use interfaces/abstract types at module boundaries.

## Code Organization

- Package by feature, not by layer.
- Keep modules small enough to be replaceable.
- Public API surface should be explicit — hide internals.
- Separate infrastructure from domain logic.
