# Performance Tuning

Measuring and improving host performance: perf, eBPF/bpftrace, classic counters, PSI, ulimits, sysctl tuning, memory pressure, and the OOM killer.

## Method Before Tools

1. **Define the symptom** — latency, throughput, errors, or saturation, with a target
   (p99 < 50 ms, 10k rps) and a time window.
2. **Check utilization and saturation** — CPU, memory, disk, network, and file
   descriptors. The USE method (utilization, saturation, errors per resource) finds the
   bottleneck quickly.
3. **Measure at the right layer** — cgroup/container, process, host, or fleet. A noisy
   neighbor is invisible from inside the container.
4. **Establish a baseline** — record before-and-after numbers under comparable load.
5. **Change one variable**, re-measure, and roll back if the change does not help.

- Tuning without measurement is superstition; most sysctl folklore is workload- and
  kernel-version-specific.
- The bottleneck moves: fix CPU and the disk becomes the limit. Expect to iterate.
- Prefer architectural fixes (caching, batching, async, capacity) over parameter tuning.
- Use [observability](../../observability/SKILL.md) practices for long-term visibility;
  this reference is for interactive diagnosis and tuning.

## Load and Saturation Basics

```bash
uptime; cat /proc/loadavg
nproc; lscpu | head -20
cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io
mpstat -P ALL 1 5
pidstat -u -r -d 1 5
```

- Load average counts runnable + uninterruptible (D-state) tasks. With 8 CPUs, a load of
  8 is saturated; a load of 4 with high I/O wait may still be unhealthy because
  D-state tasks inflate it.
- PSI (pressure stall information) is the best single saturation signal: `some` = at
  least one task stalled, `full` = all tasks stalled. Sustained `full` on memory or IO
  means real user-visible pain.
- `vmstat 1`: watch `r` (run queue), `b` (blocked), `si`/`so` (swap), `wa` (I/O wait),
  and `st` (stolen by hypervisor). Stolen time means the host is oversubscribed.
- CPU frequency and thermal throttling can cap performance invisibly:
  `cpupower frequency-info`, `turbostat`, `sensors`.

## perf and ftrace

```bash
perf stat -p PID sleep 5
perf top -g
perf record -F 99 -g -p PID -- sleep 30
perf report --stdio --sort=comm,dso,symbol | head -40
perf trace -p PID
perf sched latency
perf stat -e cache-misses,cache-references,cycles,instructions -p PID sleep 5
```

- `perf record -F 99 -g` samples at 99 Hz with call graphs; 30 seconds of samples is
  enough for a flame graph (`perf script | stackcollapse-perf.pl | flamegraph.pl`).
- Userspace symbols need `-g` at build time and debuginfo packages for accurate frames;
  stripped binaries show only addresses.
- Off-CPU and wakeup analysis: `perf sched`, `offcputime` (BCC), and `perf trace` show
  where threads block, complementing on-CPU profiles.
- `perf stat` counter ratios diagnose microarchitecture issues: high `cache-misses` per
  reference, low IPC, or branch-miss spikes point at data layout or branchy code.
- Tracepoints (`perf list`) are stable; kprobes are kernel-version-sensitive. Prefer
  tracepoints and USDT probes in automation.
- Lock contention: `perf lock`, `futex` tracepoints, and `bcc` tool `offwaketime`.

## eBPF / bpftrace

```bash
# top functions by CPU, 5s
bpftrace -e 'profile:hz:99 /pid == $1/ { @[ustack] = count(); }' 1234

# I/O latency histogram by process
bpftrace -e 'tracepoint:block:block_rq_complete { @us[comm] = hist(args->nr_sector == 0 ? 0 : 0); }'

# syscall counts per process
bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[pid, comm] = count(); } interval:s:10 { print(@); clear(@); }'

# open failures
bpftrace -e 'tracepoint:syscalls:sys_exit_openat /args->ret < 0/ { @[comm, args->ret] = count(); }'
```

| Tool set | Strength | Use |
|---|---|---|
| bpftrace | Ad-hoc one-liners, histograms | Interactive diagnosis |
| BCC tools (`execsnoop`, `opensnoop`, `biolatency`, `tcplife`) | Ready-made scripts | Common questions fast |
| libbpf + CO-RE | Portable production agents | Vendor/monitoring integration |
| `perf` + ftrace | Built-in, no extra packages | When eBPF is unavailable |

- bpftrace needs root or `CAP_BPF`/`CAP_PERFMON`; check `kernel.unprivileged_bpf_disabled`
  and distro policy.
- Kernel version and BTF availability determine which probes work: BTF-enabled kernels
  (mainline distro kernels) support CO-RE; older/custom kernels may not.
- Keep probes bounded: aggregate into maps, avoid printing per-event in hot paths, and
  set `interval`/`timeout` to end collection.
- Overhead is usually low but not zero; measure with and without probes on tight-SLO
  systems.
- eBPF is not a substitute for application tracing; use OpenTelemetry for request-level
  causality.

## Classic Counters

