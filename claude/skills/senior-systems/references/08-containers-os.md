# Containers from the OS Layer

Understanding and debugging containers as operating-system constructs: namespaces, cgroups, OCI runtimes, rootless mode, overlay filesystems, and host-side debugging.

## What a Container Is

A container is a process (or process tree) with:

1. **Namespaces** restricting what it can see (PID, mount, network, UTS, IPC, user, cgroup, time).
2. **cgroups** limiting what it can consume (CPU, memory, pids, I/O).
3. **A root filesystem** assembled from image layers.
4. **Security policy** — capabilities, seccomp, LSMs (SELinux/AppArmor), and user mapping.

There is no container kernel. `runc`/`crun` are thin process launchers; containerd,
Docker, and Podman manage images, networks, and lifecycle on top. This is why
[host-side debugging](./07-performance-tuning.md) tools work directly on containers.

```bash
unshare --user --map-root-user --pid --fork --mount-proc bash   # the essence, no runtime
lsns -p <pid>
```

## Namespaces in Practice

| Namespace | Flag | What the container sees |
|---|---|---|
| pid | `CLONE_NEWPID` | Itself as PID 1; host PIDs hidden |
| mount | `CLONE_NEWNS` | Its own root and mounts |
| net | `CLONE_NEWNET` | Own interfaces, routes, ports, loopback |
| uts | `CLONE_NEWUTS` | Own hostname/domain |
| ipc | `CLONE_NEWIPC` | Own SysV/POSIX IPC objects |
| user | `CLONE_NEWUSER` | UID/GID mapping; rootless foundation |
| cgroup | `CLONE_NEWCGROUP` | Sees cgroup paths relative to itself |
| time | `CLONE_NEWTIME` | Clock offsets per process group |

```bash
# which namespaces does a container process use?
pid=$(docker inspect -f '{{.State.Pid}}' web)
ls -l /proc/$pid/ns/
nsenter -t "$pid" -a -- hostname
nsenter -t "$pid" -n -- ss -tulpn
nsenter -t "$pid" -m -- ls /
```

- Container network debugging: `nsenter -n` gives the container's routing table, iptables,
  and sockets from the host, without installing tools inside the image.
- File-descriptor tricks work across namespaces:
  `docker inspect`/`crictl inspect` → host PID → `/proc/<pid>/root/` and `/proc/<pid>/cwd/`.
- PID 1 semantics inside containers matter: it must reap zombies and forward signals.
  Use `--init` or a proper init if the app does not.
