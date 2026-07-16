---
description: Prepare a release with changelog, version bump, and tag
argument-hint: '[target]'
allowed-tools: Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)
---
Delegate this task to the `release-manager` subagent via the Task tool, passing along the context below.

Prepare a release for $ARGUMENTS.

!`git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~20)..HEAD`

Analyze the recent commits and:
1. Determine the next version number (semver: major/minor/patch)
2. Generate a changelog with clear sections:
   - Features
   - Bug Fixes
   - Performance Improvements
   - Breaking Changes
   - Deprecations
3. Suggest the git tag command
4. Check if any migration steps or release notes are needed
5. Verify version references in:
   - `package.json`, `Cargo.toml`, `pyproject.toml`, or similar
   - Any changelog files
   - Documentation version references
