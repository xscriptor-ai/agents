# Infrastructure as Code

> Scope: tooling choices, module design, state management, policy enforcement, and testing for provisioning cloud infrastructure.

## Tool selection

| Tool | Language | State model | Best for | Tradeoffs |
|---|---|---|---|---|
| OpenTofu | HCL | State file (self-managed backends) | Teams wanting the Terraform workflow under a permissive license | Smaller provider ecosystem nuance; verify provider compatibility upstream |
| Terraform | HCL | State file (self-managed backends) | Largest registry, managed Cloud/Enterprise features | Business Source License; verify terms before standardizing |
| Pulumi | TS/Python/Go/C#/Java | Managed or self-managed backends | App teams owning infra in general-purpose languages; rich testing | Smaller module ecosystem; language runtime adds dependencies |
| Crossplane | Kubernetes CRDs + YAML | Kubernetes etcd (no state file) | In-cluster self-service, platform APIs, drift reconciliation | Control plane is Kubernetes; providers lag cloud APIs |
| Cloud-native (CloudFormation, Bicep, Deployment Manager) | JSON/YAML/DSL | Service-managed | Single-cloud shops with compliance constraints | Weak multi-cloud story; limited abstraction |
| Ansible | YAML | Stateless (imperative) | Configuration of existing hosts and network devices | Not a provisioning or drift tool |

Decision guidance:

- OpenTofu is the default for new HCL projects unless a dependency requires Terraform-specific features or registry content. The two are command-compatible for the core workflow; divergence grows over time, so pick one per repository.
- Choose Pulumi when infrastructure code is written by application teams and unit testing, code review, and reuse matter more than registry breadth.
- Choose Crossplane when the platform's product is a Kubernetes API that application teams consume, and you want reconciliation and self-service without pipelines.
- Never mix tools for the same resource. Overlapping ownership causes state fights and destructive applies.

## Module design

A module is a product with an interface:

- **Inputs**: required variables minimal and explicit; validate with `validation` blocks. Prefer structured objects over long flat variable lists.
- **Outputs**: expose only what consumers need; every output is API surface you must keep stable.
- **Versioning**: publish to a registry or tag in Git with semantic versions; consumers pin (`version = "~> 3.0"`). Unpinned module sources are a supply-chain and stability risk.
- **Ownership boundary**: a module provisions a coherent unit (network, database, service). A module that provisions a whole environment becomes unmaintainable.
- **No provider configuration inside modules**: modules declare `required_providers`; the root configures providers and passes aliases. Provider blocks in modules prevent aliasing and multi-region composition.
- **No remote state reads across environments** as the default integration path; pass values as inputs or use explicit data sources sparingly. Cross-state coupling is the hardest thing to untangle.
- **Conditionals**: avoid `count`/`for_each` on whole modules to toggle behavior. Instead expose two smaller modules or use `for_each` over maps for genuine repetition. `for_each` beats `count` because addresses stay stable when items are removed from the middle.
- Document each module with a README (purpose, inputs, outputs, examples) generated from the code where possible.

```hcl
terraform {
  required_version = ">= 1.7" # OpenTofu floors differ; verify upstream
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket       = "org-tfstate-prod"
    key          = "network/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true # modern locking; DynamoDB locking is the legacy pattern
  }
}

module "network" {
  source  = "git::https://github.com/example/tf-modules.git//network?ref=v3.2.0"
  cidr    = "10.20.0.0/16"
  azs     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  tags    = local.tags
}
```

## State management

- One state per environment and per lifecycle boundary (network, data, apps). Many small states reduce blast radius and apply time; one giant state makes every change risky.
- Remote backends with encryption and locking are mandatory: object storage plus lockfile/DynamoDB-style locking, or the vendor's managed backend. Never commit state; it contains secrets and destroys your ability to plan safely.
- Access control: state read access equals secret read access. Restrict the state bucket to the pipeline identity and a small break-glass role.
- Workspaces vs directories: directories per environment are easier to reason about, review, and grant access to. CLI workspaces are acceptable for ephemeral parallel copies, not for prod/dev separation.
- Drift: run scheduled `plan` in CI and alert on unexpected diffs. Console/CLI changes are incidents; import them deliberately or revert them.
- Imports and moves: use `import` blocks and `moved` blocks so refactors are reviewable and don't destroy/recreate resources. Never hand-edit state except in a documented emergency, with a backup first.
- Deletion protection: enable provider-level deletion protection on databases and buckets, and use `prevent_destroy` for crown jewels.

## Secrets and sensitive data

- Infrastructure code frequently needs secrets: database passwords, API keys, TLS material. Never put them in variables committed to Git or in state in plaintext.
- Generate secrets inside the provider/managed service where possible (RNG resources, managed secret versions), or fetch at apply time from Vault/Cloud Secret Manager via data sources.
- Mark variables and outputs `sensitive`; this masks CLI output but does not encrypt state. State encryption (supported natively in newer OpenTofu releases; verify upstream) or a backend with encryption at rest is still required.
- Use workload identity federation from CI to cloud (OIDC) instead of long-lived cloud keys in CI secrets. This removes the most valuable credential from your CI system.
- Rotate anything that ever appeared in a plan log, state file, or CI artifact.

