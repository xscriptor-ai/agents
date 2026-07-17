---
description: Run tests, analyze failures, and suggest fixes
agent: test-writer
subtask: true
---

Run the test suite and analyze the results.

!`npm test 2>&1 || true`

!`npx vitest run 2>&1 || true`

!`go test ./... 2>&1 || true`

!`cargo test 2>&1 || true`

Based on the test output:
- Identify all failing tests and their error messages
- Analyze the root cause of each failure
- Suggest specific fixes with code examples
- Check for missing test coverage in critical paths
- Recommend additional test cases for edge conditions

If no test framework is detected, analyze the project structure and recommend an appropriate testing setup.
