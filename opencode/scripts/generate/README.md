<h1>generate-agent.sh</h1>

<p>Interactive CLI to generate a new OpenCode agent markdown file with correct YAML frontmatter.</p>

<h2>Usage</h2>

<pre><code>./generate/generate-agent.sh
./generate/generate-agent.sh --output ../agents/custom</code></pre>

<h2>What It Prompts</h2>

<ul>
  <li>Agent name (filename)</li>
  <li>Description</li>
  <li>Mode (subagent/primary/all)</li>
  <li>Temperature (0.0 - 1.0)</li>
  <li>Color (hex or theme token)</li>
  <li>Permissions for each tool category (edit, bash, glob, grep, read, list, webfetch)</li>
  <li>Whether to set a specific model</li>
</ul>

<h2>Output</h2>

<p>Creates a single <code>.md</code> file with complete frontmatter and a boilerplate prompt body ready for editing.</p>
