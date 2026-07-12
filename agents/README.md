<h1>OpenCode Agents</h1>

<p>A collection of ready-to-use <a href="https://opencode.ai/docs/agents">OpenCode agent definitions</a> organized by context and specialization. Each agent is a markdown file with YAML frontmatter that configures its behavior, permissions, and system prompt.</p>

<p><strong>181 agents</strong> across <strong>33 specialization groups</strong>. All agents are <strong>model-agnostic</strong> and work with Claude, GPT, DeepSeek, or any other LLM provider available in OpenCode.</p>

<p>Repository: <a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a></p>

<h2>Table of Contents</h2>

<ul>
  <li><a href="#agent-structure">Agent Structure</a></li>
  <li><a href="#installation">Installation</a></li>
  <li><a href="#usage">Usage</a></li>
  <li><a href="#customization">Customization</a></li>
  <li><a href="#general">General</a></li>
  <li><a href="#web-security">Web / Security</a></li>
  <li><a href="#web-architecture">Web / Architecture</a></li>
  <li><a href="#web-frontend">Web / Frontend</a></li>
  <li><a href="#web-backend">Web / Backend</a></li>
  <li><a href="#languages">Languages</a></li>
  <li><a href="#mobile">Mobile</a></li>
  <li><a href="#data-ml">Data & ML</a></li>
  <li><a href="#cloud">Cloud</a></li>
  <li><a href="#testing">Testing</a></li>
  <li><a href="#graphql">GraphQL</a></li>
  <li><a href="#embedded">Embedded</a></li>
  <li><a href="#game-dev">Game Development</a></li>
  <li><a href="#security-recon">Security / Recon</a></li>
  <li><a href="#security-web-pentest">Security / Web Pentest</a></li>
  <li><a href="#security-mobile-pentest">Security / Mobile Pentest</a></li>
  <li><a href="#security-desktop">Security / Desktop Exploitation</a></li>
  <li><a href="#security-red-team">Security / Red Team</a></li>
  <li><a href="#security-blue-team">Security / Blue Team</a></li>
  <li><a href="#security-purple-team">Security / Purple Team</a></li>
  <li><a href="#security-ai-ml-security">Security / AI & ML Security</a></li>
  <li><a href="#content">Content</a></li>
  <li><a href="#observability">Observability</a></li>
  <li><a href="#compliance">Compliance</a></li>
  <li><a href="#system">Systems</a></li>
  <li><a href="#privacy-engineering">Privacy Engineering</a></li>
  <li><a href="#blockchain-web3-security">Blockchain / Web3 Security</a></li>
  <li><a href="#telecom-security">Telecom Security</a></li>
  <li><a href="#automotive-security">Automotive Security</a></li>
  <li><a href="#hardware-security">Hardware Security</a></li>
  <li><a href="#medical-security">Medical Device Security</a></li>
  <li><a href="#aviation-maritime-energy">Aviation / Maritime / Energy</a></li>
  <li><a href="#physical-mainframe-security">Physical / Mainframe Security</a></li>
  <li><a href="#mega-orchestrators">Mega Orchestrators</a></li>
  <li><a href="#github">GitHub</a></li>
  <li><a href="#installation">Installation</a></li>
</ul>

<h2 id="agent-structure">Agent Structure</h2>

<p>Each agent file uses YAML frontmatter followed by a system prompt in markdown:</p>

<pre><code>---
description: One-line description of what this agent does
mode: subagent
model: anthropic/claude-sonnet-4-20250514
temperature: 0.1
color: accent
permission:
  edit: deny
  bash: deny
---

You are a specialist. Detailed instructions for the AI.
- Bullet points with specific guidance
- Checklists for what to check or do
- Rules to follow
</code></pre>

<h2 id="installation">Installation</h2>

<pre><code># Copy agents for a specific context
cp agents/general/code-reviewer.md ~/.config/opencode/agents/
cp agents/web/backend/api-designer.md ~/.config/opencode/agents/
cp agents/web/frontend/react-specialist.md ~/.config/opencode/agents/

