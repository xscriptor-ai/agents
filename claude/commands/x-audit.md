---
description: Security audit of a file, directory, or the whole project
argument-hint: '[target]'
allowed-tools: Task, Read, Glob, Grep, Bash(git diff:*), Bash(git status:*)
---
Delegate this task to the `security-auditor` subagent via the Task tool, passing along the context below.

Perform a security audit on $ARGUMENTS.

!`git ls-files`

Analyze the codebase for:
- Injection vulnerabilities (SQLi, XSS, command injection, SSTI)
- Authentication and authorization flaws
- Insecure direct object references (IDOR)
- Sensitive data exposure (hardcoded secrets, keys, tokens)
- Dependency vulnerabilities
- Misconfigurations (CORS, CSP, headers, permissions)
- Insecure deserialization
- Use of vulnerable or deprecated packages

For each finding, provide:
- File and line reference
- Impact assessment (critical/high/medium/low)
- Remediation steps with code example
- CWE/CVE reference where applicable