```bash
iostat -xz 1 5
vmstat -w 1 5
pidstat -u -r -d -w 1 5
sar -n DEV 1 5
iotop -oPa
free -h; cat /proc/meminfo | head -20
```

| Tool | Field | Interpretation |
|---|---|---|
| iostat | `r_await`/`w_await` | Per-request latency (ms); the real latency signal |
| iostat | `aqu-sz` | Queue depth; growing means saturation |
| iostat | `%util` | Misleading on NVMe/RAID; near 100% only meaningful for single HDD |
| vmstat | `r`, `b` | Run queue and blocked tasks |
| vmstat | `si`/`so` | Swap in/out; sustained non-zero is memory pressure |
| pidstat | `%CPU`, `%MEM` | Per-process attribution |
| iotop | `IO>` | Live per-process I/O rates |

- Compare latency percentiles, not averages. `%iowait` is a CPU idle state accounting
  artifact, not a disk metric; use it only as a hint.
- Queue depth thresholds depend on the device: SATA/NVMe have very different concurrency
  capabilities. Latency is the universal measure.
- Use `blktrace`/`btt` for deep block-layer analysis, `biolatency` for histograms.
- File-descriptor and connection counts are resources too: `lsof -p PID | wc -l`,
  `ss -s`; exhaustion looks like an application hang.

## Memory: Pressure and Reclaim

```bash
free -h
grep -E 'MemAvailable|Dirty|Writeback|SwapCached' /proc/meminfo
cat /proc/pressure/memory
cat /sys/fs/cgroup/<path>/memory.current /sys/fs/cgroup/<path>/memory.stat
perf stat -e page-faults -p PID sleep 5
slabtop -s c
```

- `free` vs `available`: Linux uses free RAM for page cache; `MemAvailable` is the
  number that matters. "Used" memory near 100% is normal and healthy.
- Reclaim pressure shows as growing PSI `some`/`full` on memory, rising
  `pgscan`/`pgsteal`, and eventually swap activity. Treat those as the alarm.
- Page cache can be dropped only for measurement, not as a fix:
  `echo 3 > /proc/sys/vm/drop_caches` (privileged, global, harmful to performance).
- Dirty page writeback: large `Dirty` values cause latency spikes when the kernel
  flushes. Tune `vm.dirty_ratio`/`vm.dirty_background_ratio` only with evidence; modern
  kernels auto-tune.
- Slab growth (especially `dentry`/`inode`) indicates filesystem churn; `slabtop` and
  `drop_caches` diagnostics, not a steady-state fix.
- Leaks: RSS trending up with flat workload; use `smem`/`pmap`, heap profilers, and
  `/proc/PID/smaps_rollup`. OOM kills often follow a slow leak, not a sudden spike.

## OOM Killer

```bash
dmesg -T | grep -i -E 'oom|killed process'
cat /sys/fs/cgroup/<path>/memory.events
cat /proc/<pid>/oom_score; cat /proc/<pid>/oom_score_adj
systemctl show -p MemoryMax,MemoryHigh,OOMScoreAdjust myapp.service
```

- Global OOM: the kernel picks a victim by `oom_score` (RSS + adjustments). Inside a
  cgroup, the cgroup limit is enforced first and the kill is recorded in `memory.events`.
- `oom_score_adj` ranges -1000 (never kill) to 1000 (kill first). Use sparingly and
  document; protecting everything protects nothing.
- systemd services: `OOMScoreAdjust=`, `MemoryMin=`, `MemoryLow=`, `MemoryHigh=`,
  `MemoryMax=`, `ManagedOOMMemoryPressure=` provide policy beyond the raw killer.
- Diagnose cause before tuning: a container killed at its limit needs more memory or
  fewer allocations, not `MemoryMax=infinity`.
- Kernel OOM messages include the cgroup and `oom-kill` constraints; capture them in
  monitoring before journal rotation loses them.
- Swap is not a fix for leaks; it masks growth and converts memory pressure into I/O
  stalls. Configure swap for hibernation/headroom, not as capacity.

## Limits: ulimits and systemd

```bash
ulimit -a
cat /proc/<pid>/limits
prlimit --pid <pid>
systemctl show myapp.service -p LimitNOFILE -p LimitMEMLOCK -p TasksMax
cat /etc/security/limits.conf; cat /etc/security/limits.d/*.conf
```

| Limit | Symptom when hit | Notes |
|---|---|---|
| `nofile` | `too many open files` | Raise per service, not globally by default |
| `nproc` | fork/thread failures | cgroup `pids.max` also applies |
| `memlock` | eBPF/DPDK/RDMA failures | Needs explicit raise; systemd `LimitMEMLOCK=infinity` |
| `core` | No crash dump | Set `core_pattern` deliberately |
| `stack` | Thread creation failures | Rarely the real problem |
| `max user processes` | Login failures under load | Distinguish from cgroup caps |

- systemd services: limits must be set in the unit (`LimitNOFILE=`, `TasksMax=`);
  `limits.conf` is ignored for services, which do not go through PAM.
