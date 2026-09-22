---
name: senior-systems
description: 'Cross-platform systems reference pack: shell scripting (bash/zsh, strict
  mode, traps, shellcheck, bats), Linux (systemd, cgroups v2, namespaces, journald,
  packages), macOS (launchd, Homebrew, SIP/Gatekeeper, MDM), Windows (PowerShell 7,
  winget, WSL2, Task Scheduler, AD), networking (DNS, TCP/TLS, nftables, tcpdump,
  VPN, proxies), storage (ext4/btrfs/ZFS, NVMe, RAID, LVM, backups), performance (perf,
  eBPF, iostat/vmstat, sysctl, OOM), containers (OCI, rootless, overlays, host debugging),
  and hardening (SSH, SELinux/AppArmor, auditd, CIS, patching). Use when scripting,
  debugging Linux/macOS/Windows hosts, diagnosing network or disk incidents, tuning
  performance, debugging containers from the host, or hardening servers. Optional
  pack: consumers degrade gracefully when it is absent.'
---

# Systems

Host-level systems work for senior engineers: writing scripts that survive production,
administering Linux, macOS, and Windows machines, and diagnosing networking, storage,
performance, container, and security problems at the operating-system layer. The pack
assumes hands-on access (shell, terminal, root or equivalent privilege) and favors
non-destructive, observable, reversible operations. It is deliberately opinionated where
the platform ecosystem has converged and marks where distributions and vendors differ.

## Domain Overview

- **Shells** — bash 5.x and zsh are interactive and automation staples; POSIX `sh` is the
  portability floor. Every non-trivial script passes `shellcheck` and is tested with bats
  where behavior matters. See [shell scripting](./references/01-shell-scripting.md).
- **Linux** — systemd is the init, service manager, timer, and cgroup manager on every
  mainstream distribution (RHEL 9/10, Ubuntu LTS, Debian 12/13, Fedora, Arch). Package
  managers vary; cgroups v2 is the unified hierarchy.
- **macOS** — Apple silicon, APFS, launchd, and SIP shape everything. Automation goes
  through launchd, Homebrew, `defaults`, and MDM configuration profiles, not cron.
- **Windows** — PowerShell 7 is the automation surface; winget for packages, WSL2 for
  Linux workloads, Task Scheduler and Windows services for persistence, Event Log for
  diagnostics, AD/Entra for identity.
- **Networking** — diagnose bottom-up: link, IP, routes, DNS, TCP, TLS, application.
  nftables is the modern Linux packet filter; WireGuard is the default tunnel.
- **Storage** — choose the filesystem for the workload (ext4/XFS/btrfs/ZFS), monitor
  capacity and inodes, and treat backups as unproven until restored.
- **Performance** — measure before tuning. `perf`, eBPF/bpftrace, and PSI answer different
  questions than `top`; sysctl changes are hypotheses, not defaults.
- **Containers** — containers are namespaces plus cgroups plus a root filesystem; host-side
  debugging skills transfer across Docker, Podman, containerd, and Kubernetes.
- **Security** — least privilege, patching, and an allow-by-default firewall are baseline;
  SELinux/AppArmor and auditd provide enforcement and evidence.

## Core Rules (non-negotiable)

1. **Read before you write.** Inspect current state (`lsblk`, `systemctl status`,
   `ss -tulpn`, `nft list ruleset`) before changing anything; capture it for rollback.
2. **Prefer reversible operations.** Snapshot, back up configs, or stage changes; every
   destructive action (`rm -rf`, `mkfs`, `dd`, `DROP`) gets an explicit confirmation path.
3. **Scripts use strict mode.** `set -euo pipefail` (plus `set -E` and a trap) in bash;
   POSIX `sh` scripts set `-eu` and handle `pipefail` where supported. Never rely on
   unquoted expansions.
4. **Everything is quoted and validated.** `"$var"`, `"$@"`, `--` before user paths,
   `mktemp` for temporaries, and input validated at the boundary.
5. **Least privilege.** Services run as dedicated non-root users; sudo rules are explicit;
   capabilities replace setuid where possible. Root is a tool, not a default.
6. **Services are declarative.** systemd units/timers on Linux, launchd jobs on macOS,
   Task Scheduler or services on Windows. cron is a fallback, not a design.
