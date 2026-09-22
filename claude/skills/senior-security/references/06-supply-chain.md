# Supply Chain Security

> Scope: securing the path from source to running artifact — SBOM, SLSA, sigstore, dependency provenance, build hardening, and vendor risk.

## Threat model

| Stage | Threats | Primary controls |
|---|---|---|
| Source | Compromised developer account, malicious dependency, typo-squatting, self-merging PR | SSO with MFA, branch protection, required review, lockfiles, dependency review |
| Build | Poisoned CI, tampered steps, credential theft, cache poisoning | Ephemeral runners, OIDC, isolated builds, pinned actions, provenance |
| Artifact | Registry tampering, tag mutation, unsigned or downgraded image | Digests, signing, registry immutability, admission verification |
| Distribution | Mirror compromise, dependency confusion | Scoped registries, allowlisted indexes, signature verification |
| Deploy | Unauthorized artifact, policy bypass, secret exposure in pipeline | Admission policy, least-privilege deploy identity, secret managers |
| Runtime | Exploited vulnerable dependency, malicious package at runtime | Continuous scanning, rebuild cadence, runtime detection |

The goal is not zero vulnerabilities; it is that every deployed artifact traces to a reviewed source commit and a trusted build, and that you can answer impact questions in minutes.

## SBOM

Generate a software bill of materials per artifact at build time and store it with the artifact.

| Choice | Options | Notes |
|---|---|---|
| Format | SPDX, CycloneDX | Both are fine; pick one per org and be consistent; verify current spec versions upstream |
| Generation | syft, Trivy, cdxgen, buildkit plugins, CI-native | Must include transitive dependencies and versions |
| Storage | Registry attestation, artifact store, SBOM database | Keyed by image digest, not release name |
| Use | Vulnerability impact, license compliance, incident response, customer due diligence | An unused SBOM is compliance theater |

Quality checks: the SBOM should enumerate OS packages, language packages, and their versions, with package identifiers resolvable to advisories. Validate at build time; reject empty or truncated documents. Regenerate on every build — a rebuild with a new base or dependency produces a new SBOM.

VEX (Vulnerability Exploitability eXchange) lets you publish "not affected" determinations with reasoning so scanners, customers, and auditors stop re-reporting accepted findings. Publish VEX for every accepted risk with a rationale.

## SLSA and provenance

SLSA (Supply-chain Levels for Software Artifacts) is a vocabulary for build integrity. The current spec uses tracks and levels; verify the current structure upstream rather than memorizing old level numbers.

Progression that works in practice:

1. **Build definition in Git.** One versioned definition per artifact; the pipeline is code and reviewed.
2. **Provenance generated.** CI or a dedicated builder emits an in-toto-style attestation describing source, builder, and parameters; store it with the artifact.
3. **Hardened builds.** Ephemeral, isolated build environments; the build cannot forge its own provenance; signing keys are held outside the build step.
4. **Distribution integrity.** Artifacts and provenance are signed; consumers verify before deploy.

Implementation order:

- Digest-addressed artifacts and immutable registries so tags cannot be re-pointed.
- Provenance available and signed for every release.
- Verification in admission and, where feasible, at runtime.
- Reproducible builds where the ecosystem supports it; treat as an enhancement, not a prerequisite.

## Sigstore, cosign, and verification

- **Keyless signing**: the CI workload's OIDC identity is exchanged for a short-lived certificate (Fulcio), and the signature plus certificate are recorded in a transparency log (Rekor). No long-lived private key to steal.
- **Key-based signing**: use KMS-backed keys where keyless is not permitted; file-based keys with passphrases are the weakest option.
- Sign the digest, then attach SBOM and provenance as attestations to the same digest.
- Verification must bind identity. Checking a signature without checking who signed it is security theater.
- Store signatures and attestations as OCI artifacts in the registry so admission does not depend on outbound transparency-log access; mirror the log entries you rely on.
- Plan for key/certificate rotation and log availability; verification outages block deploys.

```bash
# Sign an image keyless in CI (uses the workflow OIDC identity)
cosign sign --yes ghcr.io/example/api@sha256:REPLACE_DIGEST

# Verify with identity binding
cosign verify ghcr.io/example/api@sha256:REPLACE_DIGEST \
  --certificate-identity "https://github.com/example/api/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"

# Attach an SBOM attestation
cosign attest --yes --predicate sbom.spdx.json --type spdxjson ghcr.io/example/api@sha256:REPLACE_DIGEST
```

Admission verification options: Kyverno `verifyImages`, Sigstore policy-controller, Ratify. Keep verification webhooks highly available and scope rules narrowly. See `./05-container-cloud-security.md`.

## Dependency provenance

