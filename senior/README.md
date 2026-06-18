<h1>Senior Agents</h1>

<p>Consolidated <strong>senior-level agents</strong> that aggregate multiple specialized skills into a single, comprehensive agent per ecosystem. Designed to reduce token usage, eliminate redundant instructions, and provide a single source of truth for full-stack development across all major programming ecosystems.</p>

<p>Compatible with <a href="https://opencode.ai">OpenCode</a> and <a href="https://docs.anthropic.com/en/docs/claude-code/overview">Claude Code</a>.</p>

<h2>Structure</h2>

<pre><code>senior/
  agents/          # Senior agent definitions
    typescript/     # TypeScript/JS ecosystem
    python/         # Python ecosystem
    go/             # Go ecosystem
    rust/           # Rust ecosystem
    java-kotlin/    # JVM ecosystem
    mobile/         # Mobile dev ecosystem
    web/            # Language-agnostic web
    cloud/          # Cloud infrastructure
    security/       # Application security
    systems/        # Systems engineering
    data-ml/        # Data & ML platform
    game-dev/       # Game development
    content/        # Content strategy
    compliance/     # Compliance frameworks
    github/         # GitHub automation
    testing/        # Testing strategies
  skills/           # Deep reference skills (loaded on-demand)
    architecture/   # ADRs, C4, design patterns
    testing/        # Cross-language testing
    secure-coding/  # Security patterns
    performance/    # Performance optimization
    deployment/     # CI/CD, Docker, IaC
    api-design/     # REST, GraphQL, gRPC
    observability/  # Logging, metrics, tracing
    monorepo/       # Monorepo management
    typescript/     # TS deep patterns
    python/         # Python deep patterns
    go/             # Go deep patterns
    rust/           # Rust deep patterns
    java-kotlin/    # JVM deep patterns
    mobile/         # Mobile deep patterns
    web/            # Web deep patterns
    cloud/          # Cloud deep patterns
    security/       # Security deep patterns
    systems/        # Systems deep patterns
</code></pre>

<h2>How It Works</h2>

<p>Each senior agent is a self-contained markdown file with YAML frontmatter that:</p>

<ol>
  <li><strong>Aggregates</strong> knowledge from 3-12 specialized agents into one coherent agent</li>
  <li><strong>Reduces tokens</strong> by eliminating duplicate frontmatter, permissions, and overlapping patterns</li>
  <li><strong>Loads skills on-demand</strong> via the <code>skill</code> tool for deep reference patterns when needed</li>
  <li><strong>Works standalone</strong> without needing to delegate to sub-agents for common tasks</li>
</ol>

<h2>Agent Index</h2>

