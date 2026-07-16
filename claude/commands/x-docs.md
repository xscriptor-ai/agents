---
description: Generate or update documentation for the specified module or component
argument-hint: '[target]'
allowed-tools: Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)
---
Delegate this task to the `docs-writer` subagent via the Task tool, passing along the context below.

Generate comprehensive documentation for $ARGUMENTS.

!`find $ARGUMENTS -type f | head -30 2>/dev/null || echo "checking project structure"`

Include:
- Overview and purpose
- Public API surface (functions, classes, exports)
- Usage examples
- Configuration options
- Dependencies and requirements
- Edge cases and error handling
- Related files and references

Use the project's existing documentation style as reference:
!`find . -name '*.md' -not -path './node_modules/*' | head -10`

Output the documentation in markdown format, ready to save to a file.
