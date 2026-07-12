<h1 align="center">Xscriptor AI</h1>

<p align="center">205 ready-to-use AI agents + 21 skills for <a href="https://opencode.ai">OpenCode</a> and <a href="https://docs.anthropic.com/en/docs/claude-code/overview">Claude Code</a>.</p>

<p align="center">Repository: <a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a><br>
npm: <code>npx @xscriptor/ai-agents</code></p>

<h2 align="center">Structure</h2>

<table align="center">
  <thead><tr><th>Path</th><th>Content</th></tr></thead>
  <tbody>
    <tr><td><a href="agents/"><code>agents/</code></a></td><td>181 specialized agents (33 groups)</td></tr>
    <tr><td><a href="senior/agents/"><code>senior/agents/</code></a></td><td>24 consolidated senior agents (16 ecosystems)</td></tr>
    <tr><td><a href="skills/"><code>skills/</code></a></td><td>3 project skills (xscriptor, devx, samurai)</td></tr>
    <tr><td><a href="senior/skills/"><code>senior/skills/</code></a></td><td>18 deep-reference skills</td></tr>
    <tr><td><a href="scripts/"><code>scripts/</code></a></td><td>8 utility scripts (install, validate, generate, etc.)</td></tr>
    <tr><td><a href="packages/ai-agents/"><code>packages/ai-agents/</code></a></td><td>npm package @xscriptor/ai-agents</td></tr>
  </tbody>
</table>

<h3 align="center">Specialized vs Senior agents</h3>

<table align="center">
  <thead><tr><th></th><th><code>agents/</code> (Specialized)</th><th><code>senior/agents/</code> (Senior)</th></tr></thead>
  <tbody>
    <tr><td><strong>Scope</strong></td><td>One skill per agent (e.g., Python, React, Docker)</td><td>Whole ecosystem per agent (e.g., full-stack TS, cloud-native)</td></tr>
    <tr><td><strong>Usage</strong></td><td>Compose multiple agents for complex tasks</td><td>Single agent handles the full problem</td></tr>
    <tr><td><strong>Tokens</strong></td><td>3-9 agents = ~10k-46k tokens</td><td>1 agent = ~1.5k-2.4k tokens (<strong>73% less</strong>)</td></tr>
    <tr><td><strong>Depth</strong></td><td>Deep expertise in one area</td><td>Breadth + on-demand skill loading for depth</td></tr>
  </tbody>
</table>

<h2 align="center">Quick Start</h2>

<pre><code># npx (no clone) — installs everything
npx @xscriptor/ai-agents

# Selective install
npx @xscriptor/ai-agents --agents   # specialized only
npx @xscriptor/ai-agents --senior   # senior only
npx @xscriptor/ai-agents --skills   # skills only
npx @xscriptor/ai-agents --groups general,languages
npx @xscriptor/ai-agents --anthropic   # Claude Code
npx @xscriptor/ai-agents --project     # current project

# Clone and install all
git clone https://github.com/xscriptor/ai.git
cd ai
./scripts/install-agents.sh

# Selective with local script
./scripts/install-agents.sh --agents
./scripts/install-agents.sh --senior
./scripts/install-agents.sh --skills

# Remote (installs everything by default)
curl -fsSL https://raw.githubusercontent.com/xscriptor/ai/main/scripts/install-agents.sh | bash</code></pre>

<div align="center">
<h2>X</h2>

<a href="https://dev.xscriptor.com">
  <img src="https://xscriptor.github.io/icons/icons/code/product-design/xsvg/verified-filled.svg" width="24" alt="X Web" />
</a>
 & 
<a href="https://github.com/xscriptor">
  <img src="https://xscriptor.github.io/icons/icons/code/product-design/xsvg/github.svg" width="24" alt="X Github Profile" />
</a>
 & 
<a href="https://www.xscriptor.com">
  <img src="https://xscriptor.github.io/icons/icons/code/product-design/xsvg/quotes.svg" width="24" alt="Xscriptor web" />
</a>

</div>