<table>
  <thead>
    <tr>
      <th>Ecosystem</th>
      <th>Agent</th>
      <th>Aggregates</th>
      <th>Color</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>TypeScript</td>
      <td><code>agents/typescript/senior-fullstack-ts.md</code></td>
      <td>TS + React + Next.js + Node + DB + testing + deploy</td>
      <td><code>#3178C6</code></td>
    </tr>
    <tr>
      <td>TypeScript</td>
      <td><code>agents/typescript/senior-frontend-ts.md</code></td>
      <td>React + Next.js + Vue + Angular + CSS + perf + a11y</td>
      <td><code>#61dafb</code></td>
    </tr>
    <tr>
      <td>TypeScript</td>
      <td><code>agents/typescript/senior-node-backend.md</code></td>
      <td>Node/Deno/Bun + Express/Fastify + DB + caching + MQ</td>
      <td><code>#339933</code></td>
    </tr>
    <tr>
      <td>Python</td>
      <td><code>agents/python/senior-python.md</code></td>
      <td>Python + FastAPI + Django + async + testing + packaging</td>
      <td><code>#3572A5</code></td>
    </tr>
    <tr>
      <td>Data & ML</td>
      <td><code>agents/python/senior-data-ml.md</code></td>
      <td>Data eng + ML + MLOps + data science</td>
      <td><code>#FF6F00</code></td>
    </tr>
    <tr>
      <td>Go</td>
      <td><code>agents/go/senior-go.md</code></td>
      <td>Go + web + CLI + concurrency + DB + deploy</td>
      <td><code>#00ADD8</code></td>
    </tr>
    <tr>
      <td>Rust</td>
      <td><code>agents/rust/senior-rust.md</code></td>
      <td>Rust + async + web + embedded + FFI + systems</td>
      <td><code>#DEA584</code></td>
    </tr>
    <tr>
      <td>JVM</td>
      <td><code>agents/java-kotlin/senior-jvm.md</code></td>
      <td>Java + Kotlin + Spring + Ktor + Android</td>
      <td><code>#007396</code></td>
    </tr>
    <tr>
      <td>Mobile</td>
      <td><code>agents/mobile/senior-mobile.md</code></td>
      <td>iOS + Android + RN + Flutter + security</td>
      <td><code>#34C759</code></td>
    </tr>
    <tr>
      <td>Web</td>
      <td><code>agents/web/senior-fullstack.md</code></td>
      <td>Full-stack web: FE + BE + API + DB + deploy + security</td>
      <td><code>#6C63FF</code></td>
    </tr>
    <tr>
      <td>Web</td>
      <td><code>agents/web/senior-frontend.md</code></td>
      <td>Frontend: components + state + styling + perf + a11y</td>
      <td><code>#61dafb</code></td>
    </tr>
    <tr>
      <td>Web</td>
      <td><code>agents/web/senior-backend.md</code></td>
      <td>Backend: API + DB + caching + MQ + microservices</td>
      <td><code>#339933</code></td>
    </tr>
    <tr>
      <td>Web</td>
      <td><code>agents/web/senior-architecture.md</code></td>
      <td>Architecture: system design + scalability + reliability</td>
      <td><code>#E91E63</code></td>
    </tr>
    <tr>
      <td>Cloud</td>
      <td><code>agents/cloud/senior-cloud-native.md</code></td>
      <td>K8s + GitOps + service mesh + SRE + multi-cloud</td>
      <td><code>#326CE5</code></td>
    </tr>
    <tr>
      <td>Cloud</td>
      <td><code>agents/cloud/senior-devops.md</code></td>
      <td>CI/CD + containers + IaC + DevSecOps</td>
      <td><code>#F05032</code></td>
    </tr>
    <tr>
      <td>Security</td>
      <td><code>agents/security/senior-appsec.md</code></td>
      <td>AppSec: web + API + mobile + AI + DevSecOps</td>
      <td><code>#FF0000</code></td>
    </tr>
    <tr>
      <td>Security</td>
      <td><code>agents/security/senior-pentest.md</code></td>
      <td>Pentest: web + API + mobile + browser + bug bounty</td>
      <td><code>#8B0000</code></td>
    </tr>
    <tr>
      <td>Systems</td>
      <td><code>agents/systems/senior-systems.md</code></td>
      <td>Linux + macOS + Windows + networking + storage</td>
      <td><code>#4EAA25</code></td>
    </tr>
    <tr>
      <td>Data</td>
      <td><code>agents/data-ml/senior-data-platform.md</code></td>
      <td>Pipelines + ML + MLOps + data science</td>
      <td><code>#FF6F00</code></td>
    </tr>
    <tr>
      <td>Game Dev</td>
      <td><code>agents/game-dev/senior-game-dev.md</code></td>
      <td>Unity + Unreal + game architecture</td>
      <td><code>#FF69B4</code></td>
    </tr>
    <tr>
      <td>Content</td>
      <td><code>agents/content/senior-content.md</code></td>
      <td>Technical writing + editing + translation + markdown</td>
      <td><code>#8B4513</code></td>
    </tr>
    <tr>
      <td>Compliance</td>
      <td><code>agents/compliance/senior-compliance.md</code></td>
      <td>SOC 2 + GDPR + HIPAA + PCI + FedRAMP + SOX</td>
      <td><code>#1A5276</code></td>
    </tr>
    <tr>
      <td>GitHub</td>
      <td><code>agents/github/senior-github.md</code></td>
      <td>Actions + admin + API automation</td>
      <td><code>#181717</code></td>
    </tr>
    <tr>
      <td>Testing</td>
      <td><code>agents/testing/senior-testing.md</code></td>
      <td>E2E + visual + perf + chaos + fuzz + unit</td>
      <td><code>#16A085</code></td>
    </tr>
  </tbody>
</table>

<h2>Skills Index</h2>

