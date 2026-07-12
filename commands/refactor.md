---
description: Analyze and plan refactoring for a file, module, or pattern
agent: refactor-agent
subtask: true
---

Analyze $ARGUMENTS for refactoring opportunities.

!`wc -l $ARGUMENTS 2>/dev/null || echo "analyzing structure"`

Evaluate:
- **Complexity**: Functions/modules with high cyclomatic complexity
- **Duplication**: Repeated code patterns that could be extracted
- **Coupling**: Tightly coupled components that should be decoupled
- **Naming**: Unclear or inconsistent naming conventions
- **Structure**: Files/modules that violate single responsibility
- **Dead code**: Unused functions, imports, or parameters
- **Type safety**: Missing or incorrect type annotations

For each finding, provide:
- Current code snippet
- Proposed refactored version
- Rationale for the change
- Estimated effort (small/medium/large)

Do NOT make changes directly — only produce the analysis and recommendations.
