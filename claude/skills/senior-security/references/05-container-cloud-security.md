# Container and Cloud Security

> Scope: hardening Kubernetes, images, admission, cloud IAM, network policy, cloud secrets, and continuous posture management.

## Shared responsibility

Cloud providers secure the provider plane; you secure identities, configuration, workloads, and data. Every service has a different split, so write down the boundary per service. Assume misconfiguration, not provider compromise, is the primary threat.

| Layer | You own | Provider owns |
|---|---|---|
| Cloud IAM | Policies, roles, federation, credential hygiene | IAM service availability and integrity |
| Managed Kubernetes | Workloads, RBAC, network policy, admission, images | Control plane availability (in managed offerings) |
| VMs and containers | Patching, hardening, runtime config | Hypervisor and physical |
| Managed data services | Access control, encryption config, backups, schema | Engine, patching of managed versions |
| Serverless | Code, identity, triggers, dependencies | Runtime and platform scaling |

## Kubernetes hardening baseline

| Area | Practice |
|---|---|
| Versions | Run supported minors only (the project maintains roughly the latest three; verify upstream) and patch promptly |
| API server | Private endpoint where possible, strong authn, audit logging on, authorization via RBAC, disable anonymous auth |
| etcd | Encryption at rest for secrets, TLS, restricted network access, tested backups |
| RBAC | Namespaced roles, no `cluster-admin` for applications, no wildcard verbs/resources, audit role bindings |
| Service accounts | Disable token automount unless needed; projected tokens with audience and expiry; one SA per workload |
| Pod Security | Pod Security Admission `restricted` for namespaces by default; exceptions documented and narrowed |
| Workload context | `runAsNonRoot`, fixed high UID, read-only root filesystem, drop ALL capabilities, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault` |
| Host access | No `hostPath`, `hostNetwork`, `hostPID`, or privileged containers without reviewed exceptions |
| Network | Default-deny policy; explicit ingress and egress; see below |
| Secrets | External secret manager or encrypted store; never plain Secrets created by hand |
| Admission | Policy that blocks the above violations; see below |
| Node access | No SSH by default; use debug pods with explicit, time-boxed grants |
| Audit | API audit logs shipped off-cluster; alerts on privileged role changes and exec into pods |

```yaml
# Pod security-context fragment (baseline)
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  seccompProfile: { type: RuntimeDefault }
containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
```

## Image security

- Use minimal bases: distroless or scratch for static binaries, slim images otherwise. Fewer packages mean fewer vulnerabilities and a smaller attack surface.
- Pin base images by digest; rebuild regularly to pick up patched bases. A pinned digest without a rebuild path ages into vulnerability debt.
- Multi-stage builds: build tools never ship in the runtime image.
- Run as non-root, set a fixed UID, and use a read-only root filesystem with explicit writable mounts.
- Scan images on build and continuously for running digests; gate criticals with a fix available.
- Sign images and attest SBOM/provenance; verify at admission. Details in `./06-supply-chain.md`.
- Keep a runtime inventory linked to SBOMs so "which workloads ship component X" is a query.

```dockerfile
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
USER 65532:65532
ENTRYPOINT ["/api"]
```

(Go toolchain versions move quickly; use a supported release and verify upstream.)

## Admission control

Admission is the enforcement point for cluster-wide policy. Prefer built-in mechanisms before adding webhooks, because webhooks add availability risk.

| Mechanism | Use | Notes |
|---|---|---|
| Pod Security Admission | Namespace-level baseline/restricted | Built in; label namespaces; exceptions per namespace |
| ValidatingAdmissionPolicy (CEL) | Custom, in-process validation | No webhook dependency; good for simple invariants |
| Kyverno | Policy engine with image verification and mutation | Broad library; validate policies in CI |
| Gatekeeper (OPA) | Rego policy with constraint templates | Strong when you already use OPA |
| Sigstore policy-controller | Keyless signature verification | Pairs with cosign |
| Mutating webhooks | Defaults injection (sidecars, labels) | Keep minimal; each webhook is a cluster availability dependency |

Rules for policy systems:

- Run policies in audit mode first, measure violations, then enforce; never enforce untested policy cluster-wide.
- Test policies against manifests in CI; policy is code with review.
- Fail closed for security checks, but operate webhooks with multiple replicas, failure policies chosen deliberately, and narrow match scopes.
- Log policy denials; frequent denials usually mean defaults are wrong, not that attackers are busy.

## Cloud IAM pitfalls

| Pitfall | Why it hurts | Control |
|---|---|---|
| Wildcard actions/resources | One compromised role owns the account | Least privilege, generated from access logs, reviewed periodically |
| Long-lived access keys | Leak once, valid forever | Workload identity, OIDC federation, no static keys |
| Confused deputy | A service is tricked into acting for the wrong tenant | External IDs, audience conditions, source-account restrictions |
| Cross-account trust with `*` principal | Any account can assume | Restrict principal, add conditions, monitor trust policy changes |
| Privilege escalation paths | Small permissions compose into admin (`iam:PassRole`, `iam:CreatePolicyVersion`) | Analyze with CIEM tooling, remove composition paths |
| Permissions at the account root | Blast radius equals the account | Separate accounts/projects per environment and function |
| Unused identities | Forgotten roles and keys are entry points | Inventory, last-used analysis, automatic disable |
| Metadata service exposure | SSRF reaches instance credentials | Require IMDSv2 or equivalent, hop limits, egress blocks |
| Over-scoped CI roles | Pipeline can change production without review | Separate plan and apply roles, environment approvals, OIDC with conditions |
| Missing guardrails | Nothing blocks obvious misconfig | Permission boundaries, SCPs/organization policies, deny lists |

Identity hygiene: every human uses SSO with MFA; every workload uses a distinct identity; every credential has an owner and an expiry; every cross-boundary trust has conditions.

## Network policy

- Start with default-deny ingress and egress per namespace; add explicit flows.
- Policy must cover both directions; an ingress-only policy still allows data exfiltration.
- Egress allowlists are critical for workloads processing untrusted input: agent runtimes, scrapers, renderers, and anything with SSRF potential.
- Use identity-based policy where available (Cilium, Calico with service accounts) rather than IP ranges that change with scaling.
- Watch DNS: pod egress policies that block DNS break everything and get disabled. Allow the cluster DNS explicitly.
- Test policy with connectivity tests in CI or a staging cluster; a policy that blocks a dependency is an outage.
- Consider L7 policy for mesh or eBPF platforms when method/path restrictions add real value; otherwise L3/L4 identity policy is enough.

```yaml
# Default deny for a namespace (Cilium example; NetworkPolicy works similarly)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: default-deny, namespace: app }
spec:
  endpointSelector: {}
  ingress: []
  egress:
    - toEndpoints:
        - matchLabels: { k8s:io.kubernetes.pod.namespace: kube-system, k8s-app: kube-dns }
      toPorts:
        - ports: [{ port: "53", protocol: UDP }]