<table>
  <thead>
    <tr>
      <th>Skill</th>
      <th>Path</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Architecture</td><td><code>skills/architecture/SKILL.md</code></td><td>C4 model, ADRs, design patterns catalog</td></tr>
    <tr><td>Testing</td><td><code>skills/testing/SKILL.md</code></td><td>Cross-language testing strategies</td></tr>
    <tr><td>Secure Coding</td><td><code>skills/secure-coding/SKILL.md</code></td><td>Injection, XSS, crypto, secrets management</td></tr>
    <tr><td>Performance</td><td><code>skills/performance/SKILL.md</code></td><td>Caching, profiling, bundle optimization</td></tr>
    <tr><td>Deployment</td><td><code>skills/deployment/SKILL.md</code></td><td>Docker, CI/CD, IaC, secret management</td></tr>
    <tr><td>API Design</td><td><code>skills/api-design/SKILL.md</code></td><td>REST, GraphQL, gRPC conventions</td></tr>
    <tr><td>Observability</td><td><code>skills/observability/SKILL.md</code></td><td>Logging, tracing, metrics, alerting</td></tr>
    <tr><td>Monorepo</td><td><code>skills/monorepo/SKILL.md</code></td><td>Nx, Turborepo, pnpm workspaces</td></tr>
    <tr><td>TypeScript</td><td><code>skills/typescript/SKILL.md</code></td><td>Advanced types, module resolution</td></tr>
    <tr><td>Python</td><td><code>skills/python/SKILL.md</code></td><td>Async, FastAPI, SQLAlchemy, packaging</td></tr>
    <tr><td>Go</td><td><code>skills/go/SKILL.md</code></td><td>Concurrency, testing, profiling</td></tr>
    <tr><td>Rust</td><td><code>skills/rust/SKILL.md</code></td><td>Unsafe, FFI, embedded, async</td></tr>
    <tr><td>JVM</td><td><code>skills/java-kotlin/SKILL.md</code></td><td>Virtual threads, coroutines, Spring/JPA</td></tr>
    <tr><td>Mobile</td><td><code>skills/mobile/SKILL.md</code></td><td>iOS, Android, RN, Flutter patterns</td></tr>
    <tr><td>Web</td><td><code>skills/web/SKILL.md</code></td><td>Full-stack, state, CSS, performance, a11y</td></tr>
    <tr><td>Cloud</td><td><code>skills/cloud/SKILL.md</code></td><td>K8s, GitOps, service mesh, SRE</td></tr>
    <tr><td>Security</td><td><code>skills/security/SKILL.md</code></td><td>Threat modeling, OWASP, zero-trust</td></tr>
    <tr><td>Systems</td><td><code>skills/systems/SKILL.md</code></td><td>Shell, OS admin, networking, storage</td></tr>
  </tbody>
</table>

<h2>Installation</h2>

<pre><code># Copy all senior agents
cp -r senior/agents/* ~/.config/opencode/agents/

# Copy all senior skills
cp -r senior/skills/* ~/.config/opencode/skills/

# Or install specific ecosystem
cp senior/agents/typescript/*.md ~/.config/opencode/agents/
cp senior/skills/typescript/SKILL.md ~/.config/opencode/skills/</code></pre>

<h2>Usage</h2>

<p>Invoke any senior agent with <code>@</code> mention:</p>

<pre><code>@senior-fullstack-ts "build a real-time chat application"
@senior-python "create a FastAPI service with async PostgreSQL"
@senior-go "design a CLI tool with concurrent workers"
@senior-rust "implement a web server with tokio + axum"
@senior-cloud-native "migrate to Kubernetes with GitOps"
@senior-pentest "perform a full security assessment"</code></pre>

<h2>Design Principles</h2>

<ol>
  <li><strong>Self-contained</strong>: Each senior agent has enough context for 80% of tasks without delegating</li>
  <li><strong>Token-efficient</strong>: Consolidates 3-12 agents into one, removing duplicate content</li>
  <li><strong>Skills for depth</strong>: Uses <code>skill</code> tool to load deep reference material on demand</li>
  <li><strong>Platform-agnostic</strong>: YAML frontmatter works with OpenCode and Claude Code</li>
  <li><strong>Non-destructive</strong>: Does not modify existing <code>agents/</code> or <code>skills/</code> directories</li>
</ol>
