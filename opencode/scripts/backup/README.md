<h1>backup-agents.sh</h1>

<p>Creates a timestamped backup of the installed OpenCode agents directory before any destructive operation.</p>

<h2>Usage</h2>

<pre><code>./backup/backup-agents.sh
./backup/backup-agents.sh --source ~/.config/opencode/agents
./backup/backup-agents.sh --source ~/.config/opencode/agents --dest ~/backups</code></pre>

<h2>Behavior</h2>

<ul>
  <li>Creates a <code>.tar.gz</code> archive with the current timestamp</li>
  <li>Output filename: <code>opencode-agents-YYYY-MM-DD-HHMMSS.tar.gz</code></li>
  <li>Default source: <code>~/.config/opencode/agents/</code></li>
  <li>Default dest: current directory</li>
  <li>Exit code 0 even if source directory does not exist (nothing to back up)</li>
</ul>
