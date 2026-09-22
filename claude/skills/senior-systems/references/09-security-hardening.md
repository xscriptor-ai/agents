# Security Hardening

Hardening hosts and workloads: SSH, SELinux/AppArmor, auditd, firewall defaults, CIS-style baselines, patch strategy, and least privilege.

## Threat-Model First

Hardening without a threat model produces either theater or breakage. Start from:

| Question | Consequence |
|---|---|
| Internet-exposed or internal only? | Determines SSH, firewall, and update posture |
| What data can this host reach? | Determines credential and network segmentation needs |
| Who administers it and how? | Determines identity, sudo, and audit design |
| What is the blast radius of compromise? | Determines isolation (VM/container/sandbox) |
| What compliance regime applies? | Determines evidence and baseline requirements |

- Assume perimeter breach; segment networks so one host does not grant access to all.
- Defense in depth: patching, least privilege, mandatory access control, logging, and
  backups each cover the others' failures.
- Every control has an operational cost; document accepted risks and deviations rather
  than silently weakening controls.

## Patch Strategy

| Layer | Mechanism | Cadence |
|---|---|---|
| OS security updates | `unattended-upgrades`, `dnf-automatic`, WUfB | Automatic for security, windowed for features |
| Kernel | Distro kernel, livepatch where supported | Reboot window; livepatch covers CVEs between reboots |
| Applications | Version-pinned package manager, container base rebuild | Rebuild images on base updates |
| Firmware | Vendor tooling (`fwupd`, vendor utilities) | Per advisory |
| EOL tracking | Inventory with OS/runtime versions | Alert months before EOL |
| Emergency | Out-of-band critical advisories | Defined runbook and communication path |

- Patch the exploit path first: internet-facing services, then lateral-movement
  enablers (SSH, sudo, agents), then everything else.
- Automatic updates can break services; stage in a canary ring and monitor. Never let
  patching be "someone else's job".
- Reboots are part of patching: kernel, glibc, and systemd updates need them. Track
  pending reboot state (e.g., `/var/run/reboot-required`, `needs-restarting -r`,
  `Get-WindowsUpdate` reboot flags).
- Verify EOL dates upstream; do not extrapolate. Unsupported kernels and runtimes are
  the root cause of many "0-day" compromises.
- Livepatching covers only kernel CVEs and only with a supported vendor subscription;
  it is a bridge, not a replacement for maintenance windows.

## SSH Hardening

```sshconfig
# /etc/ssh/sshd_config.d/10-hardening.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
PermitEmptyPasswords no
UsePAM yes
AllowGroups ssh-users
LogLevel VERBOSE
```

```bash
sshd -t                                   # validate before reload
systemctl reload sshd || systemctl reload ssh
ssh-keygen -t ed25519 -a 100 -C "user@host"
ssh-keygen -t ed25519-sk -C "user@host"   # hardware-backed (FIDO2)
ssh -o StrictHostKeyChecking=accept-new host
ssh-keygen -R host
```

| Control | Recommendation | Notes |
|---|---|---|
| Keys | Ed25519 (or `ed25519-sk`) | RSA 3072+ only for legacy; DSA is dead |
| Passwords | Disabled | Exceptions documented, MFA required |
| Root login | `no`; use sudo | `prohibit-password` only as a transition |
| MFA | TOTP or hardware keys | `AuthenticationMethods publickey,keyboard-interactive` |
| Agent forwarding | Off by default | Use `ProxyJump` instead |
| Port change | Optional, low value | Reduces noise only, not a control |
| fail2ban/sshguard | Optional with keys | Useful where passwords remain |
| Certificates | Short-lived CA-signed keys | Scales better than `authorized_keys` |
| Access scope | `AllowGroups`/`Match` blocks | Restrict by user, group, source, command |
| Sessions | `MaxSessions`, timeouts | Limits hijacked connection persistence |

- `ProxyJump bastion` keeps the bastion as the only exposed SSH endpoint; the bastion
  runs no other services and logs sessions centrally.
- Host keys must be verified; distribute `known_hosts` via config management or use
  SSHFP/DNS or certificates.
- `authorized_keys` options matter: `from=`, `command=`, `no-agent-forwarding`,
  `no-port-forwarding`, `no-pty`, `restrict` (deny by default).
- Client config belongs in the repo (`~/.ssh/config` templates), with separate keys per
  role/host; never reuse one key everywhere.
- Private keys: mode `600`, passphrase or hardware-backed, never copied to servers.
- Validate with `sshd -t` and keep a second session open while changing SSH settings;
  lockouts are self-inflicted outages.

## SELinux (RHEL family)

```bash
getenforce; sestatus
ls -Z /var/www/html; ps -eZ | grep httpd
semanage fcontext -a -t httpd_sys_content_t "/srv/www(/.*)?"
restorecon -Rv /srv/www
setsebool -P httpd_can_network_connect on
ausearch -m AVC,USER_AVC -ts recent
sealert -a /var/log/audit/audit.log
```

