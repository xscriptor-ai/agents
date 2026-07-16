---
name: senior-deployment
description: Deployment patterns — Docker multi-stage builds, CI/CD pipeline design,
  blue-green/canary/rolling deployments, IaC patterns, secret management
---

# Deployment

## Docker Multi-Stage Builds

```dockerfile
# Stage 1: Build
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /app/server

# Stage 2: Runtime
FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /app/server /server
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/server"]
```

### Best Practices

- Use distroless or scratch for minimal attack surface.
- Pin base image digests, not tags.
- Use `.dockerignore` to exclude dev dependencies.
- Scan images with trivy or grype in CI.

## CI/CD Pipeline Design

| Stage | Actions | Gateway |
|-------|---------|---------|
| Pre-commit | Lint, format, type-check | Pass/fail |
| Build | Compile, unit test, security scan | Pass/fail |
| Integration | Integration tests via Docker Compose | Pass/fail |
| Deploy: Staging | Blue-green deploy, smoke tests | Automatic |
| Deploy: Production | Canary (5%) -> 50% -> 100% | Manual approval + auto gates |
| Post-deploy | Health check, rollback on failure | Automatic rollback |

## Deployment Strategies

| Strategy | Description | Risk | Rollback Time |
|----------|-------------|------|---------------|
| Rolling | Replace instances incrementally | Low | Fast |
| Blue-Green | Two full environments, switch traffic | Low | Instant |
| Canary | Percentage-based traffic shift | Very low | Instant |
| Recreate | Kill all, start all | High | Slow |
| A/B Testing | Route by user segment | Low | Instant |

### Recommendation

- Staging: Blue-Green for zero-downtime verification.
- Production: Canary with gradual traffic increase and automated rollback.

## Infrastructure as Code

| Tool | Language | State Mgmt | Best For |
|------|----------|------------|----------|
| Terraform | HCL | Remote state + locking | Multi-cloud |
| Pulumi | TypeScript/Python/Go | Managed or self-hosted | Teams preferring code |
| CloudFormation | YAML/JSON | AWS-managed | AWS-only |
| Crossplane | Kubernetes CRDs | Kubernetes-native | In-cluster provisioning |
| CDK | TypeScript/Python/etc | CloudFormation backend | AWS + familiar languages |

### IaC Principles

- Stores state in remote backend with locking (S3+DynamoDB, Terraform Cloud).
- PR-driven workflow: plan in PR, apply on merge.
- Use modules for reusable infrastructure patterns.
- Enforce tagging and compliance policies in code.
- Never manually modify resources created by IaC.

## Secret Management

| Stage | Solution | Rotation |
|-------|----------|----------|
| Local | .env + direnv + sops | Manual |
| CI | CI provider secrets / OIDC | Per-run |
| Staging | HashiCorp Vault | Automatic |
| Production | Vault + KMS + IAM roles | Automatic |

## Environment Management

- Immutable environments — never SSH into production.
- Use feature flags (LaunchDarkly, Unleash) over long-lived branches.
- Environment parity: same deployment method for staging and production.
- Database schema migrations run before application deployments.

## Monitoring Setup

| Layer | Metric | Tool |
|-------|--------|------|
| Application | Error rate, latency, throughput | Prometheus + custom metrics |
| Infrastructure | CPU, memory, disk, network | Node exporter + Grafana |
| Database | Query time, connections, replication lag | PG exporter, CloudWatch |
| Business | Sign-ups, orders, revenue | Custom business metrics |
| Uptime | Endpoint health checks | Pingdom, StatusCake |
