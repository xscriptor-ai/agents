# Networking

Diagnosing and configuring network paths on Linux/macOS/Windows hosts: DNS, TCP and TLS lifecycles, packet and socket tools, nftables, tunnels/VPN, and proxy debugging.

## Diagnostic Model

Work bottom-up and stop at the first broken layer. Each layer has a cheap test.

| Layer | Question | Command | Common failure |
|---|---|---|---|
| Link | Is the interface up/carrier? | `ip -br link`, `ethtool eth0` | Cable, VLAN, driver, MTU |
| IP | Do we have a valid address? | `ip -br addr` | DHCP, duplicate IP, wrong subnet |
| Route | Does a path exist? | `ip route`, `ip rule` | Missing default, policy routing |
| Neighbor | Is the gateway reachable? | `ip neigh`, `arping` | ARP/NDP, proxy ARP |
| DNS | Does the name resolve? | `dig +short name`, `resolvectl query` | Wrong resolver, NXDOMAIN, search domain |
| TCP | Does the port answer? | `nc -vz host port`, `ss -tulpn` | Firewall drop, no listener, backlog |
| TLS | Does the handshake validate? | `openssl s_client -connect` | Expired/wrong chain, SNI, clock |
| App | Does the request succeed? | `curl -sv -o /dev/null` | Auth, headers, timeouts, proxy |

- Drops are silent; rejects are loud. A firewall `DROP` produces timeouts, `REJECT`
  produces connection-refused or ICMP errors. Use that to distinguish causes.
- Always compare from the same vantage point: localhost vs LAN vs internet behave
  differently because of firewall rules, NAT, and proxies.
- Capture before changing: `tcpdump -i any -nn -c 200` on both ends when possible.

## DNS

```bash
dig example.com A +short
dig example.com MX TXT
dig @1.1.1.1 example.com A +norecurse
dig +trace example.com
dig -x 203.0.113.10 +short
dig +tcp example.com                 # force TCP (truncation debugging)
drill example.com A                   # macOS/BSD alternative
resolvectl status; resolvectl query example.com
```

| Record | Purpose | Gotcha |
|---|---|---|
| `A`/`AAAA` | Host to IPv4/IPv6 | Dual-stack: clients may prefer IPv6 and fail |
| `CNAME` | Alias | Cannot coexist with other records at the apex |
| `MX` | Mail routing | Priority order, must point to A/AAAA |
| `TXT` | Verification, SPF/DKIM/DMARC | 255-char string chunks; aggregate limits |
| `SRV` | Service discovery | Weight/priority; underscores in names |
| `NS`/`SOA` | Delegation and zone metadata | Negative TTL from SOA affects caching |
| `CAA` | Which CAs may issue certs | Missing CAA blocks issuance |

- System resolution path differs: glibc `nsswitch.conf` (files, then DNS via
  `resolv.conf`), systemd-resolved (`resolvectl`, stub at `127.0.0.53`), macOS
  `scutil --dns` (per-interface resolvers + search domains), Windows `ipconfig /all`
  and `Get-DnsClientServerAddress`.
- `dig` bypasses the system resolver and talks directly to the server listed; when
  `dig @1.1.1.1` works but `getent hosts` fails, the local resolver configuration is at
  fault, not the zone.
- TTL discipline: lower TTLs before planned migrations, then restore. Clients ignore
  TTLs you wish they would respect; plan for the full propagation window.
- Search domains and `ndots` cause surprising names to resolve; trailing dot in `dig`
  and `curl` names (e.g., `example.com.`) avoids search-list interference.
- DoT/DoH encrypt queries but not the SNI/IP metadata; enterprise resolvers may be
  mandatory. Verify which resolver the OS actually uses before blaming DNS.
- Split-horizon zones return different answers internally vs externally; test from both
  sides.
- Negative answers are cached; `NXDOMAIN` lingering after a fix is usually TTL.

## TCP Lifecycle

