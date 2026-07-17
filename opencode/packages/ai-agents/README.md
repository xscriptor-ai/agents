<h1 align="center">@xscriptor/ai-agents</h1>

<p>205 ready-to-use AI agents + 21 skills + 8 commands for <a href="https://opencode.ai">OpenCode</a> and <a href="https://docs.anthropic.com/en/docs/claude-code/overview">Claude Code</a>.</p>

<p>Includes 181 specialized agents, 24 consolidated senior agents, 3 project skills, 18 deep-reference skills, and 8 custom commands.</p>

<h2>Installation</h2>

<pre><code># Everything (agents + senior + skills) to OpenCode
npx @xscriptor/ai-agents

# Only specialized agents
npx @xscriptor/ai-agents --agents

# Only senior agents
npx @xscriptor/ai-agents --senior

# Only skills
npx @xscriptor/ai-agents --skills

# Only commands
npx @xscriptor/ai-agents --commands

# Specific groups
npx @xscriptor/ai-agents --groups general,web/security

# To Claude Code
npx @xscriptor/ai-agents --anthropic

# To current project
npx @xscriptor/ai-agents --project

# Preview
npx @xscriptor/ai-agents --dry-run

# Global npm install
npm install -g @xscriptor/ai-agents
install-agents</code></pre>

<h2>Usage</h2>

<pre><code>@code-reviewer review this pull request
@web-vulnerability-hunter test the login endpoint
@incident-response investigate the alert
@senior-fullstack design the architecture</code></pre>

<p>Repo: <a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a></p>
