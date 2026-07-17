<h1 align="center">@xscriptor/skill-xscriptor</h1>

<p>Design system skill for the Xscriptor literary portfolio site. Contains the complete architecture, component system, styling conventions, and content management guidelines for xscriptor.com — built with Next.js 16 App Router, Tailwind CSS v4, and a custom i18n system.</p>

<h2>Installation</h2>

<pre><code># Install to OpenCode (~/.config/opencode/skills/xscriptor/)
npx @xscriptor/skill-xscriptor

# Install to Claude Code (~/.claude/skills/xscriptor/)
npx @xscriptor/skill-xscriptor --anthropic

# Preview what will be installed
npx @xscriptor/skill-xscriptor --dry-run</code></pre>

<h2>Usage</h2>

<p>Once installed, the skill is loaded automatically when working on the Xscriptor project. Invoke it manually with <code>/xscriptor</code> in Claude Code, or use <code>@xscriptor</code> in OpenCode.</p>

<p>The skill covers:</p>
<ul>
  <li><strong>Tech stack</strong> — Next.js 16, Tailwind v4, framer-motion, static export</li>
  <li><strong>Project structure</strong> — app router, locale groups, component barrel</li>
  <li><strong>Component system</strong> — <code>@xscriptor/xcomponents</code> npm package conventions</li>
  <li><strong>Content management</strong> — markdown articles, MDX books, blog pipeline</li>
  <li><strong>Styling conventions</strong> — theme variables, CSS Modules, Tailwind v4</li>
  <li><strong>Theme system</strong> — light/dark with <code>data-theme</code> and localStorage</li>
  <li><strong>i18n</strong> — 3 languages (es, en, de) with custom provider</li>
  <li><strong>Static export</strong> — build configuration, .htaccess, sitemap generation</li>
</ul>

<h2>Resources</h2>

<ul>
  <li><a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a></li>
  <li><a href="https://dev.xscriptor.com/en/resources/ai/">dev.xscriptor.com/en/resources/ai/</a></li>
</ul>

<hr>

<p><strong>License:</strong> <a href="./LICENSE">MIT</a><br>
<strong>Report issues:</strong> <a href="https://github.com/xscriptor/ai/issues">github.com/xscriptor/ai/issues</a><br>
<strong>Changelog:</strong> <a href="https://github.com/xscriptor/ai/releases">github.com/xscriptor/ai/releases</a></p>