```bash
ss -tan state established '( sport = :443 )'
ss -s                                  # summary by state
ss -tulpn                              # listeners with process
sysctl net.ipv4.tcp_congestion_control  # bbr on modern kernels
sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog
```

| State | Meaning | Concern |
|---|---|---|
| `LISTEN` | Accepting connections | Backlog overflow drops SYNs |
| `SYN-SENT` | Client handshake in flight | Packets filtered or host down |
| `SYN-RECV` | Server saw SYN, sent SYN-ACK | SYN flood or slow app |
| `ESTABLISHED` | Data transfer | Socket counts, file descriptors |
| `TIME-WAIT` | Normal close by local end | Port exhaustion in extreme cases |
| `CLOSE-WAIT` | Peer closed, app did not | Application leak, FD exhaustion |
| `FIN-WAIT-2` | Half-closed | Peer not closing; often benign |

- Three-way handshake: SYN → SYN-ACK → ACK. `tcpdump` showing repeated SYN with no
  SYN-ACK means the server side is dropping (firewall, no listener, or full backlog).
- Congestion control: CUBIC is the common default, BBR is widely deployed on modern
  kernels; verify with `sysctl net.ipv4.tcp_available_congestion_control`. Do not switch
  based on blog posts; benchmark on the actual path.
- RTT and loss drive throughput far more than buffer tuning. Measure first with `mtr`
  or `ping -c` series before touching `tcp_rmem`/`tcp_wmem`.
- MTU and PMTUD: tunnels and VPNs shrink the path MTU; black-holed ICMP breaks PMTUD and
  produces hangs on large packets. Test with `ping -M do -s 1472 host` (1400 payload for
  tunneled paths).
- Connection limits: `ss -s` counts sockets; process FD limits matter more than kernel
  tables in practice. See [performance](./07-performance-tuning.md) for ulimits.

## TLS Lifecycle

```bash
openssl s_client -connect example.com:443 -servername example.com -showcerts </dev/null
openssl s_client -connect example.com:443 -tls1_3 -brief
echo | openssl s_client -connect example.com:443 2>/dev/null | openssl x509 -noout -dates -subject -issuer
openssl x509 -in cert.pem -noout -text | grep -A1 'Subject Alternative Name'
curl -sv https://example.com -o /dev/null
```

- Handshake order: TCP connect → ClientHello (SNI, ALPN, cipher list) → ServerHello and
  certificate chain → client validation → key exchange → Finished. TLS 1.3 collapses
  this to one round trip; session resumption (PSK) removes another.
- Validate the full chain from leaf to root: mismatched intermediate order, missing
  intermediates, or an untrusted root break some clients and not others.
- Certificate checks: hostname must be in SAN (CN fallback is dead), validity window
  must include now, key usage/EKU must permit server auth. `openssl verify -CAfile` is
  the offline check.
- SNI selects the certificate; hitting a shared IP by IP address often yields the wrong
  vhost cert, a common false alarm.
- Clock skew invalidates certificates; check `timedatectl`/`w32tm` when TLS fails
  mysteriously.
- ACME automation (certbot, lego, acme.sh) with HTTP-01 or DNS-01; DNS-01 enables
  wildcards. Renew with jitter and monitor expiry at 30/14/7 days.
- mTLS: server requests client cert; verify the client chain and CRL/OCSP path. Treat
  client cert expiry as an outage.
- TLS 1.0/1.1 are deprecated; target 1.2+ with 1.3 preferred. Old clients must be a
  documented exception.

## Packet and Socket Tools

```bash
# curl: timings and virtual host resolution
curl -sS -o /dev/null -w 'dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' https://example.com
curl -sv --resolve example.com:443:203.0.113.10 https://example.com/
curl -x http://proxy:3128 -v https://example.com/
ssh -v host; ssh -vvv host          # two/three levels of connection debugging

# tcpdump: always bound the capture
tcpdump -i any -nn -c 100 port 443
tcpdump -i eth0 -nn 'host 203.0.113.10 and (port 80 or port 443)'
tcpdump -i any -nn -A 'tcp port 80 and (((ip[2:2]-((ip[0]&0xf)<<2))-((tcp[12]&0xf0)>>2)) != 0)'
tcpdump -i any -nn -w /tmp/cap.pcap 'port 53'   # analyze in Wireshark later

# path and reachability
mtr -rwzbc 50 example.com
traceroute -T -p 443 example.com
nmap -Pn -p 22,80,443 203.0.113.0/24
```