- Network namespaces are per-container; host `ss -tulpn` does not show container
  listeners (they live in their own netns or are DNAT'd by the runtime).

## cgroups v2 and Limits

```bash
docker run --memory=512m --memory-swap=512m --cpus=1.5 --pids-limit=256 nginx
podman run --memory=512m --cpus=1.5 --read-only --cap-drop=ALL nginx
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.max
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/cpu.stat
```

| Flag | cgroup file | Effect |
|---|---|---|
| `--memory` | `memory.max` | Hard cap; OOM-kill inside the cgroup |
| `--memory-reservation` | `memory.low` | Soft protection under pressure |
| `--cpus` | `cpu.max` | Bandwidth cap (`quota period`) |
| `--cpu-shares` | `cpu.weight` | Relative share, no hard cap |
| `--pids-limit` | `pids.max` | Fork-bomb containment |
| `--blkio-weight` | `io.weight` | Relative I/O share |
| `--device-read-bps` | `io.max` | Hard I/O ceiling |

- cgroups v2 is unified on current distros; `cpu.stat` exposes `nr_throttled` and
  `throttled_usec` — a throttled container looks slow while host CPU is idle.
- Memory: `memory.events` (`oom`, `oom_kill`, `high`) distinguishes limit kills from
  global OOM; `memory.current`/`memory.peak` show usage trends.
- JVM/Node/Go runtimes often need heap limits tuned to the cgroup limit; container-aware
  flags exist (`-XX:MaxRAMPercentage`, Node `--max-old-space-size`) — verify per runtime.
- `--memory-swap` equal to `--memory` disables swap for the container; otherwise the
  difference is the allowed swap.
- Kernel OOM inside a namespace still kills the largest task in the cgroup; identify it
  with `memory.oom.group` settings and logs.

## OCI Runtime and Runtimes

```bash
containerd --version; runc --version; crictl info
ctr -n k8s.io containers list
ctr -n k8s.io tasks list
crictl ps -a; crictl logs <id>; crictl inspect <id> | jq '.info.runtimeSpec'
runc list
```

| Component | Role |
|---|---|
| OCI image spec | Tarball layers plus a JSON config (entrypoint, env, ports) |
| OCI runtime spec | `config.json`: namespaces, mounts, capabilities, seccomp |
| `runc` | Reference runtime; creates namespaces and execs the process |
| `crun` | C alternative; lighter and faster startup |
| containerd | Image/layer store, snapshotters, shim lifecycle (Kubernetes CRI) |
| Docker Engine | Developer UX over containerd (or its own daemon paths) |
| Podman | Daemonless CLI; rootless-first; pods compatible with Kubernetes YAML |

- `runc spec` generates a `config.json`; runtimes are swappable and the
  `RuntimeClass` in Kubernetes can select `runsc` (gVisor) or Kata for stronger
  isolation.
- `crictl` talks to the CRI socket (Kubernetes nodes); `ctr` talks to containerd
  directly (`-n` namespace matters); `nerdctl` is a friendlier containerd CLI.
- Docker vs containerd: `docker ps` may not show CRI-managed containers and vice versa;
  use `crictl` on Kubernetes nodes and `docker` on developer hosts.
- Runtime hooks (`prestart`, `createRuntime`) modify container setup; they run as root
  and are a privilege-escalation surface. Audit hooks in multi-tenant clusters.
- The shim (`containerd-shim`) survives daemon restarts and holds the container's stdio
  and exit status; stuck shims are a real failure mode — inspect `ctr`/`crictl`, not
  just the orchestrator.

## Rootless Containers

```bash
cat /etc/subuid /etc/subgid                 # user:start:count ranges
podman info | grep -A5 rootless
podman run --rm -p 8080:80 nginx            # >=1024 ports work by default
sysctl net.ipv4.ip_unprivileged_port_start  # lower to allow <1024 in rootless netns
podman system migrate                        # refresh mappings after subuid changes
```

| Requirement | Detail |
|---|---|
| subuid/subgid | `/etc/subuid`, `/etc/subgid` (or useradd defaults) must grant ranges |
| newuidmap/newgidmap | Setuid helpers from `uidmap` package map ranges |
| User namespaces | `kernel.unprivileged_userns_clone=1` where distros gate it |
| Storage driver | `overlayfs` native where possible; `fuse-overlayfs` fallback |
| Networking | rootlesskit + slirp4netns (userspace) or pasta; slower than veth |
| cgroup delegation | systemd lingers + `Delegate=yes` for limits in user slices |
| Ports | <1024 needs `ip_unprivileged_port_start` or `CAP_NET_BIND_SERVICE` |

- Rootless pods/containers run mapped to subordinate UIDs; a container root escape lands
  as an unprivileged host UID. This is the main security benefit, not a full sandbox.
- `podman generate systemd` is deprecated in favor of Quadlet (`.container` files under
  `/etc/containers/systemd/`); verify the current supported approach upstream.
- Rootless storage can exhaust `~/.local/share/containers`; monitor it like any disk.
- `podman unshare` starts a shell in the user namespace to inspect/manage mapped files.
- Rootless limitations: no host networking by default, no arbitrary netfilter rules,
  different performance profile. Test before standardizing.

## Overlay Filesystems and Layers

```bash
docker info | grep -i storage
cat /proc/mounts | grep overlay
mount | grep overlay
du -sh /var/lib/docker/overlay2 /var/lib/containers/storage
docker system df; docker image prune -a; docker builder prune
```

- overlayfs unions a read-only `lowerdir` stack with a writable `upperdir`; the first
  write to a file triggers **copy-up** (whole file copied), which can be expensive for
  large files.
- The backing filesystem must support `d_type` (XFS with `ftype=1`, ext4). Overlay on
  top of network filesystems (NFS) or btrfs subvolumes is unsupported or problematic.
- Layer size is not additive: shared base layers are stored once. Tooling that sums
  image sizes overstates disk use.
- Deleted files leave whiteouts; frequent rebuilds accumulate layers. Prune images,
  build caches, and volumes on a schedule, and monitor the state directory.
- Inode exhaustion is a common container-host failure when many small files and layers
  exist; `df -i` on the state filesystem is mandatory.
- Use volumes or bind mounts for data; writes to the container layer are ephemeral,
  slower, and bloat the image store.
- Rootless storage may use `fuse-overlayfs`, which is slower and has different
  semantics; verify with `podman info`.

## Networking (runtime view)

```bash
docker network inspect bridge
iptables -t nat -L DOCKER -n --line-numbers   # legacy docker NAT chain
podman network inspect podman
crictl inspectp <pod-id> | jq '.info.runtimeSpec.linux.namespaces'
```

- Default bridge networks use NAT and a local DNS resolver; container names resolve
  only on user-defined networks (Docker), not the default bridge.
- Port publishing (`-p 8080:80`) is DNAT in the host netns; conflicts show as
  `address already in use` on the host `ss`, not inside the container.
- CNI/CNI-like plugins (Calico, Cilium) program host routing and eBPF datapaths;
  container connectivity problems can be host routing problems.
- `network_mode: host` bypasses isolation; convenient and dangerous — no port mapping,
  shares the host's DNS and firewall state.
- MTU mismatches between overlay networks and the underlay cause large-packet hangs;
  check `ip link` inside the container and the CNI config.
- DNS inside containers: `/etc/resolv.conf` is generated per network; with systemd-
  resolved on the host, watch for the `127.0.0.53` stub being unreachable from the
  container's netns.

## Debugging Containers from the Host

| Question | Command |
|---|---|
| Host PID of container process? | `docker inspect -f '{{.State.Pid}}' c` / `crictl inspect c` |
| What is it doing? | `nsenter -t PID -a -- ps auxf`, `top -p PID` |
| Network state? | `nsenter -t PID -n -- ss -tulpn`, `ip addr`, `ip route` |
| Filesystem view? | `ls /proc/PID/root`, `nsenter -t PID -m -- ls /` |
| Syscalls? | `strace -f -p PID -tt -T` (briefly; may be blocked by seccomp) |
| Kernel stack / D state? | `cat /proc/PID/stack`, `cat /proc/PID/wchan` |
| CPU/memory inside cgroup? | `cat /sys/fs/cgroup/.../cpu.stat`, `memory.current` |
| Distroless image (no shell)? | `docker debug`, `kubectl debug --target`, ephemeral containers |
| Exit code / OOM? | `docker inspect .State`, `crictl inspect`, cgroup `memory.events` |

```bash
# ephemeral debug container sharing the target's namespaces (Kubernetes)
kubectl debug -it pod/web --image=nicolaka/netshoot --target=web
# Docker Desktop / CLI debug tool with a toolbox image
docker debug web
```

- `nsenter -a` covers all namespaces but uses the host filesystem view for binaries;
  `-m` alone enters the mount namespace for container filesystem inspection.
- Prefer ephemeral/debug containers over `--privileged`; `--privileged` disables the
  very isolation you are debugging and hides capability-related failures.
- Seccomp/AppArmor denials surface as `EPERM`/`Operation not permitted`; check
  `dmesg`/audit logs on the host, and inspect the profile in
  `docker inspect`/`crictl inspect`.
- A container in D state is usually blocked on I/O (disk, NFS, overlay merge); inspect
  `/proc/PID/stack` and the host's `iostat`.
- Reproduce with the same image digest and runtime; "works locally" often means
  different architecture (arm64 vs amd64) or image.

## Images: Minimal and Reproducible

- Pin base images by digest for reproducibility; tag-only references are mutable.
- Distroless or `scratch` images shrink attack surface but remove shells — plan
  debugging via ephemeral containers.
- Multi-stage builds keep build toolchains out of runtime images; verify no secrets or
  source leaks in layers (`docker history`, `crane export`, or a scanner).
- Set `USER` non-root, drop capabilities, use `--read-only` with tmpfs where possible,
  and declare `HEALTHCHECK`/probes.
- `HEALTHCHECK`/liveness semantics differ between Docker and Kubernetes; do not copy
  one to the other without thought.
- Image scanning (Trivy, Grype, major registries) is necessary but not sufficient;
  rebuild to pick up base-image fixes.

## Anti-Patterns

- Running `--privileged` to make a container start.
- Debugging by rebuilding the image with `apt install`/`apk add` instead of using
  ephemeral tooling.
- Mounting the Docker socket into containers; it is root-equivalent on the host.
- Storing databases in the container writable layer.
- Assuming `docker ps` shows everything on a Kubernetes node.
- Sizing memory limits without runtime awareness (JVM/Node heaps).
- Using `latest` tags in production or relying on mutable base images.
- Treating a container as a security boundary for untrusted code without a sandboxed
  runtime (gVisor/Kata).
- Ignoring inode usage on the container state filesystem.
- Leaving orphaned volumes, images, and networks accumulating for years.

## Checklist

- [ ] Runtime and version inventory known (Docker/containerd/Podman, runc/crun).
- [ ] Resource limits set for CPU, memory, and pids on every workload.
- [ ] Runtimes container-aware or heaps explicitly sized to limits.
- [ ] Rootless evaluated where threat model or policy requires it; subuid/subgid set.
- [ ] State filesystem monitored for space AND inodes; prune schedule defined.
- [ ] Host-side debugging path documented (nsenter, ephemeral containers).
- [ ] Security posture: non-root user, dropped capabilities, seccomp/AppArmor,
      read-only rootfs where possible.
- [ ] Images pinned by digest, minimal, scanned, and rebuilt regularly.
- [ ] Networking mode and DNS behavior understood for each workload.
- [ ] Kubernetes nodes managed via `crictl`, developer hosts via Docker/Podman; not
      conflated.

Related: [Linux administration](./02-linux-admin.md) for cgroup and systemd context,
[security hardening](./09-security-hardening.md) for LSM profiles and least privilege.