- `TasksMax` maps to cgroup `pids.max` and is the correct fork-bomb control.
- Never set `nofile` to unlimited globally on busy hosts; it can exhaust kernel memory.
  Size per service from actual `lsof | wc -l` headroom.
- Inherited limits: a process forked from a shell with raised limits keeps them; this
  hides misconfiguration until a service starts from systemd.

## sysctl Tuning

```bash
sysctl -a | grep -E 'swappiness|somaxconn|tcp_congestion'
sysctl net.core.somaxconn vm.swappiness vm.dirty_background_ratio
sysctl -w net.core.somaxconn=4096            # temporary
# persist in /etc/sysctl.d/99-tuning.conf after review
```

| Key | Typical direction | Cautions |
|---|---|---|
| `net.core.somaxconn` | Raise for busy accept queues | Apps must also use a large backlog |
| `net.ipv4.tcp_max_syn_backlog` | Raise for SYN floods | Interacts with syncookies |
| `net.ipv4.ip_local_port_range` | Widen for high outbound rates | TIME-WAIT exhaustion is the real cause |
| `net.ipv4.tcp_tw_reuse` | Often safe for outbound clients | Do not use `tcp_tw_recycle` (removed) |
| `vm.swappiness` | Lower (1-10) to prefer reclaim | Swapping is still needed under pressure |
| `vm.dirty_ratio`/`dirty_background_ratio` | Lower for latency-sensitive disks | Higher values improve throughput |
| `vm.overcommit_memory` | Leave at 0 | `1` enables OOM surprises |
| `kernel.pid_max` | Raise for many threads | Also check `threads-max` |
| `net.netfilter.nf_conntrack_max` | Raise for NAT/firewall loads | Watch `nf_conntrack_count` |
| `vm.max_map_count` | Raise for some databases/JVMs | Elasticsearch/Neo4j historically needed this |

- Every change is a hypothesis: document the key, reason, value, date, and measurement.
- `sysctl.d` fragments are the persistent mechanism; avoid editing `/etc/sysctl.conf`
  directly on managed hosts.
- Container hosts: many keys are namespaced per network namespace; setting them inside
  a container may not affect the host or may be rejected.
- THP (`transparent_hugepage`) defaults changed across kernels; do not blanket-disable
  or force `always`. Measure with the actual workload (`/sys/kernel/mm/transparent_hugepage/`).
- NUMA: pin latency-critical processes with `numactl --cpunodebind --membind`; check
  `numastat -p PID` for remote memory access before blaming the app.
- CPU governors: `performance` trades power for consistent latency; `schedutil` is
  usually the right default on modern kernels.

## Profiling Workflow (recipes)

| Symptom | First check | Then |
|---|---|---|
| High CPU, app-level | `perf top -g`, flame graph | Optimize hot symbols, check IPC |
| High CPU, kernel-level | `perf top -g -K`, `mpstat` | Syscall/os noise, softirqs, network stack |
| Latency with idle CPU | `offcputime`, `perf sched` | Lock contention, blocking I/O |
| Slow disk writes | `iostat -xz`, `biolatency` | Queue depth, fsync pattern, write amplification |
| Slow network | `ss -i`, `mtr`, `perf stat -e net:*` | RTT/loss, retransmits, buffer sizes |
| Periodic stalls | `vmstat`/PSI over time, `ftrace` | Writeback, timer storms, cron contention |
| Container throttled | `cpu.stat`, `memory.events` | Raise limits or reduce work |

- Record commands and outputs in the incident/ticket; tuning without evidence is
  unverifiable later.
- Benchmark with representative load; microbenchmarks mislead for I/O and network.
- Roll back every tuning change that does not show measurable improvement.

## Anti-Patterns

- `%util` at 100% treated as "disk is dying" on NVMe arrays.
- Raising `nofile` globally to hide an application FD leak.
- `vm.swappiness=0` on a machine that genuinely needs to reclaim anonymous memory.
- Copy-pasting sysctl sets from blog posts without measurement or documentation.
- `echo 3 > drop_caches` as a production remedy.
- Tuning the container while the host/neighbor is saturated.
- Using load average alone to declare CPU saturation on many-core hosts.
- Ignoring PSI and waiting for OOM kills before acting on memory pressure.
- Profiling release binaries without symbols and trusting the resulting graph.

## Checklist

- [ ] Symptom quantified (metric, target, window) before any change.
- [ ] Baseline captured; one variable changed per iteration.
- [ ] PSI checked for CPU, memory, and I/O saturation.
- [ ] Bottleneck attributed to host, cgroup, or process correctly.
- [ ] Limits reviewed in units (`LimitNOFILE`, `TasksMax`), not just `ulimit`.
- [ ] OOM events correlated with cgroup limits and growth trends.
- [ ] Every sysctl/unit change documented with reason and measurement.
- [ ] Changes reverted unless they measurably help.
- [ ] Monitoring/alerts updated for the saturation signal you found.

Related: [Linux administration](./02-linux-admin.md) for cgroups and units,
[storage](./06-storage-filesystems.md) for I/O behavior, and
[networking](./05-networking.md) for transport diagnosis.