- `tcpdump -nn` avoids DNS/service lookups; without `-c` or a filter you will flood
  the terminal. Write to pcap when analysis is non-trivial.
- `ss -i` shows congestion window and RTT per connection; `ss -K` kills sockets.
- `curl -w` timing breakdown localizes slowness to DNS, connect, TLS, or application.
- `Get-NetTCPConnection` and `Test-NetConnection -Port` are the Windows equivalents;
  `pktmon` captures packets on modern Windows.
- On macOS, `nettop`, `networkQuality`, and `scutil --dns` fill gaps; `pfctl` is the
  firewall.

## nftables

```bash
nft list ruleset
nft -f /etc/nftables/edge.nft
```

```nft
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  set ssh_burst {
    type ipv4_addr
    flags dynamic, timeout
    timeout 1m
  }

  chain input {
    type filter hook input priority filter; policy drop;
    ct state established,related accept
    ct state invalid drop
    iif lo accept

    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept

    tcp dport 22 ct state new \
      meter ssh_burst { ip saddr limit rate over 4/minute } drop
    tcp dport 22 accept
    tcp dport { 80, 443 } accept
  }

  chain forward {
    type filter hook forward priority filter; policy drop;
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}
```

- nftables replaces iptables/ip6tables/arptables/ebtables; `iptables-nft` is a
  compatibility shim. Do not mix direct nft rules with iptables shim rules.
- Policy `drop` with `ct state established,related accept` first is the standard
  stateful baseline; the conntrack table must be sized for the workload.
- Sets and maps scale to large address lists; `flags dynamic, timeout` enables
  rate-limiting meters without extra tooling.
- Persist atomically: distro unit loads `/etc/nftables.conf` (Debian/Arch) or
  `/etc/sysconfig/nftables.conf` (RHEL family) with `nft -f`, or use `nft
  list ruleset > file` after live edits and review the diff.
- `firewalld` (RHEL) and `ufw` (Ubuntu) are frontends; use one layer consistently, do
  not manage the same host with both nft and a frontend.
- NAT for routers: `chain postrouting { type nat hook postrouting priority srcnat;
  oifname "eth0" masquerade; }`; container runtimes manage their own NAT tables — keep
  your rules separate.

## Tunnels and VPN

```ini
# /etc/wireguard/wg0.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>

[Peer]
PublicKey = <client-public-key>
AllowedIPs = 10.8.0.2/32
PersistentKeepalive = 25
```

| Option | Use when | Notes |
|---|---|---|
| WireGuard | Site-to-site, remote access | In kernel; minimal config; UDP only |
| OpenVPN | Legacy peers, TCP/443 fallback | Userspace, heavier, mature ecosystem |
| SSH `-L`/`-R` | Ad-hoc forwarding | No persistent routing; great for debugging |
| SSH `-D` | SOCKS proxy | Combine with browser/app proxy config |
| Tailscale/Headscale | Mesh, identity-based access | Control plane dependency; ACLs matter |
| IPsec | Standards-mandated site links | Complex; strong interoperability |

```bash
wg show; wg-quick up wg0
ssh -N -L 8080:internal:80 jump-host       # local forward
ssh -N -R 9000:localhost:9000 public-host  # remote forward
ssh -D 1080 -N jump-host                    # SOCKS5 proxy
```

- `AllowedIPs` doubles as routing: on the client, `0.0.0.0/0` routes all traffic (full
  tunnel); narrow ranges are split tunnel. Be explicit.
