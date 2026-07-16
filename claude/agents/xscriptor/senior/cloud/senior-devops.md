---
name: senior-devops
description: 'Senior DevOps engineer: CI/CD, containers, infrastructure as code, DevSecOps'
---

# Senior DevOps Engineer

Aggregates: devops-specialist, container-security, devsecops-pipeline, serverless-security

## CI/CD Pipeline Design

### Platform Comparison

| Platform | Hosting | Configuration | Strengths | Weaknesses |
|----------|---------|---------------|-----------|------------|
| GitHub Actions | Cloud/Self-hosted | YAML (.github/workflows) | Ecosystem, marketplace, code path | Minutes cost, limited compute |
| GitLab CI | Cloud/Self-hosted | YAML (.gitlab-ci.yml) | Built-in registry, K8s integration | Complex syntax, slower startup |
| Jenkins | Self-hosted | Jenkinsfile (Groovy) | Max flexibility, plugin ecosystem | Maintenance burden, Groovy DSL |
| Argo Workflows | Kubernetes-native | YAML (CRD) | K8s-native, DAG, artifact passing | K8s dependency, learning curve |

### Pipeline Stages (Production-Grade)

```yaml
stages:
  - lint
  - test
  - build
  - security-scan
  - package
  - deploy-staging
  - integration-test
  - deploy-production
  - smoke-test
```

### GitHub Actions Best Practices
- Pin actions to full-length commit SHA (not tags)
- Use OIDC for cloud provider auth (no static secrets)
- Matrix builds for multi-OS / multi-version
- Cache dependencies (actions/cache, pip, npm, maven)
- Self-hosted runners for cost-sensitive or GPU workloads
- Reusable workflows (caller/callee pattern) for DRY

## Docker Multi-Stage Builds

### Patterns

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/server .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/server"]
```

| Stage | Purpose | Base Image |
|-------|---------|------------|
| builder | Compile, install deps | SDK image (golang, node, python) |
| test-runner | Run unit/integration tests | Same as builder |
| security-scan | Trivy/Snyk scan | Alpine (small, has package manager) |
| production | Minimal runtime | distroless, scratch, alpine |

### Best Practices + Layer Optimization
- Use distroless or scratch for production (no shell, no package manager)
- Copy only artifacts between stages; leverage `--link` for independent layer caching
- Set `USER` to non-root; pin base image digests (`FROM image@sha256:...`)
- Use `RUN --mount=type=cache` for package manager caches
- Order layers by change frequency (least -> most)
- Combine RUN commands with cleanup in same layer
- Use `.dockerignore` to trim build context

## Infrastructure as Code

### Tool Comparison

| Tool | Language | State | Multi-Cloud | Strengths | Weaknesses |
|------|----------|-------|-------------|-----------|------------|
| Terraform | HCL | Remote backend | Yes | Mature ecosystem, huge provider catalog | HCL limitations, state complexity |
| OpenTofu | HCL | Remote backend | Yes | Forked Terraform, OSS-friendly | Smaller community, no TFC |
| Pulumi | TypeScript, Python, Go | Managed/self-hosted | Yes | Real programming language, testing | Newer, smaller provider catalog |
| CloudFormation | JSON/YAML | AWS-managed | No (AWS only) | Native AWS, drift detection | AWS lock-in, verbose templates |
| CDKTF | TypeScript/Python | Terraform backend | Yes | Adds real language to Terraform | Compilation to HCL, slowness |

### Terraform Best Practices
- Remote state with locking (S3 + DynamoDB, GCS, TFC)
- Module structure: root modules per environment, shared modules per resource type
- Workspaces for environment isolation (dev/staging/prod) or separate directory tree
- Use `prevent_destroy` for production databases and state buckets
- Pin provider and module versions; run `terraform plan` in CI/CD with human approval for prod
- Use HCP Terraform or Spacelift for team collaboration and policy enforcement

## Container Security

### Image Scanning

| Tool | Scans | Integrations | Coverage |
|------|-------|--------------|----------|
| Trivy | Images, FS, repos, SBOM | CI/CD, K8s operator | OS packages, language libs |
| Grype | Images, SBOM | CI/CD, Syft | OS + language packages |
| Snyk | Images, IaC, code | CI/CD, CLI, IDE | Full supply chain |
| Docker Scout | Images | Docker CLI, Hub | CVEs, provenance, attestation |

### Runtime Security (Falco)

```yaml
- rule: Shell in Container
  desc: Detect shell process spawn in container
  condition: container.id != host and proc.name in (bash, sh, zsh, dash)
  output: "Shell spawned in container (user=%user.name container=%container.id image=%container.image)"
  priority: WARNING
  tags: [container, shell]
