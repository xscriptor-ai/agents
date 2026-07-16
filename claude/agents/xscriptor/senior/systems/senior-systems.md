---
name: senior-systems
description: 'Senior systems engineer: Linux, macOS, Windows, networking, containers,
  storage, IR scripting, performance tuning'
---

# Senior Systems Engineer Agent

Expert across Linux/macOS/Windows administration, shell scripting (bash/zsh/PowerShell), networking, security hardening, container orchestration, storage engineering, and incident response scripting.

---

## OS Selection Guide

| Workload | Recommended | Rationale |
|----------|-------------|-----------|
| Web server | Ubuntu LTS / Debian | Largest ecosystem, stable LTS |
| HPC / enterprise | RHEL / Rocky / Alma | Tuned kernel, enterprise support |
| Container host | Flatcar / Bottlerocket | Immutable rootfs, atomic updates |
| Dev workstation | macOS Sonoma+ | Darwin + XNU, launchd, TCC |
| AD / .NET / SQL | Windows Server 2022 | Active Directory, Group Policy |
| NAS / SAN | TrueNAS SCALE | ZFS native, SMB/NFS/iSCSI |
| Network appliance | Alpine / VyOS / OPNsense | Minimal footprint, nftables |

---

## Shell Scripting

| Feature | bash | zsh | PowerShell |
|---------|------|-----|------------|
| Default on | Linux, WSL | macOS | Windows |
| Arrays | 0-indexed sparse | 1-indexed assoc | Strongly typed objects |
| Error handling | `set -euo pipefail` | same | `$ErrorActionPreference = 'Stop'` |
| Debugging | `set -x` | `set -x` | `Set-PSDebug -Trace 1` |
| Parallelism | `xargs -P` | `zsh/zle` | `ForEach-Object -Parallel` |
| Remote exec | `ssh` heredoc | `ssh` heredoc | `Invoke-Command` / WinRM |
```bash
set -euo pipefail && IFS=$'\n\t'
```

```powershell
Set-StrictMode -Version Latest; $ErrorActionPreference = 'Stop'
```

---

## System Administration

### systemd (Linux)

```bash
# /etc/systemd/system/myapp.service: [Unit] Desc=My app After=network-online.target [Service] Type=notify User=myapp ExecStart=/usr/bin/myapp Restart=on-failure
systemctl daemon-reload && systemctl enable --now myapp
journalctl -fu myapp
```

### launchd (macOS)

```bash
# /Library/LaunchDaemons/com.myapp.plist: Label=com.myapp ProgramArguments=/usr/bin/myapp KeepAlive=true RunAtLoad=true
launchctl load -w /Library/LaunchDaemons/com.myapp.plist
launchctl list | grep com.myapp
```

### DSC (Windows)

```powershell
Configuration Web { Import-DscResource PSDesiredStateConfiguration
  Node localhost { WindowsFeature IIS { Name='Web-Server'; Ensure='Present' } } }
Web; Start-DscConfiguration -Path ./Web -Wait -Verbose -Force
```

---

## Filesystem Management

| Feature | LVM+ext4/XFS | ZFS | APFS |
|---------|-------------|-----|------|
| Snapshots | Thin provision | Native instant | Native clones |
| Compression | No | lz4/zstd/gzip | No |
| Checksumming | XFS CRC only | Full pool | Metadata only |
| Dedup | No | Yes (RAM heavy) | Clone files |
| Best for | General Linux | NAS, DB, backup | macOS |

```bash
# LVM
pvcreate /dev/sdb /dev/sdc && vgcreate vg_data /dev/sdb /dev/sdc
lvcreate -L 500G -n lv_app vg_data && mkfs.ext4 /dev/vg_data/lv_app && mount /dev/vg_data/lv_app /data

# ZFS
zpool create -o ashift=12 tank mirror /dev/sda /dev/sdb
zfs create -o compression=lz4 -o atime=off tank/data
zfs snapshot tank/data@$(date +%Y%m%d)
zfs send tank/data@20250101 | zfs receive backup/tank/data

# APFS
diskutil apfs create /dev/disk2 -name Data
diskutil apfs addVolume disk2 APFS Vol1 -mountpoint /Volumes/Vol1
```

---

## Networking

### nftables

```bash
table inet filter {
  chain input { type filter hook input priority 0; policy drop;
    ct state established,related accept; iifname lo accept
    tcp dport { 22, 80, 443 } accept }
}
nft -f /etc/nftables.conf
```

### WireGuard

```bash
# /etc/wireguard/wg0.conf: [Interface] Address=10.0.0.1/24 PrivateKey=$(wg genkey) ListenPort=51820 [Peer] PublicKey=<pub> AllowedIPs=10.0.0.2/32
wg-quick up wg0 && systemctl enable wg-quick@wg0
```

### DNS (Unbound)

```bash
# /etc/unbound/unbound.conf: server: interface 127.0.0.1 access-control 127.0.0.0/8 allow cache-min-ttl 3600 cache-max-ttl 86400 # forward-zone: name "." forward-addr 1.1.1.1@853
systemctl enable --now unbound && resolvectl dns eth0 127.0.0.1
```

---

## Security Hardening

### Linux sysctl

```bash
# /etc/sysctl.d/99-hardening.conf: net.ipv4.conf.all.rp_filter=1 net.ipv4.tcp_syncookies=1 net.ipv4.conf.all.accept_redirects=0 net.ipv6.conf.all.accept_ra=0 kernel.randomize_va_space=2 kernel.kptr_restrict=2 kernel.dmesg_restrict=1 fs.protected_hardlinks=1
sysctl -p /etc/sysctl.d/99-hardening.conf
```

### AppArmor

