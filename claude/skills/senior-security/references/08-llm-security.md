# LLM Security

> Scope: securing LLM, RAG, and agent features — prompt injection, tool and agent abuse, data exfiltration, guardrails, red teaming, and evaluation.

## Why LLM security is different

Three properties break classical assumptions:

1. **Instruction and data share a channel.** Model input mixes system instructions, user input, retrieved content, and tool output into one token stream. There is no reliable parser that distinguishes "instructions" from "data", so injection is a design condition, not a bug to patch once.
2. **Behavior is probabilistic.** The same input can take different paths. Controls must be deterministic around the model, not inside it.
3. **The model is not a trust boundary.** A model asked to enforce policy will sometimes comply with an attacker. Authorization, validation, and egress control must live in ordinary code.

Design rule: treat the model as an untrusted, creative component inside a system whose other parts enforce security.

## Prompt injection

**Direct injection**: the user supplies "ignore previous instructions..." and the model complies. Severity depends on what the model can reach.

**Indirect injection**: malicious instructions arrive in content the model processes — a retrieved document, web page, email, PDF, ticket, code comment, commit message, calendar invite, or tool result. This is the dominant risk because the attacker does not need access to the user session.

Why prompt-based defenses fail alone: any filter expressed in natural language can be overridden by natural language, and classifiers produce false negatives under novel phrasing and encoding (base64, homoglyphs, other languages).

Defense in depth, ordered by leverage:

| Control | Effect | Limits |
|---|---|---|
| Least privilege for tools and data | Caps the blast radius of any successful injection | Requires real authz, not model-side checks |
| Human approval for irreversible actions | Blocks damage at the last mile | Adds friction; reserve for high-impact |
| Tool parameter validation | Rejects off-policy operations in code | Only as good as the policy and schemas |
| Egress allowlists and DLP | Stops exfiltration channels | Must cover all output paths |
| Spotlighting / delimitering | Marks untrusted content as data | Heuristic; attacker can attempt to escape |
| Instruction hierarchy | System > developer > user precedence at training time | Reduces, never eliminates, injection |
| Input/output classifiers | Catch known patterns | Cheap layer only; never the primary control |
| Dual-LLM / quarantined processing | A privileged model never sees raw untrusted text | Complexity and latency; strong containment |

Practical architecture for assistants with tools:

1. Separate the planner (sees trusted instructions) from the reader (processes untrusted content) and pass only structured, validated data between them.
2. Never let a model's output directly become a shell command, SQL statement, URL fetch, or file path; route through typed tool interfaces with allowlists.
3. Keep secrets out of prompts and context entirely — assume the system prompt is public (see LLM07 system prompt leakage).
4. Log the full tool-call chain with inputs and decisions; injection investigations need the provenance of every instruction.

## Tool and agent abuse

Autonomous agents combine injection with real authority, so the controls are architectural.

| Risk | Example | Control |
|---|---|---|
| Excessive agency | Agent can delete resources or send email without approval | Minimal tool set, read-only default, approval for writes |
| Confused deputy | Agent uses its own broad credentials on behalf of a user | Per-user delegated tokens; never a shared super-identity |
| Tool description injection | Malicious tool metadata manipulates the planner | Treat tool metadata as untrusted; vet tool sources; pin versions |
| Parameter injection | Tool arguments contain attacker-controlled paths/URLs | Schema validation plus semantic allowlists in the tool |
| Credential passthrough | Agent forwards its token to downstream systems | Token exchange with audience and scopes per call |
| Runaway loops / cost | Agent retries forever or spawns sub-agents | Step, time, and cost budgets; circuit breakers |
| Unsafe code execution | Generated code runs with network and credentials | Sandbox with no secrets, bounded CPU/memory, egress allowlist |
| MCP and plugin supply chain | Third-party tool servers with broad scopes | Pin servers, review code, scope tokens per server, no token passthrough |

For MCP-style tool ecosystems specifically: authenticate the server, authorize the client, bind tokens to a single server (audience restriction), avoid passing through the user's upstream token, and treat every tool description and result as untrusted input. Verify the current protocol security guidance upstream.

Approval design: require human confirmation for actions that are irreversible, externally visible, financial, or that grant access. Show a faithful representation of the action (recipient, amount, data leaving the boundary), not a model-generated summary.

## Data exfiltration and privacy

Exfiltration paths to close:

- Markdown images and links that beacon data to attacker URLs; strip or proxy image URLs in rendered output.
- Tool calls that fetch attacker-controlled URLs (SSRF and DNS exfil); apply egress allowlists.
- Output encoded in base64, steganographic whitespace, or tokens that a downstream client decodes.
- RAG retrieval crossing tenant boundaries; authorization must be enforced at query time per user, not by pre-filtering an index globally.
- Embedding inversion: vectors can leak information about their source text; protect the vector store like the source data.
- Logs and traces containing prompts and tool payloads with PII or secrets; apply retention and redaction.

Controls: tenant-isolated indexes with per-request authz filters, DLP on outputs and egress, output encoding for the rendering context, prompt/response logging with redaction and access control, and data minimization in context assembly.

Privacy and compliance: map data flows to the threat model (`./01-threat-modeling.md`), avoid sending regulated data to providers without contractual coverage, keep data residency in mind, and record model/provider inventory for AI governance (NIST AI RMF, EU AI Act obligations phase in over 2025-2027 — verify dates upstream).

