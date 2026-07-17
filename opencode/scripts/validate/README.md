<h1>validate-agents.sh</h1>

<p>Validates all agent markdown files for correct YAML frontmatter, required fields, and proper values.</p>

<h2>Usage</h2>

<pre><code>./validate/validate-agents.sh
./validate/validate-agents.sh --agents ../agents
./validate/validate-agents.sh --agents ../agents --strict</code></pre>

<h2>Checks Performed</h2>

<ol>
  <li><strong>Frontmatter presence</strong> — every <code>.md</code> file must start with <code>---</code></li>
  <li><strong>Description required</strong> — every agent must have a <code>description:</code> field</li>
  <li><strong>Mode valid</strong> — <code>mode:</code> must be <code>subagent</code> or <code>primary</code></li>
  <li><strong>Temperature range</strong> — <code>temperature:</code> between 0.0 and 1.0 (inclusive)</li>
  <li><strong>Color format</strong> — <code>color:</code> must be a hex color (<code>#RRGGBB</code>) or a valid theme token (<code>primary</code>, <code>accent</code>, <code>error</code>, <code>warning</code>, <code>success</code>, <code>info</code>)</li>
  <li><strong>Permission keys</strong> — permissions must use valid action values: <code>allow</code>, <code>ask</code>, or <code>deny</code></li>
  <li><strong>(strict mode)</strong> — warns if <code>model:</code> is set (agents should be model-agnostic by default)</li>
</ol>

<h2>Exit Codes</h2>

<ul>
  <li><code>0</code> — all agents pass validation</li>
  <li><code>1</code> — one or more agents have validation errors</li>
</ul>
