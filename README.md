<h1>Xscriptor AI</h1>

<p>206 ready-to-use AI agents for <a href="https://opencode.ai">OpenCode</a> and <a href="https://docs.anthropic.com/en/docs/claude-code/overview">Claude Code</a>, plus reusable skills, scripts, and an npm package.</p>

<p>Repository: <a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a><br>
npm: <code>npx @xscriptor/ai-agents</code></p>

<h2>Structure</h2>

<table>
  <thead><tr><th>Path</th><th>Content</th></tr></thead>
  <tbody>
    <tr><td><a href="agents/"><code>agents/</code></a></td><td>182 specialized agents (42 groups)</td></tr>
    <tr><td><a href="senior/agents/"><code>senior/agents/</code></a></td><td>24 consolidated senior agents (16 ecosystems) — <strong>NEW</strong></td></tr>
    <tr><td><a href="skills/"><code>skills/</code></a></td><td>3 SKILL.md (xscriptor, devx, samurai)</td></tr>
    <tr><td><a href="senior/skills/"><code>senior/skills/</code></a></td><td>18 deep-reference skills for senior agents — <strong>NEW</strong></td></tr>
    <tr><td><a href="scripts/"><code>scripts/</code></a></td><td>8 utility scripts (install, validate, generate, etc.)</td></tr>
    <tr><td><a href="packages/ai-agents/"><code>packages/ai-agents/</code></a></td><td>npm package @xscriptor/ai-agents</td></tr>
  </tbody>
</table>

<h3>Specialized vs Senior agents</h3>

<table>
  <thead><tr><th></th><th><code>agents/</code> (Specialized)</th><th><code>senior/agents/</code> (Senior)</th></tr></thead>
  <tbody>
    <tr><td><strong>Scope</strong></td><td>One skill per agent (e.g., Python, React, Docker)</td><td>Whole ecosystem per agent (e.g., full-stack TS, cloud-native)</td></tr>
    <tr><td><strong>Usage</strong></td><td>Compose multiple agents for complex tasks</td><td>Single agent handles the full problem</td></tr>
    <tr><td><strong>Tokens</strong></td><td>3-9 agents = ~10k-46k tokens</td><td>1 agent = ~1.5k-2.4k tokens (<strong>73% less</strong>)</td></tr>
    <tr><td><strong>Depth</strong></td><td>Deep expertise in one area</td><td>Breadth + on-demand skill loading for depth</td></tr>
  </tbody>
</table>

<h2>Quick Start</h2>

<pre><code># npx (no clone)
npx @xscriptor/ai-agents
npx @xscriptor/ai-agents --skills
npx @xscriptor/ai-agents --anthropic

# Clone
git clone https://github.com/xscriptor/ai.git
cd ai
./scripts/install-agents.sh

# Install senior agents
cp -r senior/agents/* ~/.config/opencode/agents/
cp -r senior/skills/* ~/.config/opencode/skills/

# Remote
curl -fsSL https://raw.githubusercontent.com/xscriptor/ai/main/scripts/install-agents.sh | bash</code></pre>
