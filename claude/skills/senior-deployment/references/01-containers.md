# Containers

Scope: image build strategy (multi-stage, base image selection, caching), image hygiene and runtime behavior, buildpacks, multi-arch publishing, and supply-chain scanning and attestation.

## Build Model

| Approach | Use when | Trade-offs |
|---|---|---|
| Multi-stage Dockerfile | You need control over layers, tools, and filesystem contents | You own base-image patching and build logic |
| Buildpacks | A standard runtime is sufficient and you want fewer hand-written Dockerfiles | Less control over exact layers; builder updates are a dependency |
| Monolithic Dockerfile | Prototypes only | Huge images, leaked build tools, slow rebuilds |
| VM image build | Non-container targets | Out of scope for this reference; same principles on immutability and provenance |

The deliverable of the build is an immutable image identified by digest. Every deploy references the digest, never a floating tag. Tags (`latest`, branch names, short SHAs) are discovery aids, not identity.

## Multi-Stage Builds

The pattern: one stage builds, a second stage carries only the runtime artifact.

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-bookworm AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

FROM deps AS build
COPY . .
RUN npm run build && npm prune --omit=dev

FROM gcr.io/distroless/nodejs22-debian12 AS runtime
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER 65532:65532
CMD ["dist/server.js"]
```

Rules that make this work:

- Pin the builder and runtime to the same language version line; mismatched builder/runtime is a class of production-only bugs.
- Copy dependency manifests first, install, then copy source. This is what makes layer caching effective.
- Prune development dependencies in the build stage; never install build tooling in the runtime stage.
- Copy artifacts explicitly (`COPY --from=build`) — never `COPY . .` into the runtime stage.
- Set `WORKDIR`, `USER`, and the entrypoint explicitly. The runtime image should be boring and declarative.
- Use `--mount=type=cache` for package-manager caches. Cache mounts speed rebuilds without adding layers.

## Base Image Selection

| Base | Size / attack surface | Use when | Watch out |
|---|---|---|---|
| `scratch` | Minimal | Static binaries (Go, Rust) | No shell, no CA certs, no tzdata unless copied |
| Distroless | Small | JVM, Node, Python, Go runtimes | Debugging requires an ephemeral debug container |
| Alpine | Small | You need a shell and package manager | musl vs glibc differences; native modules must build for musl |
| `slim` Debian/Ubuntu | Medium | Native dependencies that assume glibc | More packages to patch; keep image updated |
| Full distro | Large | Legacy workloads only | Treat size and CVE count as debt |

- Pin to a digest for reproducible builds and depend on an automated updater (for example Renovate or Dependabot) to move the digest. Human-managed digest pins rot silently.
- Prefer a distroless or scratch runtime for network services; the absence of a shell removes a whole class of post-exploitation behavior.
- If you need `curl` for a health check or debugging, you picked the wrong health-check mechanism, not the wrong base. See `./07-observability-rollback.md`.
- Multi-stage and minimal bases do not remove the need to patch: rebuild regularly even when your code did not change.

## Layer Caching

Layer cache is the difference between a one-minute and a twenty-minute pipeline.

- Order instructions from least to most frequently changing.
- Use `.dockerignore` aggressively: `.git`, `node_modules`, virtualenvs, build output, test fixtures, local env files. A leaked `.env` in the build context is a secret incident.
- Prefer `COPY` of exact files over globs when the glob is unstable.
- Use `RUN --mount=type=cache` rather than committing package caches into layers.
- Use `--mount=type=bind` for files needed only during a `RUN` step, not in the final layer.
- Cache invalidation is transitive: any change to an earlier layer invalidates all later ones. Put lockfiles before source.
- In CI, share cache between runs with registry-backed or provider-native layer caching. See `./02-ci.md`.
- Verify cache effectiveness with `--progress=plain` and build logs; a cache that never hits is worse than no cache because it hides the cost in upload time.

## Image Hygiene

| Check | Rule |
|---|---|
| User | Run as a non-root numeric UID; set `USER` in the Dockerfile and enforce via admission policy |
| Filesystem | Read-only root filesystem where possible; mount only needed writable volumes |
| Capabilities | Drop all, add back only what is required |
| Secrets | None in any layer, including deleted files (they persist in earlier layers) |
| Signals | Use exec-form `ENTRYPOINT`; ensure PID 1 handles SIGTERM for graceful shutdown |
| Labels | `org.opencontainers.image.source`, `revision`, `version`, `created` for provenance |
| Ports | Declare `EXPOSE` for documentation, but bind explicitly at runtime |
| Health | No `HEALTHCHECK` curl hacks in minimal images; orchestration probes own health |
| Time | Copy CA certificates and tzdata when TLS or local time matters |

- Never pass secrets as `ARG` or `ENV`; build args are visible in image history.
- Squashing layers hides history but does not remove leaked content from a shared registry — treat any leaked secret as compromised and rotate it.
- Keep images single-purpose. A container that runs an init system, a cron daemon, and the app is three failure modes.

## Buildpacks

Buildpacks detect the language, build the app, and produce an OCI image without a Dockerfile. Choose them when:

- The runtime is standard and the team should not hand-maintain base images.
- You want automatic rebasing onto patched runtimes without rebuilding application layers.
- You need consistent images across many services with a platform team owning the builder.

Watch:

- The builder image is a supply-chain dependency: pin and update it deliberately.
- Build-time configuration is environment-variable driven; document and validate it.
- Custom system dependencies may still require a Dockerfile-based escape hatch.
- Verify what the buildpack injects by inspecting the final image; trust but verify.

## Multi-Architecture

- Build for the architectures you deploy (`linux/amd64`, `linux/arm64`); do not publish what you cannot test.
- Native builders are faster and more reliable than QEMU emulation for cross-arch builds; use them when the CI provider offers them.
- For compiled languages, cross-compilation in a single builder is usually faster than emulation. Set the target platform explicitly.
- Publish multi-arch as an image index/manifest list with `docker buildx imagetools` or equivalent; consumers pull by digest. The digest of the index differs from the digest of each platform image — know which one your deploy pins.
- Test the arm64 variant at least once per release; most multi-arch failures are architecture-specific native dependencies.

## Scanning, SBOM, and Provenance

Supply-chain artifacts are part of the deliverable, not a reporting afterthought.

- Generate an SBOM at build time (SPDX or CycloneDX) and attach it to the image or store it alongside the digest.
- Scan the image, not just the source: base-image and OS-package CVEs dominate findings.
- Gate CI on severity policy with documented exceptions and expiry dates; a gate that is always bypassed is worse than no gate.
- Sign images and attestations with a keyless signature bound to the pipeline identity (for example cosign with OIDC), and verify signatures in admission control.
- Record build provenance (builder identity, source commit, build parameters) in an attestation. Consumers verify before deploy.
- Re-scan registry contents continuously, not only at build time; new CVEs appear for old images.
- Keep a policy for how fast critical images are rebuilt and redeployed. An unredeployed patch is not a fix.

## Reproducibility

- Pin toolchain and dependency versions; floating package ranges make byte-identical rebuilds impossible.
- Set deterministic build metadata where the ecosystem supports it; avoid embedding timestamps and hostnames in artifacts.
- Reproducible builds are a goal, not a precondition; the practical minimum is "same source + same lockfile + same builder version produces functionally equivalent artifacts".
- Keep the build definition in the repository next to the code it builds.

## Anti-Patterns

- `latest` in any deployment manifest, Helm values file, or compose file.
- Installing build tools in the runtime image "just in case".
- Mounting the Docker socket into CI containers; it is root on the host.
- Baking environment-specific config or secrets into images.
- Rebuilding per environment, producing different artifacts under the same version.
- Ignoring base-image updates until a CVE forces an emergency rebuild.
- Running as root because the app "needs" it; fix permissions at build time.
- Huge build contexts because `.dockerignore` was never written.
- Scanning only the application dependencies and calling the image "clean".
- Trusting tags in production admission; verify digests and signatures.

## Checklist

- [ ] Multi-stage build; runtime stage contains only the artifact and its runtime.
- [ ] Dependency install separated from source copy; cache mounts used.
- [ ] `.dockerignore` excludes VCS data, local state, and secrets.
- [ ] Base pinned by digest; automated update path exists.
- [ ] Non-root `USER`, exec-form entrypoint, SIGTERM handled.
- [ ] No secrets, no build toolchain, no package-manager caches in the final image.
- [ ] OCI labels for source, revision, and version present.
- [ ] Multi-arch index published and the deployed variant tested.
- [ ] SBOM generated and attached; scan gate enforced with exception expiry.
- [ ] Image signed; provenance attested; admission verifies.
- [ ] Deploy manifests reference digests, not tags.
