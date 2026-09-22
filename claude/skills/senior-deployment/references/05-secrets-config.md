# Secrets and Config

Scope: externalized configuration, secret manager selection and injection patterns, workload-identity authentication, rotation, 12-factor configuration, and secret scanning.

## Configuration Model

Treat configuration as a typed, validated interface of the service.

- Sources in precedence order, lowest to highest: built-in defaults, config file, environment variables, command-line flags. Document and test the precedence.
- Validate all required configuration at startup and fail fast with a clear message naming the missing key. A service that starts with defaults for a required value is a time bomb.
- Emit effective configuration (with secret values redacted) at startup or on a debug endpoint to make environment differences visible.
- Version the configuration schema alongside the code; renaming a key is a breaking change for deployments.
- 12-factor: store config in the environment (or a mounted source), not in the codebase. Environment variables are the portable interface; files are acceptable when the runtime prefers them.
- Separate configuration (non-sensitive, reviewable) from secrets (sensitive, access-controlled, audited). They have different lifecycles.

Typed config example:

```ts
const schema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  DATABASE_URL: z.string().url(),
  FEATURE_NEW_BILLING: z.coerce.boolean().default(false),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
});
const config = schema.parse(process.env);
```

- Defaults are for development only where possible; production should be explicit. A validation error beats a silent default in production.
- Never log full environment dumps; they leak secrets and tokens.

## Secret Manager Selection

| Store | Strengths | Weaknesses | Use when |
|---|---|---|---|
| Cloud secret manager | Identity-integrated, managed rotation hooks, audit logs | Cloud-specific APIs and pricing | Default for cloud-native workloads |
| Vault-compatible | Dynamic credentials, leases, transit encryption, multi-cloud | You operate it; unsealing and upgrades are real work | Dynamic secrets or multi-cloud requirements |
| SOPS-encrypted files | GitOps-friendly, no runtime service, simple | Key distribution and rotation are manual-ish; no dynamic secrets | Small teams, Kubernetes GitOps, few secrets |
| Sealed secrets | Cluster-scoped decryption, GitOps-native | Cluster-bound keys; controller is a trust anchor | Single-cluster Kubernetes without an external manager |
| Cloud KMS plus custom tooling | Maximum control | High maintenance, easy to get wrong | Rare; usually a sign to use a manager |
| Plain CI variables / repo files | Convenient | No rotation, broad exposure, hard to audit | Development-only placeholders, never production |

Selection rules:

- One system of record per environment. Duplicated secrets in two stores guarantee divergence.
- Every secret has an owner, a purpose, and a rotation schedule recorded in an inventory.
- Access is via identity (workload identity, IAM role, Kubernetes service account), and the trust policy is scoped to the workload, not the cluster.
- Audit reads; alert on unusual access patterns and on access from unexpected identities.

## Injection Patterns

| Pattern | Mechanics | Notes |
|---|---|---|
| Runtime SDK fetch | App calls the manager at startup | Works anywhere; app depends on the manager library; cache briefly |
| Init container / entrypoint fetch | Fetch, write to tmpfs, exec app | Language-agnostic; beware process environment exposure |
| CSI secret store driver | Mount secrets as files in the pod | Files update on rotation; app must re-read or watch |
| Operator sync to Kubernetes Secret | Controller materializes a Secret from the manager | Convenient; the Kubernetes Secret is now a copy to protect and refresh |
| Sidecar/agent injection | Proxy or agent delivers secrets | Adds a component; strong when paired with dynamic credentials |
| Encrypted files at deploy time | Decrypt with a key from KMS or an agent | GitOps-friendly; key management is the critical path |

Guidance:

- Prefer file mounts over environment variables for secrets: env vars leak into crash dumps, child processes, debug endpoints, and `/proc`.
- Do not bake secrets into container images. Build args and layer history are readable. See `./01-containers.md`.
- Do not pass secrets through CI job outputs or logs; mask and avoid echoing.
- Inject the narrowest possible credential. A service that needs read access to one bucket should not get a database admin password.
- Cache secret values in memory with a TTL rather than fetching per request. Handle refresh failures without crashing.
- Treat the manager as a dependency: define behavior for startup when it is briefly unavailable (retry with bounded backoff, fail closed on missing required secrets).

## Workload Identity and OIDC

Long-lived static credentials in CI or workloads are the primary cause of cloud credential leaks.

- CI assumes a cloud role via OIDC with a trust policy restricting repository, branch or environment, and workflow. See `./02-ci.md`.
- Workloads use the platform identity: IAM roles for service accounts, workload identity federation, or managed identities. No key files on disk.
- Kubernetes: bind a service account to a cloud identity, and scope the identity per workload, not per namespace where possible.
- Database access uses short-lived credentials or IAM database authentication instead of long-lived passwords where the engine supports it.
- Tokens are audience-restricted and short-lived; a token minted for staging must not be accepted by production.
- Prefer mTLS plus identity documents over shared tokens for service-to-service authentication.

## Rotation