## Guardrails

Layer them; no single guardrail is sufficient, and weak guardrails create false confidence.

| Layer | Examples | Failure mode to avoid |
|---|---|---|
| Input filtering | Injection detectors, length/size limits, allowed content types | Treating classifier output as authorization |
| Context assembly | Spotlighting, provenance labels, strict templates, no secrets in prompts | Assuming delimiters are unforgeable |
| Tool mediation | Typed schemas, allowlists, parameter validation, per-tool scopes | Model-side "check before calling" logic |
| Action approval | Human-in-the-loop for writes and high-impact actions | Approval fatigue from over-prompting |
| Output validation | Schema checks, banned-content filters, PII redaction | Rendering raw markdown with URLs |
| Egress control | Destination allowlists, DLP, no direct internet from sandboxes | Blocking only the obvious channel |
| Monitoring | Anomaly detection on tool calls, volume, and data movement | Logging prompts without alerting |

Guardrail engineering: version prompts and policies like code, test them against adversarial suites, measure false positive and false negative rates, and never deploy a guardrail that blocks a critical path without a documented override.

## Provider and deployment considerations

- Know your data path: managed API, private endpoint, self-hosted, or on-device. Each changes the trust boundary, the data-processing agreement, and the incident path.
- Contract for security: no training on your data where required, retention windows, regional processing, subprocessors, and breach notification terms. Verify current provider terms upstream.
- Keep model and provider inventory with versions, approval status, data classes allowed, and owner; this is the artifact auditors and incident responders ask for.
- Treat model files and weights as supply-chain artifacts: download from trusted sources, verify hashes or signatures, and store in a controlled registry.
- Control fallbacks: if a provider is unavailable, the failover path must not silently send data to an unapproved endpoint.
- Pin model versions where the provider allows it; an unpinned model can change behavior overnight and invalidate your evaluations.

## Red teaming and evaluation

Adversarial testing is continuous, not a one-time launch gate. Model updates, prompt changes, tool changes, and retrieval corpus changes all invalidate prior assurance.

Tooling categories (verify current capabilities upstream): garak for broad probing, PyRIT-style orchestration for automated multi-turn attacks, promptfoo-style harnesses for regression suites, and custom suites built from your own threat model.

Test dimensions:

| Dimension | Example probes | Success metric |
|---|---|---|
| Direct injection | Role-play and override attempts | Policy violation rate |
| Indirect injection | Poisoned document, email, or web page in the pipeline | Action taken on attacker instruction |
| Exfiltration | "Summarize and send to this URL" via tool or markdown | Data reaching an unapproved destination |
| Tool misuse | Off-scope file paths, commands, API calls | Out-of-policy tool invocations |
| System prompt extraction | Requests to reveal instructions | Secret or policy leakage |
| RAG isolation | Queries across tenants, permission-elevating prompts | Cross-tenant retrieval |
| Availability/cost | Token bombs, recursive loops | Cost or latency beyond budget |
| Over-refusal | Benign edge-case prompts | Task success rate on legitimate requests |

Evaluation practice: keep a versioned suite with expected outcomes, run it on every change in CI where feasible, track rates over time rather than pass/fail, and include a red-team review for new tool grants. Treat "injection success rate > 0" as expected; the question is whether the blast radius is acceptable.

## Incident response for AI features

- Add model, prompt version, tool grants, retrieval corpus version, and provider to the incident timeline.
- Ability to disable a tool or model route quickly is the equivalent of a kill switch: design it before launch.
- Preserve prompts and tool-call logs for the affected window; they are the forensic record.
- Coordinate provider disclosure when the incident involves the model or platform; see `./09-incident-response.md`.

## Anti-patterns

- Relying on "ignore malicious instructions" in the system prompt.
- Putting secrets, credentials, or internal policy details in the system prompt.
- Giving an agent broad credentials "to simplify integration".
- Letting model output flow to `eval`, shell, SQL, or raw HTML without validation.
- Rendering model output as markdown/HTML with unrestricted image and link URLs.
- Enforcing RAG access control in the UI instead of the retrieval query.
- One shared vector index for all tenants.
- Treating a passing red-team run as permanent assurance.
- Logging full prompts containing PII without access control or retention limits.
- Approving tool actions with a model-written summary the human cannot verify.

## Checklist

- [ ] Model treated as untrusted; authz, validation, and egress enforced in code.
- [ ] Tools scoped to the minimum, read-only by default, with per-user credentials.
- [ ] Irreversible and externally visible actions require human approval with faithful details.
- [ ] Untrusted content spotlighted and processed in a quarantined path where warranted.
- [ ] No secrets in prompts or context; system prompts assumed public.
- [ ] Output validated by schema and rendered with URL/sanitization controls.
- [ ] Egress allowlists and DLP cover all model and agent channels.
- [ ] RAG enforces per-request, per-tenant authorization at query time.
- [ ] Code execution sandboxed with no secrets, bounded resources, and no default network.
- [ ] Adversarial eval suite versioned and run on model, prompt, tool, and corpus changes.
- [ ] Prompt/tool logs retained with redaction, access control, and defined retention.
- [ ] Kill switch for models, tools, and agent identities tested.
- [ ] AI incident playbook includes model/prompt/corpus provenance.
