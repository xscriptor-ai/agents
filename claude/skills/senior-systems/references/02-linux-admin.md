# Linux Administration

Administering mainstream Linux hosts: systemd services and timers, users and permissions, cgroups v2, namespaces, journald, packages, and scheduling.

## Platform Landscape (2026)

| Family | Current stable lines | Notes |
|---|---|---|
| RHEL / Rocky / Alma | RHEL 9 and 10 lines | 10-year lifecycles; SELinux enforcing; `dnf` |
| Fedora | Rolling yearly releases | Newest systemd/kernel; upstream validation |
| Ubuntu LTS | 22.04, 24.04, 26.04 LTS line | `apt`; AppArmor default; snaps on server |
| Debian | 12 (bookworm), 13 (trixie) lines | Long support; `apt`; minimal by default |
| SUSE | SLES 15/16 lines, openSUSE Leap/Tumbleweed | `zypper`; YaST; btrfs default with snapshots |
| Arch / derivatives | Rolling | `pacman`; expect manual intervention notices |

- Verify exact support windows and EOL dates upstream before planning upgrades; distro
  lifecycles differ by release. Never infer a patch date from general impressions.
- Modern systemd (v255 and later in 2026) provides deep sandboxing directives; consult
  `systemd.exec(5)` on the target host rather than assuming a directive exists.
- Kernel 6.x is standard; cgroups v2 unified hierarchy is the default on all current
  distros. Hybrid v1 hosts are legacy and should be migrated.

## Boot and Service Inspection

```bash
systemctl --failed
systemctl status nginx --no-pager
systemd-analyze blame | head
systemd-analyze critical-chain sshd.service
journalctl -b -p err --since "1 hour ago"
hostnamectl; timedatectl
```

- `systemd-analyze verify /etc/systemd/system/foo.service` catches syntax and ordering
  errors before restarting.
- `systemctl cat unit` shows all drop-ins; `systemctl show -p ...` dumps effective values.
- Ordering (`After=`/`Before=`) is not dependency (`Wants=`/`Requires=`). Both are needed
  for the common "start after network but also pull it in" case.
- `Requires=` failure stops dependents; `Wants=` is best-effort. Use `BindsTo=` for
  lifetime coupling and `PartOf=` for restart propagation.

## Writing systemd Units

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My API
Documentation=https://example.invalid/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/myapp --config /etc/myapp/config.yaml
ExecReload=/bin/kill -HUP $MAINPID
User=myapp
Group=myapp
Restart=on-failure
RestartSec=3
TimeoutStopSec=30
KillSignal=SIGTERM
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=true
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallFilter=@system-service
ReadWritePaths=/var/lib/myapp /var/log/myapp
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

| `Type=` | Use when | Signals readiness |
|---|---|---|
| `simple` | Default; process forks nothing | Immediately (false readiness) |
| `exec` | Like simple but waits for exec to succeed | After exec |
| `notify` | App calls `sd_notify(READY=1)` | Explicit; best for daemons |
| `forking` | Legacy daemon double-forks | Parent exit |
| `oneshot` | Task that exits; pair with `RemainAfterExit=` | On completion |
| `idle` | Delay until other jobs finish | After queue drained |

- Never edit units in `/usr/lib/systemd/system`; place overrides in
  `/etc/systemd/system/<unit>.d/10-override.conf` via `systemctl edit`.
- `daemon-reload` after any unit change; `restart` (not `reload`) when `ExecStart`
  changes, because `reload` keeps the old process image.
- Sandbox errors surface as `status=226/NAMESPACE` or `203/EXEC`; check
  `journalctl -u unit` and `systemd-analyze verify` before blaming the app.
- `ProtectSystem=strict` makes `/usr`, `/boot`, `/etc` read-only; list writable paths in
  `ReadWritePaths=`. This is the single highest-value hardening directive for services.

