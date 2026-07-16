---
description: Review uncommitted changes for quality, bugs, and best practices
argument-hint: '[target]'
allowed-tools: Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)
---
Delegate this task to the `code-reviewer` subagent via the Task tool, passing along the context below.

Review the following uncommitted changes for code quality, potential bugs, performance issues, and adherence to project conventions.

!`git diff --stat`
!`git diff`

Focus on:
- Logic errors and edge cases
- Security vulnerabilities
- Performance bottlenecks
- Code style and consistency with the rest of the codebase
- Missing tests or error handling

Provide a summary of findings with severity levels (critical/major/minor) and concrete suggestions for each issue.
