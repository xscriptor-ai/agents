<h1>check-permissions.sh</h1>

<p>Audits agent permissions to detect security risks and configuration issues across the collection.</p>

<h2>Usage</h2>

<pre><code>./audit/check-permissions.sh
./audit/check-permissions.sh --agents ../agents
./audit/check-permissions.sh --risk-only</code></pre>

<h2>Checks</h2>

<h3>Risk Flags</h3>

<ul>
  <li><strong>High risk</strong> — agents with <code>edit: allow</code> (can modify any file)</li>
  <li><strong>Medium risk</strong> — agents with <code>bash: allow</code> (can execute arbitrary commands)</li>
  <li><strong>Warning</strong> — agents with <code>edit: allow</code> AND <code>bash: allow</code> both set</li>
</ul>

<h3>Configuration Issues</h3>

<ul>
  <li>Agents missing explicit permission definitions (falling back to defaults)</li>
  <li>Agents without color set</li>
  <li>Agents missing description</li>
</ul>
