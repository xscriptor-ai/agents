# Storage and Filesystems

Planning, operating, and recovering storage: filesystem selection, NVMe, RAID, LVM, ZFS/btrfs, backups, and capacity/inode monitoring.

## Filesystem Decision Table

| Need | Choice | Why | Watch out |
|---|---|---|---|
| General-purpose root/data on Linux | ext4 | Mature, predictable, online resize up | No built-in checksums/snapshots |
| Large files, parallel I/O, big filesystems | XFS | Scales well, online grow, good allocator | Cannot shrink; needs `ftype=1` for overlayfs |
| Snapshots, subvolumes, compression | btrfs | Integrated CoW, easy rollback | Free-space accounting, balancing, RAID5/6 caveats |
| Data integrity, compression, send/recv replication | ZFS | End-to-end checksums, ARC, datasets | RAM needs, licensing/distro packaging, no easy shrink |
| Shared network storage | NFS/SMB | Multi-client convenience | Locking, permissions mapping, single point of failure |
| Databases | Depends: ext4/XFS local NVMe; ZFS with tuned recordsize | Latency and fsync semantics dominate | Disable CoW per-dataset only when justified |
| Object storage | S3-compatible or Ceph RGW | Durability at scale | Not a filesystem; app changes required |

- Choose per dataset, not per host: a ZFS/btrfs pool can host an ext4-formatted VM image
  or an XFS volume if that is what the workload wants.
- Do not enable ZFS dedup casually; it is RAM-hungry and usually slower than expected.
  Compression (`lz4`/`zstd`) is cheap and almost always worth it.
- btrfs RAID5/6 have historically been unsafe for certain failure modes; verify current
  upstream status before relying on them. Prefer RAID1/RAID10 with btrfs.
- Windows servers: NTFS remains standard; ReFS offers integrity streams and block
  cloning for virtualization. Verify feature support on your release.