| Mode | Meaning | Use |
|---|---|---|
| `enforcing` | Policy violations denied | Production default |
| `permissive` | Logged but allowed | Diagnosis only; alerts still fire |
| `disabled` | No policy | Only with an accepted written risk |

- Never `setenforce 0` as a permanent fix; fix the label or boolean instead.
- Contexts follow files; moving files between roles (`mv` preserves context) breaks
  labels — use `restorecon` and define `semanage fcontext` rules for custom paths.
- `audit2allow` generates policy from denials: review every rule; blindly allowing all
  denials creates permissive policy and hides attacks.
- Booleans toggle supported behaviors (`getsebool -a`); use `-P` to persist.
- Relabeling (`touch /.autorelabel`, `fixfiles -F onboot`) takes a reboot and can be
  slow; know why labels broke (usually a copied filesystem or an unpacked archive).
- Container hosts: containers get `container_t` labels; volume mounts need
  `:z`/`:Z` or explicit context configuration.

## AppArmor (Ubuntu/SUSE)

```bash
aa-status
aa-enforce /etc/apparmor.d/usr.sbin.nginx
aa-complain /etc/apparmor.d/usr.sbin.nginx
journalctl -k | grep -i apparmor
apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx
```

- Profiles restrict file access, capabilities, and network operations per binary;
  shipped profiles cover many daemons out of the box.
- `complain` mode logs but allows; use it to develop a profile, then enforce.
- Denials appear in the kernel journal; iterate on the profile rather than disabling
  AppArmor.
- Profile reload is per-profile; no reboot needed. Custom profiles live in
  `/etc/apparmor.d/`.
- For containers, the `docker-default` profile applies unless overridden; do not set
  `apparmor=unconfined` to make an image work.

## auditd

```bash
auditctl -l
auditctl -w /etc/passwd -p wa -k identity
auditctl -w /etc/sudoers -p wa -k privilege
auditctl -a always,exit -F arch=b64 -S execve -F euid=0 -k root_exec
ausearch -k identity -ts today
aureport --summary; aureport --auth --failed
service auditd restart
```

- Rules live in `/etc/audit/rules.d/*.rules` (generated to `/etc/audit/audit.rules`);
  manage them as code.
- Baseline rule categories: identity files, privilege escalation, kernel module loads,
  network config changes, time changes, and execution by privileged users.
- `-F arch=b64` plus a b32 rule on x86_64 for complete coverage; syscall auditing of
  `execve` is high-volume, so scope it (e.g., `euid=0`) and size the log partition.
- `-e 2` makes the audit configuration immutable until reboot; use on hardened hosts
  and plan rule changes around reboots.
- Audit only what you will read: forward to a SIEM, alert on `--auth --failed` and
  identity-key events. Unread audit logs are cost without control.
- `auditd` can be throttled under event storms (`-r` rate limit, backlog warnings); a
  drops-in-audit message means evidence is missing.
- Consider auditd alongside sysmon-for-Linux or eBPF-based monitoring for richer
  process telemetry.

## Firewall Defaults

| Layer | Default | Tooling |
|---|---|---|
| Host (Linux) | Deny inbound, allow outbound, drop invalid | nftables, firewalld, ufw |
| Host (macOS) | Application firewall on; stealth mode | `socketfilterfw`, pf for advanced |
| Host (Windows) | Domain/Private deny inbound; Public strict | Defender Firewall, GPO |
| Cloud | Security group/NACL deny by default | Terraform/console; review drift |
| Container | Publish only required ports | Runtime network config |