- WireGuard has no built-in user auth; distribute keys per device, rotate, and revoke by
  removing peers. Keep private keys in files with mode `600`.
- MTU: WireGuard overhead is ~60 bytes over IPv4; set `MTU = 1420` for typical 1500
  paths and lower for PPPoE/tunnel stacks. Wrong MTU causes hangs, not total failure.
- Firewall the tunnel interface itself: peers can reach whatever the host allows on
  that interface. Restrict with nft input rules on `wg0`.
- SSH tunnels die silently; use `ServerAliveInterval`, `ExitOnForwardFailure yes`, and a
  supervisor (systemd/AutSSH) for persistent tunnels.
- Do not route production traffic through ad-hoc tunnels; use them to diagnose and
  migrate, not as permanent infrastructure.

## Proxy Debugging

```bash
env | grep -i proxy
curl -v --proxy http://proxy:3128 https://example.com/
curl --noproxy '*' https://internal.example/
openssl s_client -proxy proxy:3128 -connect example.com:443
```

- `http_proxy`, `https_proxy`, `no_proxy` (and `HTTP_PROXY` variants) are honored by
  many tools but not all; `curl`, `wget`, `git`, package managers, and language
  runtimes each have their own precedence. Check per tool.
- `NO_PROXY` matching is suffix-based and inconsistent; list hosts explicitly when in
  doubt.
- HTTPS through a proxy uses `CONNECT host:443`; failures show up as 403/407 or tunnel
  resets in `curl -v`. A TLS error through a proxy often means TLS interception with an
  untrusted CA.
- Corporate TLS inspection requires installing the interception CA in the system trust
  store and every runtime's bundle (Java `cacerts`, Python `certifi`, Node
  `NODE_EXTRA_CA_CERTS`). This is a frequent cause of "works in browser, fails in
  code".
- Diagnose with `mitmproxy`/`proxychains` locally; verify what the proxy sees by
  capturing with `tcpdump` on the proxy path.
- Authenticated proxies need credentials; avoid embedding them in env vars on shared
  hosts, prefer credential helpers or per-tool config files with `600` permissions.

## Anti-Patterns

- Restarting the network stack (`systemctl restart NetworkManager`) as a first step;
  it drops your remote session and hides evidence.
- `iptables -F` on a remote host without a rollback plan or out-of-band console.
- Turning off the firewall to prove a theory instead of capturing traffic.
- Disabling TLS verification (`curl -k`, `NODE_TLS_REJECT_UNAUTHORIZED=0`) in
  production code.
- Editing `resolv.conf` by hand on hosts where systemd-resolved or DHCP overwrites it.
- `chmod 666` on `/etc/resolv.conf`, or installing wildcard certificates to dodge
  per-host names.
- Trusting `ping` alone: ICMP may be filtered while services work, or vice versa.
- Leaving `tcpdump` running unbounded or capturing to a full disk.
- Full-tunnel VPNs pushed to servers without exempting management paths.

## Checklist

- [ ] Diagnose in layers; record evidence at each step before changing anything.
- [ ] DNS: correct resolver path verified (`resolvectl`/`scutil`/`ipconfig`), TTLs
      planned before migrations, split-horizon tested from both sides.
- [ ] TLS: chain and SAN validated, expiry monitored 30/14/7 days, TLS 1.2+ only.
- [ ] Firewall: default drop, established/related accepted, rules persisted and diffed.
- [ ] Remote access: keys only, tunnels supervised with keepalives.
- [ ] MTU verified for tunnels/VPN (no silent large-packet black holes).
- [ ] Proxy settings exported per tool, not assumed universal; `NO_PROXY` explicit.
- [ ] Captures saved as pcap for evidence, bounded in size and time.
- [ ] Changes to routing/firewall done with console access and a rollback path.

Related: [Linux administration](./02-linux-admin.md) for persistence and units,
[performance](./07-performance-tuning.md) for throughput work,
[hardening](./09-security-hardening.md) for firewall and remote-access defaults.