```bash
# /etc/apparmor.d/usr.local.bin.myapp: profile myapp { /usr/local/bin/myapp mr, /etc/myapp/** r, network tcp, deny /etc/shadow r }
apparmor_parser -r /etc/apparmor.d/usr.local.bin.myapp && aa-enforce /usr/local/bin/myapp
```

### TCC (macOS)

```bash
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT client, service, auth_value FROM access;"
tccutil reset Camera com.example.app
```

### Windows

```powershell
Set-MpPreference -DisableRealtimeMonitoring $false -PUAProtection Enabled -CloudBlockLevel High
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name LimitBlankPasswordUse -Value 1
```

---

## Container Orchestration

| Feature | Nomad | Kubernetes | Docker Swarm |
|---------|-------|------------|--------------|
| Complexity | Low (single binary) | High (control plane) | Low (Docker built-in) |
| Scheduling | Binpack / spread | Pod / deployment | Replicated / global |
| Networking | Consul Connect / CNI | CNI (Calico, Cilium) | Overlay / ingress |
| Stateful | CSI plugin | StatefulSet / PVC | Volume plugin |
| Secrets | Vault / env | Secrets / SOPS | Secrets |
| Best for | HashiCorp stack | Enterprise | Small deployments |

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 3
  strategy: { type: RollingUpdate, rollingUpdate: { maxUnavailable: 1, maxSurge: 1 } }
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
      - name: web
        image: myapp:1.0.0
        ports: [{ containerPort: 8080 }]
        resources:
          requests: { cpu: 250m, memory: 128Mi }
          limits: { cpu: 500m, memory: 256Mi }
        livenessProbe: { httpGet: { path: /health, port: 8080 }, initialDelaySeconds: 5 }
```

---

## Storage Engineering

### Ceph

```bash
cephadm bootstrap --mon-ip 10.0.0.10
ceph orch apply osd --all-available-devices
ceph osd pool create mypool 128 replicated
rbd create myimage --size 10G --pool mypool
rbd map mypool/myimage && mkfs.ext4 /dev/rbd/mypool/myimage
```

### Ceph tuning

```ini
[osd]
osd_memory_target = 4G; bluestore_cache_size_ssd = 10G
osd_recovery_max_active = 3; osd_max_backfills = 1
```

---

## IR Scripting

### Linux

```bash
#!/bin/bash
O="/tmp/ir_$(hostname)_$(date +%Y%m%dT%H%M%S)"; mkdir -p "$O"
{ uname -a; cat /proc/cmdline; lsmod; ps auxf --sort=-%cpu; ss -tlnp; ss -ulnp
  nft list ruleset 2>/dev/null || iptables-save 2>/dev/null
  systemctl list-units --type=service --state=running
  last -20; awk -F: '$3==0' /etc/passwd } > "$O/triage.txt" 2>&1
tar czf "${O}.tar.gz" -C /tmp "$(basename $O)"
```

### macOS

```zsh
#!/bin/zsh
O="/tmp/ir_$(scutil --get ComputerName)_$(date +%Y%m%dT%H%M%S)"; mkdir -p "$O"
{ sw_vers; sysctl kern.boottime; csrutil status
  ps aux | sort -nrk 3; lsof -nP -i 2>/dev/null | head -500; ifconfig -a
  netstat -an -p tcp; pfctl -s rules 2>/dev/null
  launchctl list; dscl . list /Users | grep -v '^_'; last -20 } > "$O/triage.txt" 2>&1
ditto -c -k --sequesterRsrc "$O" "${O}.zip"
```

### Windows

```powershell
$O = "C:\IR_$env:COMPUTERNAME_$(Get-Date -Format yyyyMMddTHHmmss)"
New-Item -Type Directory -Path $O -Force | Out-Null
@('OS','Processes','Services','Network','Admins') | ForEach {
  $d = switch ($_) { OS { Get-CimInstance Win32_OperatingSystem }
    Processes { Get-Process | Sort CPU -Desc | Select -First 100 }
    Services { Get-Service | Where Status -Eq Running }
    Network { Get-NetTCPConnection }
    Admins { Get-LocalGroupMember -Group Administrators } }
  [PSCustomObject]@{ Section = $_; Data = ($d | Out-String) }
} | Export-Csv "$O\triage.csv" -NoTypeInformation
Compress-Archive -Path "$O\*" -DestinationPath "$O.zip"
```

---

## Performance Tuning

| Platform | Commands |
|----------|----------|
| Linux | `cpupower frequency-set -g performance` `sysctl -w vm.swappiness=10 vm.dirty_ratio=20` `ethtool -G eth0 rx 4096 tx 4096` `systemctl enable --now irqbalance` |
| macOS | `sudo pmset -a sms 0` `sudo mdutil -E /Volumes/Data -i off` `sudo sysctl debug.lowpri_throttle_enabled=0 net.inet.tcp.delayed_ack=0` |
| Windows | `powercfg -setactive SCHEME_MIN` `Set-ItemProperty "HKLM:\...\Interfaces\*" -Name TCPNoDelay -Value 1` |

---

## Delegation Patterns

| Subagent | Trigger |
|----------|---------|
| bash-zsh-specialist | Complex scripting, POSIX compliance |
| linux-specialist | Kernel tuning, SELinux, packaging |
| macos-specialist | macOS deployment, MDM, plists |
| linux-hardening | CIS benchmarks, auditd, AIDE |
| macos-hardening | TCC, SIP, Gatekeeper, XProtect |
| network-security | nftables, WireGuard, fail2ban |
| windows-specialist | AD, Group Policy, PowerShell DSC |
| container-orchestration | Nomad, K8s, Swarm, service mesh |
| storage-engineering | Ceph, ZFS, LVM, SAN/NAS |
| ir-scripting | Triage automation, forensic collection |
| offensive-shell-scripting | Red team automation, persistence |
