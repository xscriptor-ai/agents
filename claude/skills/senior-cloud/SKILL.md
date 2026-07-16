---
name: senior-cloud
description: Deep cloud patterns for Kubernetes, GitOps, service mesh, SRE, multi-cloud,
  serverless, and IaC
---

# Cloud

## Kubernetes

### Networking
- **CNI**: Calico (network policies), Cilium (eBPF, Hubble), Flannel (simple overlay).
- **Ingress**: ingress-nginx, Traefik, Contour, or Gateway API (v1.0+).
- **Service types**: ClusterIP (internal), NodePort (dev), LoadBalancer (cloud), ExternalName.

### Storage
- **CSI drivers**: EBS (AWS), Persistent Disk (GCP), Azure Disk, Rook/Ceph.
- **StorageClasses**: `gp3` (default on EKS), `pd-ssd` (GKE), `managed-csi` (AKS).
- **Volume modes**: Filesystem (RWX via NFS/EFS), Block (RWO/RWOP for DBs).

### RBAC
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { namespace: app, name: pod-reader }
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
kind: RoleBinding
subjects:
- kind: ServiceAccount, name: app-sa, namespace: app
roleRef: { kind: Role, name: pod-reader, apiGroup: rbac.authorization.k8s.io }
```

### Admission Controllers
- **Built-in**: `NamespaceLifecycle`, `LimitRanger`, `ResourceQuota`, `PodSecurity`.
- **Dynamic**: OPA/Gatekeeper (rego policies), Kyverno (Kubernetes-native policies), cert-manager.
- **Use Kyverno** for ease of use: `kyverno apply policy.yaml --cluster`.

## GitOps

### ArgoCD vs Flux

| Feature | ArgoCD | Flux |
|---------|--------|------|
| UI | Rich web UI | CLI + dashboard addon |
| Sync strategies | Manual, auto, prune | Reconciliation loop |
| Multi-cluster | Via ArgoCD ApplicationSets | Via Kustomization cross-cluster |
| SSO | Dex, Okta, OIDC | OIDC via CLI |
| Health checks | Built-in Lua scripts | Via kube-status |

- **ArgoCD**: Better for teams wanting a UI and manual approval gates.
- **Flux**: Better for fully automated, pull-based reconciliation.

## Service Mesh

| Feature | Istio | Linkerd | Cilium |
|---------|-------|---------|--------|
| Data plane | Envoy | Linkerd-proxy | eBPF (no sidecar option) |
| mTLS | Auto (SDS) | Auto | Auto (eBPF) |
| Traffic split | VirtualService/DestinationRule | SMI TrafficSplit | CiliumEnvoyConfig |
| Observability | Prometheus, Kiali, Grafana | Built-in metrics | Hubble |
| Complexity | High | Low | Medium |

- **Istio**: Full-featured, complex, best for large enterprises.
- **Linkerd**: Minimal resource overhead, simple, great for most teams.
- **Cilium**: Best for eBPF-native networking + security in one.

## SRE

### SLO / SLI / Error Budgets
```yaml
# Service Level Objective
sli:
  - metric: "http_request_duration_seconds"
    threshold: "< 200ms"
    window: "28d"
slo: 99.9%
error_budget: 0.1% of requests = ~43 minutes/month
policy: "Spend error budget at 50% before freezing deploys"
```

- **SLI metrics**: latency, error rate, throughput, saturation (USE method).
- **Burn rate alerts**: 1h, 6h, 3d windows for 2x, 10x, 100x burn.
- **Tools**: Prometheus + Alertmanager, Google Cloud Monitoring, Datadog SLO.

## Multi-Cloud Networking

- **Connectivity**: Cloud VPN (site-to-site), Direct Connect / ExpressRoute / Interconnect.
- **Mesh**: Aviatrix, Alkira for cloud-agnostic networking.
- **DNS**: Cloudflare DNS or Google Cloud DNS with multi-cloud failover.
- **Security**: Zero-trust gateways (Zscaler, Netskope), cloud WAF.

## Serverless Patterns

- **AWS Lambda + API Gateway + DynamoDB**: Classic microservice per function.
- **Event-driven**: S3 -> SQS -> Lambda -> DynamoDB.
- **Fan-out**: SNS -> SQS per consumer -> Lambda.
- **Warm starts**: Provisioned concurrency, keep-alive pings on EventBridge Scheduler.
- **Cold start mitigation**: SnapStart (Java/Python), custom runtime (Rust).

## Infrastructure as Code

### Terraform
```hcl
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "main"
  cidr   = "10.0.0.0/16"
  azs    = ["us-east-1a", "us-east-1b"]
}

terraform {
  backend "s3" {
    bucket = "tf-state"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "tf-locks"
  }
}
```

### Pulumi
```typescript
const vpc = new aws.ec2.Vpc("main", {
  cidrBlock: "10.0.0.0/16",
  tags: { Name: "main" },
});

const subnet = new aws.ec2.Subnet("subnet", {
  vpcId: vpc.id,
  cidrBlock: "10.0.1.0/24",
});
```

- **State management**: Remote state, locking (DynamoDB), encrypted.
- **Modules**: Reusable, versioned, published in registries.
- **Secrets**: Use `sensitive = true`, store in Vault / AWS Secrets Manager.
- **Policy as Code**: Sentinel (Terraform), CrossGuard (Pulumi), OPA.