# Or install all agents from a directory
cp agents/general/*.md ~/.config/opencode/agents/
</code></pre>

<h2 id="usage">Usage</h2>

<p>Invoke any agent in OpenCode with the <code>@</code> mention:</p>

<pre><code>@code-reviewer review this pull request
@web-security-auditor scan the payment module
@software-architect review the system design
@react-specialist review this component
@api-designer design a REST API for orders
</code></pre>

<h2 id="customization">Customization</h2>

<ul>
  <li><strong>model</strong>: Pin a specific provider/model (omit to use the default agent model)</li>
  <li><strong>temperature</strong>: 0.0-0.3 for precise tasks, 0.3-0.7 for creative work</li>
  <li><strong>color</strong>: Hex color or theme token (primary, accent, error, warning, success, info)</li>
  <li><strong>permission</strong>: control tool access per agent (allow, ask, deny)</li>
  <li><strong>steps</strong>: max agentic iterations before forced text response</li>
</ul>

<h2 id="general">General</h2>

<p>Language and framework agnostic agents for any project. See <a href="general/">general/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Code Reviewer</td><td><code>general/code-reviewer.md</code></td><td>Reviews code quality, best practices, and potential issues</td></tr>
    <tr><td>Security Auditor</td><td><code>general/security-auditor.md</code></td><td>Security vulnerability analysis with CVE lookup</td></tr>
    <tr><td>Docs Writer</td><td><code>general/docs-writer.md</code></td><td>Creates and maintains project documentation</td></tr>
    <tr><td>API Docs</td><td><code>general/api-docs.md</code></td><td>Generates API documentation in OpenAPI/Swagger format</td></tr>
    <tr><td>Refactor Agent</td><td><code>general/refactor-agent.md</code></td><td>Code refactoring with behavior preservation</td></tr>
    <tr><td>DB Migrator</td><td><code>general/db-migrator.md</code></td><td>Database migrations with reversible up/down patterns</td></tr>
    <tr><td>Test Writer</td><td><code>general/test-writer.md</code></td><td>Unit, integration, and E2E test creation</td></tr>
    <tr><td>Dependency Auditor</td><td><code>general/dependency-auditor.md</code></td><td>Dependency health: CVEs, licenses, maintenance</td></tr>
    <tr><td>Performance Analyzer</td><td><code>general/performance-analyzer.md</code></td><td>Performance bottleneck detection and optimization</td></tr>
    <tr><td>PR Manager</td><td><code>general/pr-manager.md</code></td><td>Pull request creation and changelog generation</td></tr>
    <tr><td>Release Manager</td><td><code>general/release-manager.md</code></td><td>Release planning, versioning, and changelog management</td></tr>
  </tbody>
</table>

<h2 id="web-security">Web / Security</h2>

<p>See <a href="web/security/">web/security/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Web Security Auditor</td><td><code>web/security/web-security-auditor.md</code></td><td>Full OWASP Top 10 audit across web application stack</td></tr>
    <tr><td>API Security Specialist</td><td><code>web/security/api-security-specialist.md</code></td><td>API-layer security: REST, GraphQL, gRPC endpoint protection</td></tr>
    <tr><td>Auth Security Specialist</td><td><code>web/security/auth-security-specialist.md</code></td><td>Authentication, authorization, OAuth2, JWT, session management</td></tr>
    <tr><td>AppSec Engineer</td><td><code>web/security/appsec-engineer.md</code></td><td>Secure SDLC: threat modeling, SAST/DAST, cloud security</td></tr>
    <tr><td>Secure Coding</td><td><code>web/security/secure-coding.md</code></td><td>OWASP ASVS, injection prevention, crypto misuse, XSS/SQLI prevention, CWE Top 25</td></tr>
    <tr><td>WAF Specialist</td><td><code>web/security/waf-specialist.md</code></td><td>WAF configuration, tuning, and bypass testing</td></tr>
    <tr><td>CDN & Edge Security</td><td><code>web/security/cdn-edge-security.md</code></td><td>CDN and edge computing security across Cloudflare, Fastly, Akamai</td></tr>
  </tbody>
</table>

<h2 id="web-architecture">Web / Architecture</h2>

<p>See <a href="web/architecture/">web/architecture/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Software Architect</td><td><code>web/architecture/software-architect.md</code></td><td>Architecture styles, patterns, C4 documentation, ADRs</td></tr>
    <tr><td>System Designer</td><td><code>web/architecture/system-designer.md</code></td><td>Distributed system design, scalability, database selection</td></tr>
    <tr><td>Scalability Specialist</td><td><code>web/architecture/scalability-specialist.md</code></td><td>Performance optimization, load testing, database scaling</td></tr>
    <tr><td>Reliability Specialist</td><td><code>web/architecture/reliability-specialist.md</code></td><td>SLO/SLI, circuit breakers, disaster recovery, incident management</td></tr>
    <tr><td>Zero Trust Architect</td><td><code>web/architecture/zero-trust-architect.md</code></td><td>BeyondCorp, ZTNA, mTLS, OPA/Cedar policies, microsegmentation, JIT access</td></tr>
  </tbody>
</table>

<h2 id="web-frontend">Web / Frontend</h2>

<p>See <a href="web/frontend/">web/frontend/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>React Specialist</td><td><code>web/frontend/react-specialist.md</code></td><td>React ecosystem: hooks, state, performance, Server Components</td></tr>
    <tr><td>Vue Specialist</td><td><code>web/frontend/vue-specialist.md</code></td><td>Vue 3 ecosystem: Composition API, Pinia, Nuxt, Vite</td></tr>
    <tr><td>CSS/UI Specialist</td><td><code>web/frontend/css-ui-specialist.md</code></td><td>Modern CSS, design systems, theming, layout, animations</td></tr>
    <tr><td>Frontend Performance</td><td><code>web/frontend/frontend-performance.md</code></td><td>Core Web Vitals, bundle optimization, runtime performance</td></tr>
    <tr><td>Accessibility Specialist</td><td><code>web/frontend/accessibility-specialist.md</code></td><td>WCAG 2.2, ARIA, semantic HTML, screen reader, keyboard navigation</td></tr>
    <tr><td>Next.js Developer</td><td><code>web/frontend/nextjs-developer.md</code></td><td>Next.js App Router, Server Actions, streaming, auth, deployment</td></tr>
    <tr><td>Angular Developer</td><td><code>web/frontend/angular-developer.md</code></td><td>Angular standalone components, signals, state management, testing</td></tr>
  </tbody>
</table>

<h2 id="web-backend">Web / Backend</h2>

<p>See <a href="web/backend/">web/backend/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>API Designer</td><td><code>web/backend/api-designer.md</code></td><td>REST, GraphQL, gRPC API design with OpenAPI 3.1</td></tr>
    <tr><td>Database Specialist</td><td><code>web/backend/database-specialist.md</code></td><td>Schema design, query optimization, indexing, migrations</td></tr>
    <tr><td>Microservices Architect</td><td><code>web/backend/microservices-architect.md</code></td><td>Service boundaries, communication patterns, distributed data</td></tr>
    <tr><td>DevOps Specialist</td><td><code>web/backend/devops-specialist.md</code></td><td>CI/CD, Docker, Kubernetes, Terraform, cloud infrastructure</td></tr>
    <tr><td>Message Queue Specialist</td><td><code>web/backend/message-queue-specialist.md</code></td><td>Kafka, RabbitMQ, event-driven patterns, outbox, DLQ</td></tr>
    <tr><td>Caching Specialist</td><td><code>web/backend/caching-specialist.md</code></td><td>Redis, CDN, HTTP caching, multi-level cache strategies</td></tr>
    <tr><td>Database Security</td><td><code>web/backend/database-security.md</code></td><td>PostgreSQL/MySQL/MongoDB hardening, TDE, audit, RBAC, RLS, injection prevention</td></tr>
  </tbody>
</table>

<h2 id="languages">Languages</h2>

<p>See <a href="languages/">languages/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Python Developer</td><td><code>languages/python-developer.md</code></td><td>Python: async, web frameworks, testing, packaging, data</td></tr>
    <tr><td>TypeScript Developer</td><td><code>languages/typescript-developer.md</code></td><td>TypeScript/JS: type system, runtimes, tooling, async, web</td></tr>
    <tr><td>Go Developer</td><td><code>languages/go-developer.md</code></td><td>Go: concurrency, net/http, CLI, profiling, deployment</td></tr>
    <tr><td>Java Developer</td><td><code>languages/java-developer.md</code></td><td>Java 21+: Spring Boot, JPA, JVM tuning, virtual threads</td></tr>
    <tr><td>Kotlin Developer</td><td><code>languages/kotlin-developer.md</code></td><td>Kotlin: coroutines, Ktor, Exposed, multiplatform, Flow</td></tr>
    <tr><td>Rust Developer</td><td><code>languages/rust-developer.md</code></td><td>Rust: systems, async, Axum, unsafe, FFI, serde</td></tr>
    <tr><td>VS Code Language Extension</td><td><code>languages/vscode-language-extension.md</code></td><td>TextMate grammars, completions, IntelliSense</td></tr>
    <tr><td>VS Code LSP Extension</td><td><code>languages/vscode-lsp-extension.md</code></td><td>Language Server Protocol, IntelliSense, diagnostics</td></tr>
    <tr><td>VS Code Debug Extension</td><td><code>languages/vscode-debug-extension.md</code></td><td>Debug Adapter Protocol, debuggers, debug UI</td></tr>
    <tr><td>VS Code UI Extension</td><td><code>languages/vscode-ui-extension.md</code></td><td>Webviews, TreeViews, commands, custom editors, status bar</td></tr>
  </tbody>
</table>

<h2 id="systems">Systems</h2>

<p>See <a href="systems/">systems/</a>.</p>

<table>
  <thead>
    <tr>
      <th>Agent</th>
      <th>File</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr><td>Bash/Zsh Specialist</td><td><code>systems/bash-zsh-specialist.md</code></td><td>Shell scripting: bash, zsh, POSIX sh, strict mode, portability, debugging, patterns</td></tr>
    <tr><td>Linux Specialist</td><td><code>systems/linux-specialist.md</code></td><td>Linux administration: systemd, filesystems, LVM, networking, performance, security</td></tr>
    <tr><td>macOS Specialist</td><td><code>systems/macos-specialist.md</code></td><td>macOS administration: launchd, plists, Homebrew, defaults, automation, AppleScript</td></tr>
    <tr><td>Linux Hardening</td><td><code>systems/linux-hardening.md</code></td><td>CIS benchmarks, SSH/kernel hardening, auditd, nftables, PAM, file integrity</td></tr>
    <tr><td>macOS Hardening</td><td><code>systems/macos-hardening.md</code></td><td>SIP, FileVault, Gatekeeper, profiles, TCC, firewall, compliance scripting</td></tr>
    <tr><td>IR Scripting</td><td><code>systems/ir-scripting.md</code></td><td>IR automation: acquisition scripts, timeline analysis, IOC scanning, orchestration</td></tr>
    <tr><td>Offensive Shell Scripting</td><td><code>systems/offensive-shell-scripting.md</code></td><td>Red team scripting: reverse shells, persistence, data exfiltration, C2 bootstrap, anti-forensics</td></tr>
    <tr><td>Network Security Engineering</td><td><code>systems/network-security.md</code></td><td>Firewalls (nft/iptables), VPN (WireGuard/OpenVPN), IDS/IPS (Suricata/Snort), segmentation</td></tr>
    <tr><td>Windows Specialist</td><td><code>systems/windows-specialist.md</code></td><td>Windows Server: AD, Group Policy, PowerShell DSC, WSUS</td></tr>
    <tr><td>Container Orchestration</td><td><code>systems/container-orchestration.md</code></td><td>Nomad, Mesos, Docker Swarm, beyond Kubernetes</td></tr>
    <tr><td>Storage Engineering</td><td><code>systems/storage-engineering.md</code></td><td>Ceph, NetApp, SAN/NAS, ZFS, NVMe-oF</td></tr>
    <tr><td>PowerShell Specialist</td><td><code>systems/powershell-specialist.md</code></td><td>PowerShell scripting and automation, Windows, Azure, cross-platform</td></tr>
  </tbody>
</table>

<h2 id="mobile">Mobile</h2>

<p>See <a href="mobile/">mobile/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>iOS Developer</td><td><code>mobile/ios-developer.md</code></td><td>Swift, SwiftUI, Swift concurrency, Core Data, testing</td></tr>
    <tr><td>Android Developer</td><td><code>mobile/android-developer.md</code></td><td>Jetpack Compose, ViewModel, Room, Hilt, testing</td></tr>
    <tr><td>React Native Developer</td><td><code>mobile/react-native-developer.md</code></td><td>Expo, Expo Router, NativeWind, FlashList, EAS</td></tr>
    <tr><td>Flutter Developer</td><td><code>mobile/flutter-developer.md</code></td><td>Riverpod, GoRouter, drift, BLoC, testing</td></tr>
    <tr><td>Mobile App Secure Coding</td><td><code>mobile/mobile-app-secure-coding.md</code></td><td>iOS Swift and Android Kotlin secure coding</td></tr>
    <tr><td>Mobile Malware Analysis</td><td><code>mobile/mobile-malware-analysis.md</code></td><td>Static and dynamic analysis of Android and iOS malware</td></tr>
  </tbody>
</table>

<h2 id="data-ml">Data & ML</h2>

<p>See <a href="data-ml/">data-ml/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Data Engineer</td><td><code>data-ml/data-engineer.md</code></td><td>Pipelines, ETL/ELT, Kafka, Spark, Airflow, dbt</td></tr>
    <tr><td>ML Engineer</td><td><code>data-ml/ml-engineer.md</code></td><td>PyTorch, XGBoost, training, evaluation, deployment</td></tr>
    <tr><td>MLOps Specialist</td><td><code>data-ml/mlops-specialist.md</code></td><td>Model serving, feature stores, drift monitoring, CI/CD for ML</td></tr>
    <tr><td>Data Scientist</td><td><code>data-ml/data-scientist.md</code></td><td>Statistical analysis, EDA, feature engineering, visualization</td></tr>
  </tbody>
</table>

<h2 id="cloud">Cloud</h2>

<p>See <a href="cloud/">cloud/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Kubernetes Specialist</td><td><code>cloud/kubernetes-specialist.md</code></td><td>Cluster design, workloads, security, autoscaling, GitOps</td></tr>
    <tr><td>SRE Specialist</td><td><code>cloud/sre-specialist.md</code></td><td>SLO/SLI, error budgets, incident response, capacity planning</td></tr>
    <tr><td>GitOps Specialist</td><td><code>cloud/gitops-specialist.md</code></td><td>ArgoCD, Flux, Kustomize, Helm, secrets management</td></tr>
    <tr><td>Service Mesh Specialist</td><td><code>cloud/service-mesh-specialist.md</code></td><td>Istio, Linkerd, Cilium, mTLS, traffic management</td></tr>
    <tr><td>Cloud Architect</td><td><code>cloud/cloud-architect.md</code></td><td>AWS, GCP, Azure comparison, multi-cloud strategy</td></tr>
    <tr><td>Serverless Security</td><td><code>cloud/serverless-security.md</code></td><td>AWS Lambda, GCP Cloud Functions, Azure Functions security</td></tr>
    <tr><td>Multi-Cloud Networking</td><td><code>cloud/multi-cloud-networking.md</code></td><td>Connectivity, segmentation, and security across clouds</td></tr>
  </tbody>
</table>

<h2 id="testing">Testing</h2>

<p>See <a href="testing/">testing/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>E2E Testing Specialist</td><td><code>testing/e2e-testing-specialist.md</code></td><td>Playwright, Cypress, page objects, CI integration</td></tr>
    <tr><td>Visual Testing Specialist</td><td><code>testing/visual-testing-specialist.md</code></td><td>Chromatic, Percy, snapshot diff, component states</td></tr>
    <tr><td>Performance Testing Specialist</td><td><code>testing/performance-testing-specialist.md</code></td><td>k6, Locust, Gatling, load/spike/soak tests</td></tr>
    <tr><td>Chaos Engineering Specialist</td><td><code>testing/chaos-engineering-specialist.md</code></td><td>Chaos Mesh, Litmus, Gremlin, blast radius control</td></tr>
    <tr><td>Fuzz Testing</td><td><code>testing/fuzz-testing.md</code></td><td>AFL++, libFuzzer, Honggfuzz, automated vulnerability discovery</td></tr>
  </tbody>
</table>

<h2 id="graphql">GraphQL</h2>

<p>See <a href="graphql/">graphql/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>GraphQL Specialist</td><td><code>graphql/graphql-specialist.md</code></td><td>Schema design, resolvers, DataLoader, caching, Relay</td></tr>
  </tbody>
</table>

<h2 id="embedded">Embedded</h2>

<p>See <a href="embedded/">embedded/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>C/C++ Developer</td><td><code>embedded/c-cpp-developer.md</code></td><td>Systems programming, CMake, embedded, RTOS</td></tr>
    <tr><td>Embedded Rust Developer</td><td><code>embedded/embedded-rust-developer.md</code></td><td>no_std, Zephyr, probe-rs, PAC/HAL, Renode</td></tr>
    <tr><td>IoT / OT Security</td><td><code>embedded/iot-ot-security.md</code></td><td>ICS assessment, Modbus/DNP3/BACnet, Purdue model, firmware RE, MQTT security</td></tr>
  </tbody>
</table>

<h2 id="game-dev">Game Development</h2>

<p>See <a href="game-dev/">game-dev/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Unity Developer</td><td><code>game-dev/unity-developer.md</code></td><td>Unity, C#, URP/HDRP, Addressables, DOTS</td></tr>
    <tr><td>Unreal Developer</td><td><code>game-dev/unreal-developer.md</code></td><td>UE5, C++, Blueprint, GAS, Nanite, Lumen</td></tr>
  </tbody>
</table>

<h2 id="security-recon">Security / Recon</h2>

<p>See <a href="security/recon/">security/recon/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Attack Surface Recon</td><td>OSINT, subdomain enumeration, cloud asset discovery, passive/active recon</td></tr>
    <tr><td>Wireless Security</td><td>Wi-Fi (WPA2/3, WPS, PMKID, evil twin), Bluetooth, RFID, SDR</td></tr>
    <tr><td>OSINT & Threat Research</td><td>Social media OSINT, dark web, data leaks, domain/infrastructure intel, threat actor profiling</td></tr>
  </tbody>
</table>

<h2 id="security-web-pentest">Security / Web Pentest</h2>

<p>See <a href="security/web-pentest/">security/web-pentest/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Web Vulnerability Hunter</td><td>SQLi, XSS, SSRF, IDOR, business logic, file upload exploitation</td></tr>
    <tr><td>API Pentester</td><td>REST, GraphQL, gRPC security testing, JWT attacks, introspection abuse</td></tr>
    <tr><td>Auth Bypass Specialist</td><td>Authentication/authorization bypass, OAuth abuse, session attacks</td></tr>
    <tr><td>Server-Side Exploitation</td><td>SSTI, deserialization, command injection, XXE, race conditions</td></tr>
    <tr><td>Cloud Security Assessment</td><td>AWS/GCP/Azure misconfiguration, container escape, IAM abuse</td></tr>
    <tr><td>WAF Bypass Specialist</td><td>Filter evasion for SQLi, XSS, SSRF, LFI across major WAFs</td></tr>
    <tr><td>Browser Security</td><td>Chromium/Firefox arch, SOP, CSP bypass, postMessage, DOM clobbering, XS-Leaks, extension security</td></tr>
    <tr><td>Container Security</td><td>Docker/K8s security, admission controllers, image scanning, runtime security (Falco)</td></tr>
    <tr><td>Cloud Posture</td><td>AWS/GCP/Azure CSPM, IAM analysis, IaC scanning (Checkov, tfsec), compliance</td></tr>
    <tr><td>Bug Bounty Hunter</td><td>Recon methodology, subdomain enum, URL discovery, nuclei, Burp Suite, report writing</td></tr>
    <tr><td>Supply Chain Security</td><td>SBOM (SPDX/CycloneDX), Sigstore/cosign, SLSA, dependency confusion, SCA scanning</td></tr>
    <tr><td>DevSecOps Pipeline</td><td>SAST/DAST/SCA in CI/CD, security gates, secret scanning, container signing</td></tr>
    <tr><td>Pentest Automation</td><td>Recon pipelines, web fuzzing, async python framework, report generation, wrappers</td></tr>
  </tbody>
</table>

<h2 id="security-mobile-pentest">Security / Mobile Pentest</h2>

<p>See <a href="security/mobile-pentest/">security/mobile-pentest/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Mobile App Pentester</td><td>iOS/Android static/dynamic analysis, API testing, data storage flaws</td></tr>
    <tr><td>iOS Security Researcher</td><td>Entitlements, TCC bypasses, XPC exploitation, Mach port abuse</td></tr>
    <tr><td>Android Security Researcher</td><td>Root detection bypass, keystore analysis, IPC abuse, modding</td></tr>
  </tbody>
</table>

<h2 id="security-desktop">Security / Desktop Exploitation</h2>

<p>See <a href="security/desktop/">security/desktop/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Windows Exploit Development</td><td>Stack/heap overflow, kernel exploitation, token stealing, SEH/ROP</td></tr>
    <tr><td>Linux Privilege Escalation</td><td>SUID, capabilities, kernel exploits, container escape, cron abuse</td></tr>
    <tr><td>macOS Security Research</td><td>SIP/TCC bypass, XPC services, code signing, Mach ports, entitlement abuse</td></tr>
    <tr><td>Binary Exploitation</td><td>Reverse engineering, fuzzing, UAF, type confusion (C/C++/Rust, all platforms)</td></tr>
    <tr><td>Python Application Security</td><td>Pickle RCE, sandbox escape, Electron/Node.js, desktop scripting vulns</td></tr>
    <tr><td>Desktop Threat Hunting</td><td>Cross-platform desktop bug hunting, IPC abuse, privilege escalation research</td></tr>
    <tr><td>Reverse Engineering</td><td>Binary RE (PE/ELF/Mach-O), Ghidra, IDA, Frida, angr, anti-analysis bypass, patching</td></tr>
    <tr><td>Active Directory Security</td><td>BloodHound, kerberos attacks, ACL abuse, DCSync, NTLM relay, AD hardening</td></tr>
    <tr><td>Exploit Development</td><td>Fuzzing (AFL++, libFuzzer), ROP/ret2libc, heap exploitation, kernel exploit, shellcode</td></tr>
  </tbody>
</table>

<h2 id="security-red-team">Security / Red Team</h2>

<p>See <a href="security/red-team/">security/red-team/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Adversary Simulation</td><td>Full engagement ops: initial access, C2, lateral movement, evasion, persistence</td></tr>
    <tr><td>Social Engineering</td><td>Phishing, vishing, physical tailgating, OSINT targeting, credential harvesting</td></tr>
    <tr><td>Malware Analysis</td><td>Static/dynamic binary analysis, PE/ELF/Mach-O, anti-debug bypass, YARA</td></tr>
    <tr><td>Physical Security Assessment</td><td>RFID cloning, lock bypassing, facility entry, badge system testing</td></tr>
    <tr><td>Phishing Assessment</td><td>GoPhish campaigns, DMARC/SPF/DKIM, SMTP warmup, template design, evasion techniques</td></tr>
    <tr><td>C2 Framework</td><td>Sliver/Mythic/Cobalt Strike setup, redirectors, domain fronting, Malleable C2 profiles, DNS C2</td></tr>
  </tbody>
</table>

<h2 id="security-blue-team">Security / Blue Team</h2>

<p>See <a href="security/blue-team/">security/blue-team/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Threat Hunting</td><td>Hypothesis-driven hunts across endpoints, network, cloud (Windows/Linux/macOS)</td></tr>
    <tr><td>Incident Response</td><td>NIST 800-61 methodology, containment, eradication, IR report generation</td></tr>
    <tr><td>Detection Engineering</td><td>Sigma, KQL, YARA, Splunk rules, behavioral detection, Atomic Red Team</td></tr>
    <tr><td>Threat Intelligence</td><td>MITRE ATT&CK mapping, IoC management, YARA, MISP/OpenCTI, TTP tracking, threat reports</td></tr>
    <tr><td>Vulnerability Management</td><td>Nessus/OpenVAS, CVSS/EPSS prioritization, patching SLAs, metrics, verification</td></tr>
    <tr><td>Digital Forensics</td><td>Memory (Volatility), disk (Sleuth Kit), file carving, timeline analysis, cloud forensics</td></tr>
    <tr><td>SOC Automation</td><td>SOAR playbooks, SIEM tuning (ELK/Splunk), alert triage, case management, Python engine</td></tr>
  </tbody>
</table>

<h2 id="security-purple-team">Security / Purple Team</h2>

<p>See <a href="security/purple-team/">security/purple-team/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Purple Team</td><td>Atomic Red Team, adversary emulation, detection gap analysis, Sigma rule writing, Caldera/Infection Monkey</td></tr>
    <tr><td>Purple Team Automation</td><td>Emulation campaigns and detection validation at scale</td></tr>
  </tbody>
</table>

<h2 id="security-ai-ml-security">Security / AI & ML Security</h2>

<p>See <a href="security/ai-ml-security/">security/ai-ml-security/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>AI / ML Security</td><td>OWASP Top 10 for LLMs, prompt injection defense, adversarial ML, model extraction, secure RAG</td></tr>
  </tbody>
</table>

<h2 id="content">Content</h2>

<p>See <a href="content/">content/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Technical Writer</td><td><code>content/technical-writer.md</code></td><td>Technical writing, style enforcement, code examples, tutorials</td></tr>
    <tr><td>Content Editor</td><td><code>content/content-editor.md</code></td><td>6-pass editorial review: structure, clarity, grammar, consistency, inclusivity, accuracy</td></tr>
    <tr><td>Content Reviser</td><td><code>content/content-reviser.md</code></td><td>3-level revision: light (grammar), medium (structure), heavy (restructure)</td></tr>
    <tr><td>Translator</td><td><code>content/translator.md</code></td><td>Technical translation: format preservation, locale-specific style, terminology management</td></tr>
    <tr><td>Markdown Architect</td><td><code>content/markdown-architect.md</code></td><td>Documentation structure, organization, cross-referencing</td></tr>
    <tr><td>Markdown Editor</td><td><code>content/markdown-editor.md</code></td><td>django-markdownx, markdown editors, preview rendering</td></tr>
    <tr><td>Markdown HTML</td><td><code>content/markdown-html.md</code></td><td>Markdown to HTML conversion, rendering, styling</td></tr>
  </tbody>
</table>

<h2 id="observability">Observability</h2>

<p>See <a href="observability/">observability/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>Observability Specialist</td><td><code>observability/observability-specialist.md</code></td><td>OpenTelemetry, PromQL, dashboards, alerting, tracing</td></tr>
    <tr><td>OpenTelemetry Specialist</td><td><code>observability/opentelemetry-specialist.md</code></td><td>Instrumentation, sampling, exporters, custom collector config</td></tr>
    <tr><td>Log Management Architect</td><td><code>observability/log-management-architect.md</code></td><td>Collection, shipping, storage, compliance, retention</td></tr>
  </tbody>
</table>

<h2 id="compliance">Compliance</h2>

<p>See <a href="compliance/">compliance/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>SOC 2 Specialist</td><td><code>compliance/soc2-specialist.md</code></td><td>SOC 2 trust criteria, evidence collection, audit readiness</td></tr>
    <tr><td>GDPR Specialist</td><td><code>compliance/gdpr-specialist.md</code></td><td>Data subject rights, consent management, breach notification</td></tr>
    <tr><td>GRC Automation</td><td><code>compliance/grc-automation.md</code></td><td>Risk assessment, policy management, vendor risk, evidence collection, compliance calendar</td></tr>
    <tr><td>PCI DSS Specialist</td><td><code>compliance/pci-dss-specialist.md</code></td><td>12 requirements, SAQ scoping, QSA readiness</td></tr>
    <tr><td>HIPAA Specialist</td><td><code>compliance/hipaa-specialist.md</code></td><td>Privacy Rule, Security Rule, Breach Notification</td></tr>
    <tr><td>FedRAMP Specialist</td><td><code>compliance/fedramp-specialist.md</code></td><td>Security assessment and authorization for cloud services</td></tr>
    <tr><td>SOX / ITGC Specialist</td><td><code>compliance/sox-itgc-specialist.md</code></td><td>Sarbanes-Oxley IT General Controls</td></tr>
  </tbody>
</table>

<h2 id="installation">Installation</h2>

<p>Repository: <a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a><br>
Agents: <code>agents/</code> | Skills: <code>skills/</code> | Scripts: <code>scripts/</code></p>

<p>All 181 agents (plus 24 senior agents and 21 skills) can be installed via script, npx, or manually. The installers copy to <code>~/.config/opencode/agents/</code> and <code>~/.config/opencode/skills/</code> where OpenCode discovers them automatically.</p>

<h3>Option 1: npx (No Install)</h3>

<pre><code># Everything (agents + senior + skills)
npx @xscriptor/ai-agents

# Selective
npx @xscriptor/ai-agents --agents
npx @xscriptor/ai-agents --senior
npx @xscriptor/ai-agents --skills

# Specific groups
npx @xscriptor/ai-agents --groups general,web/security,languages

# To Claude Code
npx @xscriptor/ai-agents --anthropic

# To project
npx @xscriptor/ai-agents --project</code></pre>

<h3>All 181 Specialized Agents by Group</h3>

<ul>
  <li>  <strong>General</strong> (21): code-reviewer, security-auditor, docs-writer, api-docs, refactor-agent, db-migrator, test-writer, dependency-auditor, performance-analyzer, pr-manager, release-manager, agent-creator, security-researcher, tech-researcher, research-lead, scientific-researcher, literary-researcher, cultural-researcher, psychology-researcher, trends-researcher, mega-researcher</li>
  <li><strong>Web / Security</strong> (7): web-security-auditor, api-security-specialist, auth-security-specialist, appsec-engineer, secure-coding, waf-specialist, cdn-edge-security</li>
  <li><strong>Web / Architecture</strong> (5): software-architect, system-designer, scalability-specialist, reliability-specialist, zero-trust-architect</li>
  <li><strong>Web / Frontend</strong> (7): react-specialist, vue-specialist, css-ui-specialist, frontend-performance, accessibility-specialist, nextjs-developer, angular-developer</li>
  <li><strong>Web / Backend</strong> (7): api-designer, database-specialist, microservices-architect, devops-specialist, message-queue-specialist, caching-specialist, database-security</li>
  <li>  <strong>Languages</strong> (10): python-developer, typescript-developer, go-developer, java-developer, kotlin-developer, rust-developer, vscode-language-extension, vscode-lsp-extension, vscode-debug-extension, vscode-ui-extension</li>
  <li><strong>Mobile</strong> (6): ios-developer, android-developer, react-native-developer, flutter-developer, mobile-app-secure-coding, mobile-malware-analysis</li>
  <li><strong>Data &amp; ML</strong> (4): data-engineer, ml-engineer, mlops-specialist, data-scientist</li>
  <li><strong>Cloud</strong> (7): kubernetes-specialist, sre-specialist, gitops-specialist, service-mesh-specialist, cloud-architect, serverless-security, multi-cloud-networking</li>
  <li><strong>Testing</strong> (5): e2e-testing-specialist, visual-testing-specialist, performance-testing-specialist, chaos-engineering-specialist, fuzz-testing</li>
  <li><strong>GraphQL</strong> (1): graphql-specialist</li>
  <li><strong>Embedded</strong> (3): c-cpp-developer, embedded-rust-developer, iot-ot-security</li>
  <li><strong>Game Dev</strong> (2): unity-developer, unreal-developer</li>
  <li><strong>Security / Recon</strong> (3): attack-surface-recon, wireless-security, osint-threat-research</li>
  <li><strong>Security / Web Pentest</strong> (13): web-vulnerability-hunter, api-pentester, auth-bypass-specialist, server-side-exploitation, cloud-security-assessment, waf-bypass-specialist, browser-security, container-security, supply-chain-security, devsecops-pipeline, pentest-automation, bug-bounty-hunter, cloud-posture</li>
  <li><strong>Security / Mobile Pentest</strong> (3): mobile-app-pentester, ios-security-researcher, android-security-researcher</li>
  <li><strong>Security / Desktop</strong> (9): windows-exploit-development, linux-privilege-escalation, macos-security-research, binary-exploitation, python-application-security, desktop-threat-hunting, reverse-engineering, active-directory-security, exploit-development</li>
  <li><strong>Security / Red Team</strong> (6): adversary-simulation, social-engineering, malware-analysis, physical-security-assessment, phishing-assessment, c2-framework</li>
  <li><strong>Security / Blue Team</strong> (7): threat-hunting, incident-response, detection-engineering, threat-intelligence, vulnerability-management, soc-automation, digital-forensics</li>
  <li><strong>Security / Purple Team</strong> (2): purple-team, purple-team-automation</li>
  <li><strong>Security / AI &amp; ML</strong> (1): ai-ml-security</li>
  <li>  <strong>Content</strong> (7): technical-writer, content-editor, content-reviser, translator, markdown-architect, markdown-html, markdown-editor</li>
  <li><strong>Observability</strong> (3): observability-specialist, opentelemetry-specialist, log-management-architect</li>
  <li><strong>Compliance</strong> (7): soc2-specialist, gdpr-specialist, grc-automation, pci-dss-specialist, hipaa-specialist, fedramp-specialist, sox-itgc-specialist</li>
  <li><strong>Systems</strong> (11): bash-zsh-specialist, linux-specialist, macos-specialist, linux-hardening, macos-hardening, ir-scripting, offensive-shell-scripting, network-security, windows-specialist, container-orchestration, storage-engineering</li>
  <li><strong>Privacy Engineering</strong> (3): data-mapping, consent-anonymization, privacy-dsar-ccpa</li>
  <li><strong>Blockchain / Web3</strong> (2): smart-contract-auditor, defi-wallet-bridge</li>
  <li><strong>Telecom</strong> (1): telecom-security</li>
  <li><strong>Automotive</strong> (1): automotive-security</li>
  <li><strong>Hardware</strong> (1): hardware-security</li>
  <li><strong>Medical</strong> (1): medical-device-security</li>
  <li><strong>Aviation / Maritime / Energy</strong> (2): aviation-security, maritime-energy-security</li>
  <li>  <strong>Physical / Mainframe</strong> (2): physical-security, mainframe-cyber-insurance-ediscovery</li>
</ul>

<h2 id="mega-orchestrators">Mega Orchestrators</h2>

<p>See <a href="mega/">mega/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>Workflow</th><th>Orchestrates</th></tr></thead>
  <tbody>
    <tr><td>Mega DevSecOps</td><td>CI/CD pipeline</td><td>Secure coding, supply chain, containers, deploy, observability</td></tr>
    <tr><td>Mega IR</td><td>Incident response</td><td>SOC, forensics, network, threat intel, IR scripting, detection</td></tr>
    <tr><td>Mega App Dev</td><td>Application development</td><td>Architecture, implementation, testing, review, release</td></tr>
    <tr><td>Mega Compliance</td><td>Compliance readiness</td><td>Gap analysis, remediation, evidence, audit prep</td></tr>
    <tr><td>Mega Security Assessment</td><td>Penetration testing</td><td>Recon, scanning, exploitation, PE, lateral, reporting</td></tr>
    <tr><td>Mega Migration</td><td>Infrastructure migration</td><td>Audit, plan, migrate, parallel run, cutover, optimize</td></tr>
    <tr><td>Mega Research + Action</td><td>Research → Implementation</td><td>Multi-layer research + workflow delegation</td></tr>
  </tbody>
</table>

<h2 id="github">GitHub</h2>

<p>See <a href="github/">github/</a>.</p>

<table>
  <thead><tr><th>Agent</th><th>File</th><th>Description</th></tr></thead>
  <tbody>
    <tr><td>GitHub Actions Workflow</td><td><code>github/actions-workflow.md</code></td><td>CI/CD pipelines, custom actions, reusable workflows, matrix builds, caching</td></tr>
    <tr><td>GitHub Admin &amp; Security</td><td><code>github/admin-security.md</code></td><td>Branch protection, Dependabot, secret scanning, org security, CODEOWNERS</td></tr>
    <tr><td>GitHub API &amp; Automation</td><td><code>github/api-automation.md</code></td><td>CLI automation, REST/GraphQL API, webhooks, bots, issue triage</td></tr>
  </tbody>
</table>

<h3>Option 2: Remote Script (No Clone)</h3>

<pre><code>curl -fsSL https://raw.githubusercontent.com/xscriptor/ai/main/scripts/install-agents.sh | bash
curl -fsSL https://raw.githubusercontent.com/xscriptor/ai/main/scripts/install-agents.sh | bash -s -- --project</code></pre>

<h3>Option 3: Clone and Install</h3>

<pre><code>git clone https://github.com/xscriptor/ai.git
cd ai

# Everything (agents + senior + skills)
./scripts/install-agents.sh

# Selective
./scripts/install-agents.sh --agents
./scripts/install-agents.sh --senior
./scripts/install-agents.sh --skills

# Specific groups
./scripts/install-agents.sh --groups general,web/security

# Interactive
./scripts/install-agents.sh --interactive

# Project-level
./scripts/install-agents.sh --project</code></pre>

<h3>Option 4: Manual Copy</h3>

<pre><code>cp agents/general/code-reviewer.md ~/.config/opencode/agents/
cp agents/web/security/web-security-auditor.md ~/.config/opencode/agents/
cp senior/agents/web/senior-fullstack.md ~/.config/opencode/agents/
cp senior/skills/architecture/SKILL.md ~/.config/opencode/skills/architecture/</code></pre>

<h2>Related Resources</h2>

<ul>
  <li><a href="https://opencode.ai/docs/agents">OpenCode Agents Documentation</a></li>
  <li><a href="https://opencode.ai/docs/permissions">OpenCode Permissions Guide</a></li>
  <li><a href="../skills/">Skills</a></li>
  <li><a href="https://github.com/xscriptor/ai">github.com/xscriptor/ai</a></li>
</ul>

<div id="x" align="center">
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