7. **The firewall denies by default.** Only required inbound ports are opened; rules are
   persisted and reviewed. Host firewall plus cloud security group both apply.
8. **Backups follow 3-2-1 and are tested.** Three copies, two media, one offsite; restore
   drills are scheduled, not aspirational.
9. **Measure before tuning.** No sysctl, scheduler, or filesystem change ships without a
   baseline and a post-change measurement; document every deviation from defaults.
10. **Logs and time are trustworthy.** Persistent journald, synchronized clocks (NTP),
    and centralized logs precede deep debugging; an unsynced clock breaks TLS and auth.
11. **Change one thing at a time.** Batch changes make causality unknowable; annotate
    changes with a reason and a timestamp in the change system.
12. **Assume compromise needs evidence.** auditd, file integrity monitoring, and patch
    tracking are baseline controls, not optional extras.

## Decision Tables

### Shell and script target

| Situation | Choice | Notes |
|---|---|---|
| Anything interactive or complex | bash | Arrays, `[[ ]]`, `mapfile`, `printf -v` |
| User's login shell on macOS | zsh | Preinstalled; bash 3.2 on macOS is ancient |
| Must run on Alpine/BusyBox/CI minimal | POSIX `sh` | `dash`/`ash`; no arrays, no `[[ ]]` |
| Windows-native automation | PowerShell 7 | Objects, not text; cross-platform |
| Complex portable logic | Rewrite in Python/Go | Shell past ~200 lines is a smell |

### Service and scheduling manager

| Platform | Manager | Use when |
|---|---|---|
| Linux | systemd unit | Long-running service, restart policy, sandboxing |
| Linux | systemd timer | Scheduled jobs with logs, dependencies, jitter |
| Linux (legacy) | cron | Simple periodic job; watch PATH and mail |
| macOS | launchd LaunchDaemon | System-wide root service or schedule |
| macOS | launchd LaunchAgent | Per-user service; runs when user session exists |
| Windows | Windows service | Background daemon with recovery policy |
| Windows | Task Scheduler | Scheduled or event-triggered jobs |

### Network diagnosis order

| Step | Question | Tool |
|---|---|---|
| 1 | Is the link up, IP valid? | `ip -br a`, `ethtool`, `ping` |
| 2 | Do routes and policy exist? | `ip r`, `ip rule`, `traceroute`/`mtr` |
| 3 | Does DNS resolve? | `dig +trace`, `resolvectl query` |
| 4 | Does the port answer? | `ss -tulpn`, `nc -vz`, `test-netconnection` |
| 5 | Does TLS validate? | `openssl s_client`, `curl -v` |
| 6 | Is the app responding? | `curl -w`, app logs, `tcpdump` |

### Filesystem selection

| Workload | Choice | Notes |
|---|---|---|
| General Linux server root | ext4 or XFS | ext4 broad, XFS large files/parallel IO |
| Snapshots and rollback | btrfs or ZFS | CoW costs; plan scrub and free space |
| Data integrity, compression, send/recv | ZFS | RAM-hungry; verify licensing for your use |
| Container image layer store | XFS (ftype=1) or ext4 | overlayfs needs d_type support |
| Boot partitions | ext4, FAT32 (EFI) | Keep simple; no CoW features |

### Container runtime

| Situation | Choice | Notes |
|---|---|---|
| Local dev, single node | Docker or Podman | Podman is daemonless/rootless by default |
| Rootless requirement | Podman or rootless Docker | Needs subuid/subgid; ports <1024 need sysctl |
| Kubernetes node internals | containerd + runc/crun | `ctr`, `crictl`, `nerdctl` for inspection |
| Host-level debugging | `nsenter`, `docker debug` | Prefer entering namespaces over privileged |
| Untrusted workloads | gVisor/Kata-class runtime | Stronger isolation, compatibility tradeoffs |

### Hardening priority