## Timers vs cron

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Nightly backup

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=15m
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
```

```bash
systemctl list-timers --all
systemctl start backup.timer
systemd-analyze calendar "Mon..Fri *-*-* 09:00:00"
journalctl -u backup.service --since today
```

| Need | Choice | Rationale |
|---|---|---|
| Scheduled job with logs and dependencies | systemd timer | journald, `Persistent=`, jitter, cgroup limits |
| Simple periodic snippet, legacy host | cron | Universal; mail on output; watch `PATH` |
| Run missed job after downtime | Timer `Persistent=true` | cron has no catch-up |
| Per-user schedules | User timers (`systemctl --user`) or cron | User timers need lingering |
| Anacron-style on minimal systems | `cronie`/`dcron` + anacron | No systemd present |

- Timers need a matching `.service` with the same basename; enabling the timer does not
  enable the service.
- `OnCalendar` uses systemd calendar syntax; always test with `systemd-analyze calendar`.
- cron environment is minimal: absolute paths, explicit `PATH`, no shell rc files.
  Set `MAILTO=` if output should be discarded deliberately.

## Users, Groups, Permissions

```bash
useradd --create-home --shell /bin/bash --groups sudo deploy
usermod -aG docker deploy            # -a is mandatory; omission replaces groups
passwd -l olduser                     # lock password login
userdel --remove olduser
id deploy; groups deploy; getent passwd deploy
```

| Mechanism | Use for | Notes |
|---|---|---|
| POSIX modes (`chmod`) | Owner/group/other bits | `umask 027` typical for servers |
| ACLs (`setfacl`) | Per-user/per-dir grants | `getfacl`; survives most copies; check fs support |
| Capabilities (`setcap`) | One narrow root privilege | Prefer over setuid binaries |
| sudo rules | Delegated admin | `/etc/sudoers.d/`, `visudo -c` to validate |
| `systemd` `User=` | Service identity | Cheaper than sudo for daemons |
| SELinux/AppArmor | Mandatory access control | See [hardening](./09-security-hardening.md) |

- Setuid binaries are a persistent risk; inventory with
  `find / -xdev -perm -4000 -type f 2>/dev/null` and remove unnecessary ones.
- Sticky bit on shared dirs (`/tmp`, upload dirs) prevents deletion of others' files.
- `chmod g+s` on a directory sets group inheritance for new files (setgid dir), which is
  often better than per-file group juggling.
- `sudo` environment: `env_reset`, `secure_path`, `requiretty` defaults vary; test rules
  with `sudo -l -U user` and validate syntax with `visudo -c`.
- Never give `NOPASSWD: ALL` broadly; scope commands and arguments. Argument globs are
  bypassable — prefer wrapper scripts with fixed paths.
- Home directory permissions matter: `700` for users with SSH keys; sshd refuses
  world-writable homes and authorized_keys.

## cgroups v2

```bash
systemctl set-property myapp.service MemoryMax=2G CPUQuota=150%
systemctl set-property --runtime myapp.service IOWeight=100
cat /sys/fs/cgroup/system.slice/myapp.service/memory.current
cat /sys/fs/cgroup/system.slice/myapp.service/memory.events
cat /sys/fs/cgroup/system.slice/myapp.service/cpu.stat
```

| File | Meaning | Typical use |
|---|---|---|
| `memory.max` | Hard limit; OOM kills inside cgroup | Cap runaway services |
| `memory.high` | Soft throttle threshold | Prefer over hard limit for latency |
| `memory.current` / `memory.peak` | Usage now / high-water | Monitoring |
| `memory.events` | `oom`, `oom_kill`, `high` counters | Detect pressure |
| `cpu.weight` | Relative CPU share (1-10000) | Fair sharing between services |
| `cpu.max` | `"quota period"` bandwidth cap | Hard CPU caps |
| `pids.max` | Process/thread cap | Fork-bomb containment |
| `io.weight` / `io.max` | I/O share / bandwidth ceilings | Noisy-neighbor control |
| `cgroup.pressure` | PSI pressure per cgroup | Saturation signals |

- Every systemd service is in a cgroup; prefer `systemctl set-property` or unit
  directives (`MemoryMax=`, `CPUQuota=`, `TasksMax=`) over hand-editing the hierarchy.
- `system.slice` vs `user.slice` split resources by context; `user-<uid>.slice` caps a
  whole login session.
- v1 controllers (`cpu`, `memory`, `blkio`) are legacy; do not build new automation on
  `/sys/fs/cgroup/<controller>/`.
- Delegation: `Delegate=yes` lets a service manage its own subtree (used by container
  runtimes); needed for rootless containers to set limits.

## Namespaces (operator view)

```bash
lsns                                  # list namespaces and owners
nsenter -t "$PID" -n ss -tulpn        # enter a process's network namespace
unshare --user --map-root-user --mount bash   # quick unprivileged playground
ip netns add lab && ip netns exec lab ip link
```

| Namespace | Isolates | Typical debugging use |
|---|---|---|
| `mnt` | Mount points | Inspect a container's view: `nsenter -m` |
| `pid` | Process IDs | See container processes: `nsenter -p` |
| `net` | Interfaces, routes, ports | `nsenter -n ss -tulpn` |
| `user` | UID/GID mapping | Rootless containers |
| `uts` | Hostname/domain | Container hostname surprises |
| `ipc` | SysV/POSIX IPC | Shared memory issues |
| `cgroup` | cgroup root view | Container cgroup visibility |
| `time` | Clock offsets | Time namespace experiments |

- `nsenter -t PID -a` enters all namespaces; requires privilege unless the target is
  your own process. It is the primary tool for [container debugging](./08-containers-os.md).
- Namespaces isolate visibility, cgroups limit consumption; neither is a security
  boundary by itself without user namespaces plus MAC and seccomp.

## journald

```bash
journalctl -u nginx -f
journalctl -p warning -S "2026-01-01" -U "2026-01-02"
journalctl -k -b -1                    # kernel, previous boot
journalctl _PID=1234 -o json-pretty
journalctl --disk-usage
journalctl --vacuum-time=30d
```

- Persistent storage: create `/var/log/journal/` (or set `Storage=persistent` in
  `/etc/systemd/journald.conf`); otherwise logs vanish at reboot.
- Bound growth with `SystemMaxUse=`, `SystemMaxFileSize=`, `MaxRetentionSec=`; default
  is 10% of the filesystem. Rotate with `journalctl --rotate` before vacuuming.
- `journalctl -o cat` strips metadata for piping; `-o json` is for tooling.
- Application logs to stdout/stderr are captured automatically for services. Do not
  double-write to files; use `StandardOutput=journal`.
- Remote shipping: `systemd-journal-remote`/`-upload`, or a collector reading the
  journal file format. Centralize before you need it.

## Package Management

| Distro | Install | Update | Search owner | Verify |
|---|---|---|---|---|
| Debian/Ubuntu | `apt install p` | `apt update && apt full-upgrade` | `dpkg -S file` | `apt-cache policy p` |
| RHEL/Fedora | `dnf install p` | `dnf upgrade` | `rpm -qf file` | `dnf info p` |
| SUSE | `zypper in p` | `zypper up` | `rpm -qf file` | `zypper info p` |
| Arch | `pacman -S p` | `pacman -Syu` | `pacman -Qo file` | `pacman -Si p` |

- Unattended security updates: `unattended-upgrades` (Debian/Ubuntu),
  `dnf-automatic` (RHEL family). Configure reboots separately and deliberately.
- Repository hygiene: pin third-party repos, prefer vendor packages, and avoid
  `curl | sh` installers on servers. Verify signatures.
- Container/universal packages: snaps and flatpaks are for desktop or vendor-pinned
  cases; check mount points and update channels before adopting on servers.
- Keep a manifest (`dpkg -l`, `rpm -qa`) in config management; do not hand-install
  packages that drift from the source of truth.
- Upgrades run in a maintenance window with console access; kernel and glibc updates
  need reboots and rollback plans.

## Troubleshooting Quick Reference

```bash
dmesg -T --level=err,warn              # kernel ring buffer, human time
lsof -i :8080; ss -tulpn               # who owns a port
ps -eo pid,ppid,stat,etime,cmd --sort=-%mem | head
strace -f -p PID -tt -T -e trace=network  # syscall trail (use briefly)
df -h; df -i; lsblk -f                 # capacity and inodes
systemctl status; journalctl -b -p err # last stop for many issues
```

- OOM kills appear in `dmesg` as `Out of memory: Killed process` and in cgroup
  `memory.events`; correlate with [performance](./07-performance-tuning.md).
- Disk full vs inodes full vs read-only remount (after I/O errors) are three different
  failures with the same symptom; check all three.
- A service that works manually but fails under systemd is usually environment
  (`PATH`, `HOME`), working directory, or sandboxing (`ProtectSystem`).

## Anti-Patterns

- Editing vendor unit files in place instead of drop-ins.
- `chmod -R 777` or `chown -R nobody` as a debugging step.
- Running services as root when a dedicated user and capabilities suffice.
- Disabling SELinux or AppArmor to make a service start.
- cron jobs without absolute paths, error handling, or output redirection.
- Hand-editing `/etc/passwd`/`/etc/shadow` instead of `useradd`/`usermod`/`passwd`.
- Ignoring `systemctl --failed` after boot.
- Unbounded journald or package caches filling the root filesystem.
- Kernel upgrades applied without a reboot plan or console access.

## Checklist

- [ ] Host is on a supported distro release; EOL tracked.
- [ ] Unattended security updates enabled, reboot policy decided.
- [ ] Services run as dedicated users with sandboxing directives where practical.
- [ ] Units verified (`systemd-analyze verify`) and drop-in overrides recorded.
- [ ] Timers preferred over cron; `Persistent=true` for catch-up jobs.
- [ ] cgroup limits (`MemoryMax`, `CPUQuota`, `TasksMax`) set on risky services.
- [ ] journald persistent and size-bounded; critical logs shipped off-host.
- [ ] NTP synchronized; timezone and hostname correct.
- [ ] Setuid inventory reviewed; sudo rules minimal and validated.
- [ ] Root filesystem capacity and inode headroom monitored.

Related: [storage](./06-storage-filesystems.md), [performance](./07-performance-tuning.md),
[containers](./08-containers-os.md), [hardening](./09-security-hardening.md).