```

## Secrets in cloud

- Source of truth: a managed secret store (cloud secret manager, Vault) or encrypted Git with a sealed-secrets pattern; pick one and document it.
- Delivery: External Secrets Operator or Secrets Store CSI with workload identity. Avoid hand-created Kubernetes Secrets and avoid baking secrets into images.
- Prefer dynamic credentials: database IAM auth, short-lived STS tokens, secretless access to storage via workload identity.
- Encrypt at rest with your own KMS key where supported; track which key protects which secret.
- Rotate automatically and test rotation in staging; an untested rotation procedure is broken.
- Audit secret access and alert on reads from unexpected principals.
- Do not put secrets in environment variables where avoidable: they leak through crash dumps, child processes, and process listings. Prefer files with tight permissions or SDK-side retrieval.

## Runtime security and posture

| Program | Question | Typical tooling |
|---|---|---|
| CSPM | Is the cloud account configured safely? | Provider-native and third-party posture scanners |
| CIEM | Who can do what, and what is unused? | Effective-permission analysis, last-used data |
| KSPM | Are clusters compliant with the baseline? | CIS benchmark scanners, policy reports |
| CWPP | What is running and are workloads protected? | Agent-based and agentless workload scanning |
| Runtime detection | Is behavior anomalous now? | Falco, Tetragon, seccomp/AppArmor enforcement |
| Vulnerability management | What is exposed and fixable? | Registry scanning plus running-image scanning |

Operating model: scan continuously, route findings to owners, fix by SLA, and track drift. Posture tools that produce reports nobody reads are expensive logging.

## Anti-patterns

- Single shared cluster for all environments with cluster-admin for everyone.
- Admission webhooks enforced everywhere with one replica.
- Signed images verified only at build, with mutable tags deployed.
- Long-lived cloud access keys stored in CI secrets.
- `aws_iam_policy` with `Action: "*"` and a comment saying "tighten later".
- Default VPC with allow-all security groups and public databases.
- Network policy applied only to the default namespace.
- Kubernetes Secrets created manually and never rotated.
- Runtime agents deployed in detect-only mode forever.
- Patching clusters only when an audit is scheduled.

## Checklist

- [ ] Cluster runs supported versions; control plane and etcd hardened; audit logs exported.
- [ ] RBAC follows least privilege; no application cluster-admin; wildcards removed.
- [ ] Pod Security `restricted` by default with documented exceptions.
- [ ] Workload security contexts set (non-root, read-only, no caps, seccomp).
- [ ] Images minimal, digest-pinned, signed, scanned on build and continuously.
- [ ] Admission policy enforced with tested policies and HA webhooks.
- [ ] Cloud IAM uses workload identity; no long-lived keys; escalations analyzed.
- [ ] Default-deny ingress and egress with explicit flows and tested connectivity.
- [ ] Secrets delivered by identity from a manager; rotation automated and tested.
- [ ] Runtime detection on; posture programs owned with SLAs and drift tracking.
