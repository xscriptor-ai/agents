<h1 align="center">OpenCode Commands</h1>

<p align="center">8 custom commands that leverage Xscriptor AI agents for common development workflows.</p>

<h2 align="center">Available Commands</h2>

<table align="center">
  <thead><tr><th>Command</th><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td><code>/review</code></td><td>@code-reviewer</td><td>Review uncommitted changes for quality, bugs, and best practices</td></tr>
    <tr><td><code>/audit</code></td><td>@security-auditor</td><td>Security audit of a file, directory, or the whole project</td></tr>
    <tr><td><code>/docs</code></td><td>@docs-writer</td><td>Generate or update documentation for a module or component</td></tr>
    <tr><td><code>/arch</code></td><td>@software-architect</td><td>Create an Architecture Decision Record (ADR)</td></tr>
    <tr><td><code>/test</code></td><td>@test-writer</td><td>Run tests, analyze failures, and suggest fixes</td></tr>
    <tr><td><code>/deploy</code></td><td>@release-manager</td><td>Prepare a release with changelog, version bump, and tag</td></tr>
    <tr><td><code>/refactor</code></td><td>@refactor-agent</td><td>Analyze and plan refactoring for code improvements</td></tr>
    <tr><td><code>/design</code></td><td>@css-ui-specialist</td><td>Review UI components, design tokens, and CSS architecture</td></tr>
  </tbody>
</table>

<h2 align="center">Installation</h2>

<pre><code># Via npx (no clone)
npx @xscriptor/ai-agents --commands

# Via local script
./opencode/scripts/install-agents.sh --commands

# Or install everything
./opencode/scripts/install-agents.sh</code></pre>

<h2 align="center">Usage</h2>

<p>Commands run in the <strong>primary agent's session</strong> by default (<code>subtask: true</code> spawns a focused subagent).</p>

<pre><code>/review                              # Review all uncommitted changes
/review src/components/              # Review specific directory
/audit src/api/                      # Audit a specific module
/docs src/lib/parser.ts              # Document a file
/arch "Choose database for analytics" # Create an ADR
/test                                # Run and analyze tests
/deploy v2.1.0                       # Prepare release
/refactor src/utils/                 # Analyze for refactoring
/design src/components/              # Review UI components</code></pre>