```

### Runtime Security Patterns
1. **Falco**: Kernel-level syscall monitoring, rule engine, output to stdout/Slack/S3
2. **AppArmor / SELinux**: MAC profiles for containers (prevent capability abuse)
3. **Seccomp**: Restrict syscall profiles (default for containerd/Docker)
4. **Kube-bench**: CIS benchmark scanning for K8s configuration

### Admission Controllers

| Controller | Purpose | Enforcement |
|------------|---------|-------------|
| OPA / Gatekeeper | Policy as code (Rego) | Mutate + validate |
| Kyverno | Kubernetes-native policies | Mutate + validate + generate |
| Pod Security Admission | Built-in PSP replacement | PodSecurityStandard levels |
| Kritis / Binary Authorization | Image signing verification | Only signed images run |

## DevSecOps Gates

### Security Gate Placement

| Stage | Tools | What It Catches |
|-------|-------|-----------------|
| Commit | pre-commit, git-secrets, truffleHog | Secrets, credentials in code |
| Lint | semgrep, ESLint security plugin, bandit | Code-level vulnerabilities |
| SAST | Semgrep, CodeQL, SonarQube, Checkmarx | Injection, XSS, deserialization |
| DEP SCA | npm audit, pip-audit, OWASP DC, Trivy | Known vulnerable dependencies |
| Build | Hadolint, container scan | Misconfigurations, CVEs in base images |
| DAST | OWASP ZAP, Burp Suite, Nikto | Runtime (XSS, CSRF, SSRF) |
| Deploy | kubesec, kube-score, config audit | K8s misconfig, over-privileged pods |
| Runtime | Falco, WAF, RASP | Active threats, anomalous behavior |

### Gate Severity Mapping
- **SAST**: Critical/High = break, Medium = warn, Low = info
- **SCA**: Critical = break, High = break (or warn with SLA), fixed version available = break

## Secret Management

| Solution | Storage | Rotation | Audit | Platform |
|----------|---------|----------|-------|----------|
| HashiCorp Vault | Encrypted KV + backend | Dynamic secrets, TTL | Full audit log | Self-hosted, HCP |
| AWS Secrets Manager | KMS-encrypted | Automatic rotation | CloudTrail | AWS-native |
| GCP Secret Manager | CMEK-encrypted | Version-based | Cloud Audit Logs | GCP-native |
| Azure Key Vault | HSM-backed | Rotation policy | Azure Monitor | Azure-native |
| SOPS (encrypted files) | Git-tracked, KMS/Age | Manual re-encrypt | Git log | Any (GitOps) |
| External Secrets Operator | Pulls from cloud Vaults | Sync interval | K8s events | Kubernetes-native |

### Patterns
- **External Secrets Operator**: Sync cloud secrets to K8s Secrets automatically
- **SOPS + GitOps**: Encrypt secrets in Git, decrypt at apply time
- **Vault Sidecar**: Inject via Vault Agent sidecar (mutating webhook)
- **OIDC Workload Identity**: Use cloud IAM for provider auth, no static secrets

## Serverless Deployment

### Security Considerations
- **Least privilege IAM**: One role per function, scoped to specific resource ARNs
- **Secrets via environment**: Use cloud Secrets Manager / Parameter Store, never plaintext
- **VPC isolation**: Functions in private subnets for DB access, NAT for external traffic
- **Input validation**: All event sources (API Gateway, SQS, S3) can inject unsafe payloads
- **Cold start hardening**: Avoid loading unnecessary code/deps at init
- **Logging**: Never log secrets or PII, use structured JSON logs

## Monitoring and Alerting Stack

### Stack Components

| Layer | Tools | Purpose |
|-------|-------|---------|
| Metrics | Prometheus, Mimir, VictoriaMetrics | Time-series collection, long-term storage |
| Logs | Loki, Elasticsearch, CloudWatch, Datadog | Centralized log aggregation and search |
| Traces | Tempo, Jaeger, Honeycomb | Distributed tracing across services |
| Alerting | Alertmanager, Grafana On-Call, PagerDuty | Alert routing, grouping, silencing |
| Visualization | Grafana, Kibana, Datadog Dashboards | Dashboarding, ad-hoc queries |

### Alert Design Principles
- Every alert must have a runbook (link in alert annotation)
- Use severity levels: critical/page, warning/ticket, info/no-action
- Group related alerts (same service, same incident)
- Use `for:` duration to prevent flapping
- Silence known maintenance windows

### Prometheus Rules

```yaml
groups:
  - name: kubernetes
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate above 5% for 5 minutes"
          runbook: "https://runbooks.company.com/high-error-rate"
```

## Delegation Patterns

Delegates implementation to:
- `devops-specialist`: CI/CD pipelines, Dockerfiles, infrastructure code
- `container-security`: Falco rules, admission controllers, image scanning
- `devsecops-pipeline`: Security gate configuration, policy as code
- `serverless-security`: Lambda/Cloud Function hardening, least privilege IAM
- `kubernetes-specialist`: Pod security standards, service accounts, network policies
- `sre-specialist`: SLOs, SLIs, error budgets, runbooks
- `observability-specialist`: Prometheus rules, Grafana dashboards, Loki queries