| Priority | Control | Why |
|---|---|---|
| 1 | Patch cadence and EOL tracking | Most incidents exploit known CVEs |
| 2 | SSH: keys only, no root login | Internet-exposed brute force is constant |
| 3 | Firewall default deny | Shrinks the attack surface immediately |
| 4 | Least privilege and sudo review | Blast radius of a compromised account |
| 5 | MAC (SELinux/AppArmor) enforcing | Contains exploit escalation |
| 6 | auditd and integrity monitoring | Detection and forensics |
| 7 | CIS-style baseline, deviation register | Repeatable, auditable configuration |

## Reference Index

Load only what the task needs. All paths are relative to this file.

| # | Reference | Scope | Load when |
|---|---|---|---|
| 01 | [references/01-shell-scripting.md](references/01-shell-scripting.md) | bash/zsh, POSIX portability, strict mode, quoting, arrays, traps, shellcheck, bats, footguns | Writing or reviewing any shell script, CI snippet, or installer |
| 02 | [references/02-linux-admin.md](references/02-linux-admin.md) | systemd units/timers, users and permissions, cgroups v2, namespaces, journald, packages, cron vs timers | Administering a Linux host, writing units, debugging services |
| 03 | [references/03-macos-admin.md](references/03-macos-admin.md) | launchd, Homebrew, SIP/Gatekeeper, `defaults`, MDM profiles, TCC, APFS quirks | Automating or debugging a Mac, fleet configuration, signing issues |
| 04 | [references/04-windows-admin.md](references/04-windows-admin.md) | PowerShell 7, winget, WSL2, Task Scheduler, services, Event Log, AD basics | Scripting Windows, managing WSL2, reading event logs, AD queries |
| 05 | [references/05-networking.md](references/05-networking.md) | DNS, TCP/TLS lifecycle, dig/curl/ss/tcpdump, nftables, tunnels/VPN, proxy debugging | Network incidents, firewall changes, TLS or proxy debugging |
| 06 | [references/06-storage-filesystems.md](references/06-storage-filesystems.md) | ext4/XFS/btrfs/ZFS, NVMe, RAID, LVM, backups 3-2-1, capacity and inode monitoring | Disk planning, filesystem selection, resize, backup design |
| 07 | [references/07-performance-tuning.md](references/07-performance-tuning.md) | perf, bpftrace/eBPF, iostat/vmstat/pidstat, PSI, ulimits, sysctl, memory pressure, OOM | Latency investigations, capacity work, tuning a saturated host |
| 08 | [references/08-containers-os.md](references/08-containers-os.md) | namespaces/cgroups, OCI runtime, rootless, overlays, networking, host-side debugging | Debugging containers, rootless setup, image/layer storage issues |
| 09 | [references/09-security-hardening.md](references/09-security-hardening.md) | SSH, SELinux/AppArmor, auditd, firewall defaults, CIS benchmarks, patching, least privilege | Hardening a server, security review, baseline and compliance work |

Cross-cutting: [Linux administration](./references/02-linux-admin.md) pairs with
[containers](./references/08-containers-os.md) and [security hardening](./references/09-security-hardening.md);
[performance](./references/07-performance-tuning.md) pairs with
[networking](./references/05-networking.md) and [storage](./references/06-storage-filesystems.md).

## Loading

- **Installed agent** — `skill({ name: "systems" })` in OpenCode; Claude Code reads
  `<skills-dir>/systems/SKILL.md`.
- **Orchestrator** — read this file, then inject only the references the task needs.
- **Not installed** — proceed with embedded guidance, state the degraded mode, and do not
  invent pack-only content.
- **Consumers** — reference this pack as `load skill senior-systems (optional)`.

## Port

- **Port id** — `skill://senior/systems` (version in `metadata.port-version`).
- **Kind** — read-only reference pack; no side effects, no tools required.
- **Entrypoint** — this `SKILL.md`; depth lives in `references/`.
- **Load modes**
  1. Installed agent: `skill({ name: "systems" })` in OpenCode; Claude Code reads `<skills-dir>/systems/SKILL.md`.
  2. Orchestrator: read `SKILL.md`, then load only the references the task needs.
  3. Not installed: consumers MUST degrade gracefully using their own guidance and report the degraded mode. Never block on the pack.
- **Consumer contract** — `metadata.consumers` lists the agents that may load it; consumers reference it as `load skill senior-systems (optional)`.
- **Stability** — `stable`; breaking changes bump `port-version` major.
