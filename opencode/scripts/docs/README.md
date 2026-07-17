<h1>build-docs.sh</h1>

<p>Aggregates all agent README files and group tables into a single comprehensive document for offline reference or generation of a static site.</p>

<h2>Usage</h2>

<pre><code>./docs/build-docs.sh
./docs/build-docs.sh --output ../docs/AGENTS-COMPLETE.md
./docs/build-docs.sh --format html</code></pre>

<h2>Output Formats</h2>

<ul>
  <li><code>markdown</code> (default) — single markdown file with all agent tables</li>
  <li><code>html</code> — self-contained HTML file with navigation sidebar</li>
</ul>

<h2>What It Generates</h2>

<ul>
  <li>Combined agent index grouped by category</li>
  <li>Total counts and summary</li>
  <li>Timestamp of generation</li>
  <li>Repository reference</li>
</ul>