| Ecosystem | Provenance mechanism (verify current status upstream) |
|---|---|
| npm | Registry provenance attestations from supported CI providers; lockfile integrity hashes |
| PyPI | Trusted Publishing with attestations for supported build backends |
| Go modules | `go.sum` checksums, module proxy and checksum database |
| Maven | Central publishing requirements and signature/checksum validation |
| Containers | cosign signatures and attestations per digest |

Practices:

- Commit lockfiles and enforce them in CI (`npm ci`, `pip install --require-hashes`, `cargo --locked`, `go mod verify`).
- Review dependency changes: a new transitive dependency is a new trust relationship. Use automated dependency review on PRs, not only post-merge scans.
- Block typosquats and dependency confusion: scope private packages under a reserved scope, use allowlisted registries, configure the package manager to prefer the private registry for your scopes, and check package names against existing ones.
- Prefer dependencies with maintainer diversity, active releases, and signed/provenance-attested publishes; a single-maintainer package with install scripts is elevated risk.
- Disable install scripts where possible (`npm ci --ignore-scripts`, no post-install network).
- Treat AI-generated or vendored code as third-party code: provenance, review, license, and vulnerability hygiene.

## Build hardening

| Control | Implementation |
|---|---|
| Ephemeral runners | Fresh, short-lived build environments per job; no shared persistent state |
| Cloud access | OIDC federation from CI to a narrowly scoped role; no stored cloud keys |
| Workflow permissions | Minimal token permissions per job; separate jobs for build, sign, and deploy |
| Pinned actions | Third-party CI actions pinned to commit SHAs, not floating tags |
| Isolated signing | Signing step runs after build with a key/identity the build cannot reach |
| Hermetic builds | Network-restricted during build where the ecosystem allows; vendor dependencies |
| Secret access | Build jobs get no production secrets; deploy jobs get no write access to source |
| Cache integrity | Key caches by content and treat cache poisoning as a build threat |
| Artifact promotion | Build once, promote the same digest across environments; never rebuild per environment |
| Logging | Build logs are immutable and retained; record source commit and artifact digest |

Caveat: "build once" conflicts with per-environment rebuilds for reproducibility in some ecosystems; resolve it explicitly — usually by building one artifact and injecting environment config at deploy.

## Vendor and third-party risk

- Maintain an inventory of vendors and open-source components with data access and criticality.
- Due diligence for critical vendors: security program, incident notification terms, subprocessor list, data residency, breach history, certification (SOC 2, ISO 27001) with report review, not just the logo.
- Contractual controls: breach notification window, right to audit, data deletion, SLA, and security requirements.
- Monitor vendor advisories and CVEs affecting components you use; map them to your inventory.
- Regulatory drivers to track: the EU Cyber Resilience Act (vulnerability and incident reporting obligations phase in from late 2026, full obligations later — verify dates upstream) and sector rules such as DORA for financial entities, which impose incident reporting clocks. These raise the bar for SBOM, CVD, and vendor notices.
- Open-source consumption is not free: budget for maintaining, patching, or replacing critical dependencies you cannot influence.

## Incident-ready supply chain

Prepare to answer these questions in minutes, not days:

- Which deployed artifacts contain component X at version Y?
- Which artifacts were built by a compromised builder or signed by a compromised identity?
- Which systems consume the affected artifact, and what is the rollback target?
- Can we revoke a signing identity and re-verify the fleet?

If answering requires an email thread, the supply chain program is incomplete.

## Anti-patterns

- Signing images but not binding identity in verification.
- SBOM generated at release and never regenerated; base image age untracked.
- Scanning only at build time with no rebuild-and-redeploy path.
- Deploying mutable tags while claiming digest immutability.
- One shared signing key for all repositories, stored as a CI secret.
- CI actions referenced by tag, not SHA.
- Private packages mixed into public scopes without registry pinning.
- Vendor risk assessed once at purchase and never revisited.
- Build jobs with production credentials "because it is easier".
- Assuming the package registry is trustworthy because it is popular.

## Checklist

- [ ] Build definitions in Git; runners ephemeral; CI to cloud via OIDC only.
- [ ] CI jobs have minimal permissions; third-party actions pinned to SHAs.
- [ ] Artifacts built once, digest-addressed, and promoted across environments.
- [ ] Provenance generated and signed for every artifact.
- [ ] Images and attestations signed (keyless or KMS); verification binds identity.
- [ ] Registry immutability enabled; admission verifies signatures and attestations.
- [ ] SBOM produced, validated, stored, and signed per digest; VEX for accepted risks.
- [ ] Lockfiles enforced; dependency review on PRs; install scripts disabled where possible.
- [ ] Continuous scanning of running artifacts; rebuild cadence defined and measured.
- [ ] Vendor inventory and due diligence for critical vendors; incident notification terms.
- [ ] Impact queries ("who ships component X") answerable from an SBOM-linked inventory.