- Automate rotation with a manager; manual rotation at scale does not happen.
- Rotation must be zero-downtime: support two valid credentials during the overlap window (dual-write or dual-read), then retire the old one.
- Pattern for static secrets: create new version, deploy consumers to read `latest`, verify usage of the new version, then revoke the old version.
- Prefer dynamic short-lived credentials where available (database users, cloud STS, broker credentials); rotation becomes lease renewal.
- Rotation triggers: schedule, personnel change, suspected exposure, and provider-recommended windows.
- Test rotation in staging on the same automation that production uses. An untested rotation script is not a plan.
- Rotation of certificates and signing keys follows the same discipline, with trust-store overlap.

## Secret Scanning and Leak Response

- Scan in three places: pre-commit hooks (fast feedback), CI on every push, and historical/full-history scans. See `./02-ci.md`.
- Enable provider push protection where available; it stops known-pattern secrets before they enter history.
- Scanning finds known formats; also scan for entropy and for internal patterns (connection strings, private keys).
- Treat any secret that entered git history, logs, or an image layer as compromised even if the commit was reverted. Reverting does not un-leak.
- Leak response runbook: revoke and rotate first, then assess blast radius from audit logs, then remove from history if required by policy, then add a detector to prevent recurrence.
- Prefer short-lived credentials so a leak has a short useful life; that is the only durable mitigation.

## Kubernetes and Cloud Specifics

- Kubernetes Secrets are base64, not encryption: enable encryption at rest, restrict `get`/`list` on secrets with RBAC, and prefer a CSI driver or external manager over native Secrets where possible.
- Avoid mounting the same Secret into every container in a pod; sidecars inherit it. Scope service accounts and mounts per container where the platform permits.
- Use projected service account tokens with explicit audiences and short lifetimes for workload identity; do not reuse the default token.
- Cloud secret managers should be reached through the workload's identity, and the resource policy should name the identity, not the cluster or namespace broadly.
- Keep an escape hatch documented for the day the manager is unavailable: break-glass credentials stored offline, with dual control and automatic expiry, plus an alert if used.
- Consider regional failover for secret retrieval if the service is multi-region; an in-region outage should not prevent new instances from starting.

## Multi-Replica and Multi-Tenant Considerations

- Secrets are fetched per process, not per request; refresh is asynchronous. Stagger refresh across replicas to avoid a thundering herd on the manager.
- Watch for rate limits: hundreds of pods fetching secrets at startup can exhaust manager quotas. Use caching, retries with jitter, and a shared agent where available.
- Tenant isolation in a shared cluster: a per-tenant secret path plus per-tenant identity; never a shared secret with tenant selection at the application layer when the security boundary matters.
- Config for multiple tenants should be validated the same as any other input; tenant-provided configuration is untrusted input.
- Rotation in a multi-tenant system is per tenant and scheduled; a global credential shared across tenants cannot be rotated safely and should be split first.

## Audit and Detection

- Log every secret read and write with the requesting identity, resource, and decision; retain long enough to investigate an incident that is discovered late.
- Alert on reads from unexpected identities, from unexpected network locations, or at unusual rates; a single stolen credential often shows up as a burst of reads.
- Watch for secrets appearing in new places: image layers, CI artifacts, log streams, and issue trackers. Scanning coverage should grow with each incident or near miss.
- Correlate secret access with deploy events; a read by a service that was not deployed is worth investigating.
- Review access grants on a schedule and remove unused identities and permissions.

## Migration Notes

- Moving from env-var secrets to file mounts: run both paths behind a config flag, verify the file path is read on refresh, then remove the env path. Remember child processes and crash dumps.
- Moving from CI-stored cloud keys to OIDC: create the trust policy first, prove it in a non-production role, then delete the static keys and monitor for failures.
- Moving from a shared database user to per-service users: create and validate the new grants in shadow mode, switch one service at a time, then revoke the shared user.
- Moving from plain Kubernetes Secrets to an external manager: sync first (operator), then migrate mounts to CSI, then remove the synced Secrets.
- Moving from manual rotation to automated: run the new automation in dry-run through two scheduled cycles before it performs the first real rotation.

## Anti-Patterns

- Secrets in `.env` files committed to the repository, even in a private repo.
- One shared "app" credential across services and environments.
- Production credentials available to CI jobs that run untrusted PR code.
- Secrets in Helm values, Kubernetes manifests, or Terraform variables without encryption.
- Rotation performed by replacing a value in two systems by hand.
- Secrets in URLs or query strings, which end up in logs and traces.
- Logging configuration values without redaction.
- Dynamic secrets never revoked; lease sprawl.
- Relying on obscurity (private repo, internal network) as a control.
- A secret manager deployed but bypassed by "temporary" env vars.

## Checklist

- [ ] All required config typed and validated at startup; failures are explicit.
- [ ] Precedence rules documented and tested.
- [ ] One secret store per environment, with an inventory of owner and rotation.
- [ ] Identity-based access only; no long-lived cloud or database credentials in CI or workloads.
- [ ] Injection uses file mounts or a CSI/agent pattern; no secrets in images or env where avoidable.
- [ ] Secrets cached with TTL; manager outage behavior is defined.
- [ ] Rotation automated, dual-credential, and rehearsed.
- [ ] Scanning in pre-commit, CI, and full history; push protection enabled.
- [ ] Leak runbook tested, with revocation before remediation.
- [ ] Audit logging on secret reads, with alerts for anomalies.