```bash
nft list ruleset | tee /etc/nftables.conf    # review before persisting
firewall-cmd --state; firewall-cmd --list-all
ufw status verbose
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

- Host firewall and cloud security group must agree; the effective policy is the
  intersection. Test from outside, not just localhost.
- Egress filtering is underused: servers rarely need unrestricted outbound. Allow DNS,
  NTP, package mirrors, and known peers; default-deny the rest where feasible.
- Log denied traffic deliberately; logging everything floods disks and hides signals.
- Rate-limit SSH/ICMP at the firewall edge; do not rely on fail2ban alone.
- Review rules as code: diff after changes, remove stale allows for decommissioned
  services and IPs.

## CIS-Style Baselines and Evidence

```bash
# OpenSCAP (RHEL family)
oscap xccdf eval --profile cis --results results.xml --report report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
# Lynis
lynis audit system
# Docker Bench (container host)
docker-bench-security
```

- CIS Benchmarks are prescriptive but not free: each profile level has operational
  tradeoffs. Choose Level 1 as baseline, evaluate Level 2 items individually.
- Automated scanners produce false positives and drift; triage findings and keep a
  deviation register with owner, reason, and expiry.
- Score is not security: 100% on a scanner with unpatched services is worse than 80%
  with current patches and monitoring.
- Re-scan after changes and after upgrades; baselines are living configuration, not
  one-time projects.
- Pair technical controls with identity controls: MFA, privileged access management,
  break-glass accounts with rotation, and session recording for high-risk access.
- Managed fleets: MDM/GPO/DSC/Ansible ensure drift correction; scanners only measure.

## Least Privilege in Practice

- **Accounts** — one identity per human, no shared logins; service accounts with
  non-login shells; disable unused accounts; review group membership quarterly.
- **sudoers** — `visudo -c` validation; rules by command path and arguments; no
  `NOPASSWD: ALL` except documented break-glass; `Defaults use_pty` and `log_output`.
- **Capabilities** — prefer `CAP_NET_BIND_SERVICE` over running as root; check with
  `getcap -r / 2>/dev/null` and remove unnecessary setuid (`find / -perm -4000`).
- **File permissions** — `umask 027`, `600` for keys and secrets, `640` for shared
  config; audit world-writable files (`find / -xdev -perm -0002 -type f`).
- **Secrets** — managers (Vault, SOPS, cloud secret stores) over files; never in Git,
  shell history, or process arguments. Rotate on staff changes and suspected exposure.
- **Service isolation** — dedicated users, systemd sandboxing (`ProtectSystem=strict`,
  `PrivateTmp=`, `NoNewPrivileges=`, `SystemCallFilter=`), AppArmor/SELinux confinement.
- **Network** — segmentation and egress rules limit lateral movement; default-deny
  between tiers, not just at the perimeter.
- **Kernel** — enable `kernel.dmesg_restrict=1`, `kernel.kptr_restrict=2`,
  `kernel.yama.ptrace_scope=1` where compatible; consider `lockdown=confidentiality`
  on high-value hosts.
- **Backups** — immutable/offline copies defeat ransomware and credential theft;
  restore credentials are separate from production credentials.
- **Integrity** — AIDE/Tripwire for file integrity, `rpm -Va`/`debsums` for package
  verification, and boot integrity (Secure Boot, measured boot) where required.

## Incident Triage Checklist (Host)

1. Preserve evidence first: memory (if warranted), disk image or snapshot, and logs
   before changes. Note time source and timezone.
2. Identify the process tree and network connections: `ps auxf`, `ss -tupn`, `lsof -i`.
3. Check persistence: cron/timers, systemd units, launchd items, scheduled tasks, SSH
   keys, shell rc files, and package changes.
4. Check accounts and auth: `last`, `lastlog`, sudo/audit logs, new UIDs, group changes.
5. Check files: recently modified binaries (`rpm -Va`, `find -mtime`), deleted-but-open
   files (`lsof +L1`), and unexpected listening ports.
6. Isolate at the network layer (not by wiping), keep the host powered for forensics if
   policy requires, and notify per the incident plan.
7. Eradicate by rebuilding from a known-good image when integrity is uncertain; treat
   credential rotation as mandatory after any confirmed compromise.

## Anti-Patterns

- Disabling SELinux/AppArmor, lowering firewall rules, or granting `NOPASSWD: ALL` to
  make an error disappear.
- Changing the SSH port and calling it security while leaving passwords enabled.
- Treating an automated CIS score as security; ignoring deviations.
- Storing long-lived credentials in environment variables or files readable by others.
- Patching only when prompted by an incident.
- Auditing everything and reading nothing.
- Assuming internal networks are trusted; flat networks amplify any foothold.
- Leaving default credentials on management interfaces (BMC/IPMI, databases, routers).
- Rebuilding a compromised host in place rather than from a known-good image.

## Checklist

- [ ] Threat model and data classification documented for the host/role.
- [ ] OS and applications on supported versions; EOL tracked; patch cadence defined.
- [ ] Automatic security updates enabled with monitoring and restart policy.
- [ ] SSH: keys only, root login disabled, restricted groups, MFA where required.
- [ ] Firewall default deny with explicit allows; egress considered; rules persisted.
- [ ] SELinux/AppArmor enforcing, exceptions documented.
- [ ] auditd rules in place, forwarded, and reviewed; log capacity sized.
- [ ] Least privilege: sudo/groups review, capabilities, file permissions, secrets.
- [ ] Failure monitoring and integrity checks deliver alerts someone acts on.
- [ ] Backups immutable/offline with restore tests and separate credentials.
- [ ] Baseline deviations recorded with owner and expiry; incidents have a runbook.

Related: [Linux administration](./02-linux-admin.md) for units and privileges,
[networking](./05-networking.md) for firewall and tunnel configuration,
[containers](./08-containers-os.md) for isolation boundaries.