## Block Devices and NVMe

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,MODEL
blkid; findmnt --verify
nvme list; nvme smart-log /dev/nvme0
nvme error-log /dev/nvme0 | head -50
smartctl -a /dev/nvme0; smartctl -a /dev/sda
hdparm -I /dev/sda | grep -i trim
fstrim -av                             # weekly is typical; check systemd fstrim.timer
```

| Metric | Where | Warning sign |
|---|---|---|
| Percentage used | `nvme smart-log` | > 80-90% of rated endurance |
| Media errors | `smartctl -a` / `nvme error-log` | Any growth |
| Available spare | NVMe SMART | Collapsing spare pool |
| Reallocated sectors | SATA SMART | Non-zero growth |
| Temperature | SMART | Above vendor spec under load |
| Unsafe shutdowns | NVMe | Power-loss exposure; check PSU/UPS |

- `fstrim.timer` (systemd) or a cron job handles periodic TRIM; online discard
  (`discard` mount option) adds per-delete latency and is generally not recommended on
  busy servers.
- NVMe wear is uneven with small random writes; over-provisioning and steady-state
  testing matter for write-heavy databases.
- Device names (`/dev/nvme0n1`, `/dev/sda`) are not stable; use `UUID=`/`LABEL=` in
  `/etc/fstab` or `/dev/disk/by-id/`.
- `SMART` self-tests do not prove a drive is healthy; monitor growth trends, not just
  pass/fail. Centralize SMART metrics.
- Plan for die/device failure: NVMe devices fail as whole units, and firmware bugs are
  real; keep firmware current per vendor advisories.

## Partitioning

```bash
parted -s /dev/sdb mklabel gpt
parted -s /dev/sdb mkpart primary 1MiB 100%
sgdisk -n 1:2048:+512M -t 1:ef00 /dev/sdb     # EFI system partition
wipefs -a /dev/sdb                             # clear old signatures before reuse
```

- GPT is the standard; keep a 1 MiB alignment for performance and a small BIOS boot or
  EFI partition where needed.
- `wipefs -a` before reusing disks avoids stale RAID/LVM/filesystem signatures that make
  the kernel assemble ghosts.
- Partition tables are metadata: back up with `sgdisk --backup` before risky operations.
- Whole-disk use (no partition table) is normal for ZFS vdevs and many LVM PVs; match
  the tool's recommendation.

## LVM

```bash
pvs; vgs; lvs -a -o +devices
pvcreate /dev/sdb1; vgcreate data /dev/sdb1
lvcreate -L 100G -n appdata data
lvextend -r -L +50G /dev/data/appdata        # -r resizes the filesystem too
lvcreate -s -L 10G -n appdata-snap /dev/data/appdata
lvs -S 'lv_name=~snap'
```

| Feature | Use | Limit |
|---|---|---|
| Linear LV | Simple aggregation of disks | One disk failure can lose the LV |
| Striping | Throughput across disks | Worse failure exposure; no redundancy |
| Mirroring | Simple redundancy | Costly; RAID tools may be better |
| Snapshots (thick) | Short-lived backup windows | Full-size CoW penalty as they fill |
| Thin pools | Overprovisioning, many snapshots | Pool exhaustion takes down all volumes |
| Cache (SSD) | Warm data acceleration | Complexity; tiering needs monitoring |
| `pvmove` | Migrate extents off a disk | Slow; run in maintenance windows |

- Set `-r` when extending so the filesystem grows in the same command; XFS growth is
  online, ext4 supports online grow.
- Snapshot space is consumed by writes to the origin, not by the snapshot copy; a full
  snapshot invalidates itself. Always monitor snapshot fill.
- Thin pools expose `data_percent` and `metadata_percent`; both can kill the pool.
  Alert well before 100% and never let metadata exceed ~75%.
- Do not shrink: shrinking LVs/filesystems is error-prone; restore from backup instead.
- LVM on top of mdadm is common; LVM RAID (`lvconvert --type raid1`) is an alternative
  with tighter integration but fewer recovery tools.

## RAID

```bash
cat /proc/mdstat
mdadm --detail /dev/md0
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb1 /dev/sdc1
mdadm /dev/md0 --fail /dev/sdb1 --remove /dev/sdb1
mdadm /dev/md0 --add /dev/sdd1
echo check > /sys/block/md0/md/sync_action   # scrub
```

| Level | Redundancy | Capacity | Use |
|---|---|---|---|
| 0 | None | N | Scratch/performance only |
| 1 | 1 disk | N/2 | OS disks |
| 5 | 1 disk | N-1 | Budget bulk; slow rebuilds |
| 6 | 2 disks | N-2 | Bulk with larger disks |
| 10 | 1 per mirror pair | N/2 | Databases and busy workloads |

- Rebuilds are read-intensive and long; degraded arrays have a second-failure window.
  Never rebuild large arrays without a tested backup from the last 24 hours.
- Regular scrubs catch latent bad blocks before a rebuild needs them. Schedule monthly
  for HDD, more often for NVMe if supported.
- RAID is not backup: it protects availability, not accidental deletion or corruption.
- Hardware RAID controllers hide errors; monitor with vendor tools and keep batteries/
  cache modules healthy. Prefer JBOD + software RAID/ZFS where practical.
- ZFS RAIDZ and btrfs RAID are filesystem-integrated; do not stack mdadm under them.

## ZFS

```bash
zpool create tank mirror /dev/disk/by-id/nvme-A /dev/disk/by-id/nvme-B
zpool status -v; zpool list -v; zfs list -o space
zfs set compression=zstd ashift=12 atime=off tank
zfs create -o recordsize=16K tank/db
zfs snapshot tank/data@2026-09-22
zfs send -i tank/data@old tank/data@new | ssh host zfs receive backup/data
zpool scrub tank
zpool trim tank
```

| Property | Guidance |
|---|---|
| `ashift=12` | 4K sectors; set at pool creation, cannot change later |
| `recordsize` | 128K general; 8-16K for databases; 1M for large media |
| `compression` | `lz4` or `zstd`; nearly free, improves write amplification |
| `atime=off` | Fewer writes; only enable where required |
| `xattr=sa` | Better performance/metadata for ACL workloads |
| `sync=standard` | Keep; `sync=disabled` risks data on power loss |
| `copies=2` | Metadata resilience on single-disk pools |

- ARC is RAM-hungry by design; size with `zfs_arc_max` and monitor hit rate, not just
  free RAM. Linux ARC interacts with the page cache poorly if over-limited.
- Scrub monthly; watch `zpool status` for `CKSUM`, `READ`, `WRITE`, `CKS` errors and
  replacement in progress. `zpool status -v` lists damaged files.
- Dedup tables are catastrophic to lose; if used, mirror the dedup device and monitor
  its size via `zdb -DD`. Default answer remains no.
- Snapshots are not backups: they share the pool and disappear with it. Use
  `zfs send`/`recv` or a tool like sanoid/syncoid for real replication.
- Pool `capacity` above ~80% degrades allocation; keep headroom and alert earlier.
- Verify distro packaging/version; feature flags limit pool portability across releases.

## btrfs

```bash
mkfs.btrfs -L data /dev/sdb
btrfs subvolume create /mnt/data/@app
btrfs subvolume snapshot -r /mnt/data/@app /mnt/data/snapshots/app-$(date +%F)
btrfs filesystem usage -T /mnt/data
btrfs scrub start -B /mnt/data
btrfs device stats /mnt/data
btrfs subvolume snapshot -r / /mnt/snapshots/root-$(date +%F)
```

- Layout with subvolumes (`@`, `@home`, `@snapshots`) enables rollback of root without
  touching user data. Mount subvolumes explicitly in `/etc/fstab` with `subvol=`.
- `btrfs filesystem df`/`usage` shows data, metadata, and system chunks separately;
  "df says 50% but writes fail" is usually metadata exhaustion.
- Balancing reclaims unevenly allocated chunks; `btrfs balance start -dusage=50` is a
  targeted approach. Unfiltered full balances are long and can be risky on full disks.
- Scrub verifies checksums and repairs from mirrors; monitor device stats for growing
  `read/write/checksum` errors.
- Send/receive replicates snapshots; incremental streams are efficient but the
  parent-child chain must be intact.
- RAID1 for metadata and data is the safe choice; avoid RAID5/6 without verifying
  current upstream guidance.

## Mount Options and Tuning

| Mount option | Effect | When |
|---|---|---|
| `noatime` | No access-time writes | Almost always on servers |
| `relatime` | Coarse atime (kernel default) | Default is fine |
| `discard` | Online TRIM | Avoid; use `fstrim.timer` |
| `nofail` | Boot continues if missing | Data/external volumes |
| `x-systemd.automount` | Mount on first access | Removable/occasional paths |
| `compress=zstd` (btrfs) | Transparent compression | CPU headroom available |
| `errors=remount-ro` (ext4) | Fail safe after I/O errors | Default hardening |

- Test `/etc/fstab` changes with `findmnt --verify` and `mount -a` before rebooting; a
  broken fstab lands the host in emergency mode.
- `nofail` plus `x-systemd.device-timeout=` prevents boot hangs on missing SAN/NFS.
- NFS tuning: `vers=4.2`, `hard`, `timeo`, `retrans`, `noatime`; `soft` mounts risk
  silent corruption. Use `autofs` for on-demand mounts.
- Network filesystems need their own timeout and reconnect strategy; an unreachable NFS
  server can hang processes uninterruptibly (D state) and block shutdown.

## Backups: 3-2-1 and Restore

| Layer | Example | Frequency |
|---|---|---|
| Local snapshot | ZFS/btrfs/LVM snapshot | Hourly for fast rollback |
| Local backup repository | restic/borg to attached disk | Daily |
| Offsite copy | Object storage via restic/rclone | Daily, encrypted |
| Immutable/versioned | Object lock, append-only repo | Retention per policy |
| Restore test | Full or sampled restore | Quarterly |

```bash
restic -r s3:s3.example.com/backups init
restic -r s3:s3.example.com/backups backup /srv --exclude-caches
restic snapshots; restic check --read-data-subset=5%
restic restore latest --target /tmp/restore --include /srv/app
borg init --encryption=repokey-blake2 ssh://backup@host/./repo
borg create ::'{host}-{now}' /srv; borg check --verify-data
```

- The 3-2-1 rule: 3 copies, 2 different media, 1 offsite. Modern practice adds "1
  offline/immutable" for ransomware resilience.
- Encryption keys are the single point of failure for encrypted repos: escrow them
  separately from the backups. Losing the passphrase loses the data.
- Versioning/retention: prune with grandfather-father-son policies and test that pruned
  data is no longer needed. Untested retention is a guess.
- Snapshots on the same pool/array are not backups; corruption and deletion propagate.
- Monitor backup job exit status and staleness, not just "the job ran". Alert if the last
  successful snapshot is older than the policy.
- Restore drills: restore a real service and verify data checksums. Document RTO/RPO
  and test against them.
- Database backups need consistency: dump with `pg_dump`/`mysqldump`/`.backup` or
  filesystem snapshots coordinated with the DB, not raw file copies of live files.
- Immutability: object lock, append-only Borg repos, or offline rotation defeat
  credential theft. Test that deletion actually fails.

## Capacity and Inode Monitoring

```bash
df -h; df -i
findmnt -o TARGET,FSTYPE,SIZE,USED,AVAIL,USE%
du -xhd1 /var | sort -h | tail
ncdu /var                              # interactive offline analysis
lsof +L1 | head                        # deleted-but-open files holding space
```

- Alert on both space and inode percentage; inode exhaustion breaks writes while `df -h`
  shows free space (classic on mail spools, session dirs, and many-small-files workloads).
- Reserved blocks (`tune2fs -m 1`) matter on large ext4 volumes; 5% of 10 TB is 500 GB.
- Deleted-but-open files keep space allocated; find with `lsof +L1` and restart the
  holder rather than rebooting.
- Thin pools and snapshots fail writes before the underlying device is full; monitor the
  abstraction (`vgs --units g`, `zpool list`, `btrfs filesystem usage`), not raw `df`.
- Growth forecasting: track daily delta and alert on time-to-full, not just threshold.
  Sudden log growth usually means a runaway service or verbose debug flag.
- Quotas (project quotas on XFS/ext4 with `prjquota`, ZFS `refquota`, btrfs `qgroup`)
  contain noisy tenants; test enforcement before production.

## Anti-Patterns

- RAID as a backup strategy; snapshots as offsite backups.
- `dd` from a live database for backups without consistency controls.
- Extending a filesystem without checking the underlying LV/pool/array free space.
- Full btrfs balance or md rebuild on a Sunday morning "to be safe".
- ZFS dedup without RAM sizing and mirrored dedup devices.
- Ignoring SMART growth and NVMe percentage-used until failure.
- Running databases on NFS without verifying fsync semantics and vendor support.
- Storing encryption keys next to the backup repository.
- Letting root or `/var` reach 100%; reserving blocks and alerting at 80%.
- Using `discard` mount option on busy databases instead of scheduled `fstrim`.

## Checklist

- [ ] Filesystem choice documented per workload with rationale.
- [ ] Stable device identifiers (`by-id`/UUID) used in fstab and pool configs.
- [ ] `fstrim.timer` (or equivalent) active; NVMe SMART monitored centrally.
- [ ] RAID/LVM/ZFS/btrfs configured with redundancy appropriate to the data.
- [ ] Scrubs scheduled; pool/array state alerted.
- [ ] Snapshots defined with retention; not confused with backups.
- [ ] 3-2-1 backups verified by restore drills; keys escrowed separately.
- [ ] Space AND inodes monitored with growth forecasting on every filesystem.
- [ ] fstab changes validated with `findmnt --verify`; `nofail` on non-boot volumes.
- [ ] Database backup method matches consistency requirements.

Related: [Linux administration](./02-linux-admin.md) for units and timers,
[performance](./07-performance-tuning.md) for I/O saturation, and
[containers](./08-containers-os.md) for image/layer storage.
