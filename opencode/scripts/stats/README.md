<h1>agent-stats.sh</h1>

<p>Generates statistics about the agent collection: counts, distribution, permissions, and coverage.</p>

<h2>Usage</h2>

<pre><code>./stats/agent-stats.py
./stats/agent-stats.py --agents ../agents
./stats/agent-stats.py --format json</code></pre>

<h2>Output</h2>

<ul>
  <li>Total agent count</li>
  <li>Agents per group</li>
  <li>Average lines per agent</li>
  <li>Temperature distribution (histogram by 0.1 steps)</li>
  <li>Most used colors</li>
  <li>Permission coverage (how many agents restrict each tool)</li>
</ul>
