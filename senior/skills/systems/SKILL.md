---
description: "Deep systems patterns for shell scripting, Linux/macOS/Windows administration, networking, storage, and performance"
---

# Systems

## Shell Scripting

### Bash Strict Mode
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

- `set -e`: Exit on error.
- `set -u`: Treat unset variables as error.
- `set -o pipefail`: Pipeline fails if any command fails.
- `IFS` with newline/tab: Prevents word splitting on spaces.

### Error Handling
```bash
cleanup() {
    local exit_code=$?
    rm -f "$TMPFILE"
    exit "$exit_code"
}
trap cleanup EXIT

handle_err() {
    echo "Error on line $1" >&2
    exit 1
}
trap 'handle_err $LINENO' ERR
```

### Patterns
```bash
# Strict argument parsing
usage() { echo "Usage: $0 [-f] [-o output]" >&2; exit 1; }
while getopts ":fo:" opt; do
    case $opt in
        f) FORCE=1 ;;
        o) OUTPUT="$OPTARG" ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

# Safe temp files
TMPDIR=$(mktemp -d) && readonly TMPDIR

# Logging
log() { printf '%(%Y-%m-%d %H:%M:%S)T %s\n' -1 "$*"; }
```

## Linux Administration

### systemd
```ini
[Unit]
Description=My Service
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/myserver
User=myuser
Restart=always
RestartSec=5
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateTmp=true
ProtectSystem=strict
ReadOnlyPaths=/

[Install]
WantedBy=multi-user.target
```

### Namespaces & cgroups
```bash
# Create network namespace
ip netns add blue
ip link add veth0 type veth peer name veth1
ip link set veth1 netns blue
ip netns exec blue ip addr add 10.0.0.1/24 dev veth1

# cgroups v2
mkdir -p /sys/fs/cgroup/mygroup
echo 100000 > /sys/fs/cgroup/mygroup/memory.max
echo $PID > /sys/fs/cgroup/mygroup/cgroup.procs
```

## macOS Administration

### launchd
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.myservice</string>
  <key>ProgramArguments</key>
  <array><string>/usr/local/bin/myservice</string></array>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/var/log/myservice.log</string>
  <key>StandardErrorPath</key><string>/var/log/myservice.err</string>
</dict>
</plist>
```

### TCC (Transparency, Consent, Control)
- Database: `/Library/Application Support/com.apple.TCC/TCC.db`
- Reset: `tccutil reset All`
- Privacy preferences: `systemsettings` -> Privacy & Security

## Networking

### iptables / nftables
```bash
# iptables
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -P INPUT DROP
iptables-save > /etc/iptables/rules.v4

# nftables (modern)
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
nft add rule inet filter input ct state established,related accept
nft add rule inet filter input tcp dport 443 accept
nft list ruleset > /etc/nftables.conf
```

### WireGuard
```ini
[Interface]
PrivateKey = <private>
Address = 10.0.0.1/24
ListenPort = 51820

[Peer]
PublicKey = <peer-public>
AllowedIPs = 10.0.0.0/24
Endpoint = peer.example.com:51820
PersistentKeepalive = 25
```

## Storage

| Technology | Use Case | Features |
|------------|----------|----------|
| LVM | Flexible disk mgmt | Snapshots, resize, striping |
| ZFS | Data integrity | Checksums, snapshots, compression, dedup |
| Ceph | Distributed storage | S3-compatible (RGW), block (RBD), filesystem (CephFS) |

### ZFS
```bash
zpool create tank mirror /dev/sda /dev/sdb
zfs set compression=zstd tank
zfs set atime=off tank
zfs snapshot tank/data@$(date +%Y%m%d)
```

## Performance Tuning

```bash
# sysctl tuning
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
vm.swappiness = 10
vm.dirty_ratio = 40
kernel.numa_balancing = 0

# Huge pages
echo always > /sys/kernel/mm/transparent_hugepage/enabled
```

- **CPU**: `cpufreq` governor `performance`, `taskset` for pinning.
- **Memory**: `numactl` for NUMA-aware placement.
- **Disk**: `ionice` for I/O priority, `fstrim` for SSD trim.
- **Network**: `ethtool -K` for offloading, `irqbalance` for IRQ affinity.