## Policy as code

| Layer | Tools | Enforces |
|---|---|---|
| Static pre-plan | Checkov, Trivy config, tflint, cdk-nag | Misconfigurations in source before apply |
| Plan-time | OPA/Conftest, Sentinel (Terraform Cloud/Enterprise), Pulumi policies | Rules on planned changes and diffs |
| Post-apply | Cloud native config rules, Config/Guard, Security Command Center | Drift and runtime configuration |
| Admission | Kyverno/Gatekeeper in Kubernetes | Workload-level policy for in-cluster resources |

Practices:

- Every rule starts in warn/report mode, then becomes blocking after a cleanup window.
- Policies have owners and expiry for exceptions; an exception without an expiry becomes permanent.
- Test policies like code: fixtures that must pass and fixtures that must fail.
- Keep the policy set small and high-signal (tagging, public access, encryption, approved regions, approved instance classes). A wall of 300 rules gets bypassed wholesale.
- Policy must run where the decision is made: PR checks for developer feedback, CI on `plan` as the authoritative gate, admission for cluster resources.

## Testing IaC

- **Unit/static**: `validate`, `fmt -check`, `tflint`, provider linting in pre-commit; fast and catches most syntax and style issues.
- **Native testing**: Terraform's test framework and OpenTofu's `test` command run plan/apply assertions against ephemeral resources. Prefer this for module contract tests; it is the lowest-friction path to real assertions.
- **Integration**: Terratest or a language-native test runner to apply a module in a sandbox account and assert behavior; always destroy afterwards.
- **Ephemeral environments**: per-PR stacks in a dedicated account/subscription/project with a TTL and a reaper. This is the only reliable way to test networking and IAM end to end.
- **Migration tests**: when refactoring, run plan against a copy of production state and require a no-op or expected diff before merging.

```hcl
# tests/network.tftest.hcl (native framework, sketch)
variables { cidr = "10.99.0.0/16" }

run "creates_three_subnets" {
  command = plan
  assert {
    condition     = length(module.network.subnet_ids) == 3
    error_message = "expected one subnet per AZ"
  }
}
```

## CI/CD for IaC

1. PR: format, validate, lint, policy, `plan` against the target environment; post the plan as a comment.
2. Human review focuses on the plan diff, not the HCL.
3. Merge to main: apply with a lock, using OIDC-federated short-lived credentials.
4. Prod applies require environment protection/approval; concurrent applies to the same state are serialized.
5. Nightly: drift detection `plan`; report and triage.
6. Keep apply output archived with the commit SHA so incidents can be correlated with changes.

## Migration notes

- **Terraform <-> OpenTofu**: the core workflow is command-compatible for typical configurations. Before switching, verify provider versions used by your modules are available in the target registry and test `plan` against a copy of state. State file formats are compatible in practice, but do not round-trip a state file between tools repeatedly; pick one as the writer.
- **Tool replacement (any direction)**: never import everything at once. Pick one low-risk stack, migrate it with `import` blocks plus a plan that shows no destructive changes, run it in parallel ownership-free for a release, then cut over and delete the old state. Repeat.
- **Module refactors**: use `moved` blocks in the same commit as the resource rename so reviewers see intent; a plan that shows destroy/create on a database is a stop sign.
- **CloudFormation/Bicep to HCL**: export existing resources, then rewrite rather than mechanically converting. Templates encode provider-specific semantics; a mechanical translation tends to reproduce those semantics in awkward HCL.

## Anti-patterns

- A single monolithic state shared by all environments.
- `terraform apply` from laptops with personal admin credentials; no audit trail.
- Manual console changes followed by "we'll import it later" (never happens).
- `-auto-approve` in production without a plan review.
- Modules that embed provider configs, remote state reads, or environment names.
- Secrets passed as plain variables and printed in CI logs.
- `count` on lists of resources, causing asymmetric destroy/recreate.
- 300 policy rules in warn mode forever.
- Applying IaC in CI without state locking.

## Checklist

- [ ] One tool per resource; ownership boundaries documented.
- [ ] Remote state with encryption and locking; access restricted.
- [ ] One state per environment/lifecycle; no cross-state reads without justification.
- [ ] Modules versioned, pinned, documented, and provider-agnostic.
- [ ] `moved`/`import` blocks used for refactors; deletion protection on crown jewels.
- [ ] OIDC federation for CI credentials; no long-lived cloud keys.
- [ ] Policy checks at pre-plan, plan, and admission layers with expiring exceptions.
- [ ] Native unit tests plus at least one integration test per critical module.
- [ ] Nightly drift detection with triage owner.
- [ ] Plan review is the required approval artifact for production changes.
