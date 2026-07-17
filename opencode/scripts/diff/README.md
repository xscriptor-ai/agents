<h1>diff-agents.sh</h1>

<p>Compares the agents installed in the OpenCode agents directory against the agents in this repository and shows differences.</p>

<h2>Usage</h2>

<pre><code>./diff/diff-agents.sh
./diff/diff-agents.sh --local ~/.config/opencode/agents
./diff/diff-agents.sh --local ~/.config/opencode/agents --repo ../agents
./diff/diff-agents.sh --missing-only</code></pre>

<h2>Output</h2>

<ul>
  <li>Agents present locally but missing from repo (custom local agents)</li>
  <li>Agents present in repo but not installed locally</li>
  <li>Agents with different file sizes (modified)</li>
  <li>Summary with counts</li>
</ul>
