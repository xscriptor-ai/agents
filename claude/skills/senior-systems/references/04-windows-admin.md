# Windows Administration

Automating and operating Windows hosts: PowerShell 7, winget, WSL2, Task Scheduler, services, Event Log, and basic Active Directory.

## Platform Landscape (2026)

| Product | State | Notes |
|---|---|---|
| Windows 11 | 24H2/25H2-era annual releases | Current consumer/business client line |
| Windows 10 | End of standard support reached (Oct 2025) | ESU or upgrade required; verify ESU terms upstream |
| Windows Server | 2019, 2022, 2025 lines | LTSC; verify mainstream support windows upstream |
| PowerShell | 7.4 LTS line and later 7.x stable lines | Windows PowerShell 5.1 remains inbox; 7.x is the automation target |
| WSL | WSL2 with a Microsoft kernel | Distro comes from the Store; systemd supported |
| Package manager | winget | Chocolatey/Scoop remain niche but useful |

- Windows 10 EOL drives most 2026 migration work; inventory before planning.
- Prefer PowerShell 7 for new automation: cross-platform, faster, better `ForEach-Object
  -Parallel`, native SSH remoting. Keep 5.1-compatible scripts only where required by
  inbox-only servers.
- Update strategy: Windows Update for Business, WSUS, or a patch management tool;
  monthly cumulative updates plus out-of-band advisories. Track build numbers, not just
  marketing versions.

## PowerShell 7 Patterns

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true   # 7.3+: native exit codes become errors

function Get-DiskReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ComputerName,
        [ValidateRange(1, 100)][int]$Threshold = 10
    )
    process {
        foreach ($name in $ComputerName) {
            Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $name |
                Where-Object { $_.DriveType -eq 3 } |
                Select-Object @{n = 'Host'; e = { $name } }, DeviceID,
                    @{n = 'FreeGB'; e = { [math]::Round($_.FreeSpace / 1GB, 1) } },
                    @{n = 'TotalGB'; e = { [math]::Round($_.Size / 1GB, 1) } }
        }
    }
}
```

| Pattern | Do | Avoid |
|---|---|---|
| Error handling | `-ErrorAction Stop`, `try/catch`, `$ErrorActionPreference` | `$?` checks after every call |
| Pipeline | Emit objects; filter with `Where-Object` | String parsing with `Select-String` |
| Output | Return objects; format at the edge | `Write-Host` for data |
| Parameters | `[CmdletBinding()]`, typed, validated | `$args` and positional guessing |
| Idempotence | `Test-Path`, `Get-*`/`Set-*`, desired-state checks | Blind `New-*` on every run |
| Credentials | `PSCredential`, managed identity, Windows Hello | Plaintext or argv passwords |
| Remoting | `Invoke-Command` over WinRM/SSH | PsExec for everything |
| Modules | Version-pinned modules, `Install-Module -Scope AllUsers` | Unpinned gallery installs |

- `$PSNativeCommandUseErrorActionPreference` (7.3+) makes non-zero exit codes from native
  tools throw under `Stop`; without it, native failures pass silently.
- `Set-StrictMode -Version Latest` catches uninitialized variables and bad property
  access; add it to every non-trivial script.
- `Get-CimInstance` replaces `Get-WmiObject` (removed in 7). CIM cmdlets support
  `-ComputerName` and DCOM/WinRM sessions.
- Approved verbs only (`Get-Verb`); `-WhatIf`/`-Confirm` via `SupportsShouldProcess`.
- Classes and `using namespace` work in 7 but for reusable code prefer modules with a
  `.psd1` manifest and semantic versioning.
- Test with Pester 5: `Describe`/`Context`/`It`, `Should -Be`, `Mock` for external
  calls; run in CI with `Invoke-Pester -CI`.
- Script signing: production scripts are signed (Authenticode) and execution policy is
  `RemoteSigned` or `AllSigned`; execution policy is not a security boundary, AppLocker
  or WDAC is.
- `$PSStyle` (7.2+) controls ANSI colors; disable formatting for logs.

## winget

```powershell
winget search --name git
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
winget list --upgrade-available
winget upgrade --all --include-unknown
winget export -o packages.json
winget import -i packages.json --accept-package-agreements
winget configure -f config.dsc.yaml     # WinGet Configuration (DSC-based)
```

- `--id` plus `-e` (exact) avoids fuzzy-match installs of the wrong package.
- Machine-wide installs require an elevated shell; per-user installs do not. Decide per
  package and document it.
- winget is not installed on older Windows Server builds by default; bootstrap from the
  App Installer package or use Chocolatey where winget is unavailable.
- `winget configure` applies DSC v3-style YAML documents; treat the YAML as the source
  of truth for developer/workstation baselines.
- Private repositories and internal package sources are supported; prefer them for
  controlled software distribution.
- Chocolatey (`choco install`, `choco upgrade all`) remains useful for servers and
  automation-heavy environments; pin versions and review community package scripts.

## WSL2

```ini
# %UserProfile%\.wslconfig  (global, per user)
[wsl2]
memory=8GB
processors=4
swap=2GB
networkingMode=mirrored
firewall=true
[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

```ini
# /etc/wsl.conf  (inside the distro)
[boot]
systemd=true
[interop]
appendWindowsPath=false
[automount]
options="metadata,umask=22,fmask=11"
```

```powershell
wsl --install -d Ubuntu
wsl -l -v
wsl --shutdown
wsl --export Ubuntu D:\backups\ubuntu.tar
wsl --import Ubuntu2 D:\wsl\ubuntu2 D:\backups\ubuntu.tar --version 2
```

- WSL2 is a real Linux kernel in a lightweight VM: systemd, cgroups v2, and containers
  work inside it. WSL1 is legacy; avoid for new work.
- `networkingMode=mirrored` (Windows 11 22H2+) gives localhost and LAN parity with the
  host; classic NAT mode requires `localhostForwarding` and separate firewall rules.
- WSL distro files live in a VHDX; `wsl --shutdown` before backup/copy, then export or
  copy the VHDX. Backups are the user's responsibility.
- Cross-filesystem performance: operating on files under `/mnt/c` is slow. Keep project
  files in the Linux filesystem (`~/`) and reach them from Windows via `\\wsl$`.
- `appendWindowsPath=false` prevents Windows PATH pollution in Linux shells; call
  `powershell.exe`/`cmd.exe` explicitly for interoperability.
- Time drift after host sleep is corrected by `wsl --shutdown`/restart; NTP inside the
  distro may not fix the VM clock.
- WSL is supported on Windows 10 21H2+ and Windows 11/Server 2022+; verify host build
  before standardizing.
- GPU (CUDA/WSLg) and USB (usbipd-win) passthrough are supported but version-sensitive;
  verify upstream prerequisites.

## Task Scheduler

```powershell
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument '-NoProfile -File C:\ops\sync.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 3am
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'Ops Sync' -Action $action `
    -Trigger $trigger -Principal $principal -Settings $settings -Force

Get-ScheduledTask -TaskName 'Ops Sync' | Get-ScheduledTaskInfo
Start-ScheduledTask -TaskName 'Ops Sync'
Disable-ScheduledTask -TaskName 'Ops Sync'
```

- `schtasks /query /tn "Ops Sync" /xml` is the legacy path; the `*-ScheduledTask`
  cmdlets are preferred and map 1:1 to the XML.
- `-StartWhenAvailable` is the catch-up equivalent of systemd `Persistent=true`.
- Principal matters: `SYSTEM` for machine-wide work, a service account for network
  access (SYSTEM lacks network credentials on other hosts), interactive users for GUI.
- `MultipleInstances` controls overlap: `IgnoreNew` prevents pileups, `Queue` queues.
- Actions run with the working directory `System32` by default; set `-WorkingDirectory`.
- Task history lives under `Microsoft-Windows-TaskScheduler/Operational`; enable it
  explicitly, it is off by default.
- Store scripts on a path the principal can read; SYSTEM cannot see user-mapped drives.

## Services

```powershell
Get-Service | Where-Object Status -eq 'Running'
New-Service -Name 'MyApp' -BinaryPathName '"C:\Program Files\MyApp\app.exe" --service' `
    -DisplayName 'My App' -StartupType Automatic -Description 'API worker'
sc.exe failure MyApp reset= 86400 actions= restart/5000/restart/10000/none/0
Restart-Service MyApp
Get-CimInstance Win32_Service -Filter "Name='MyApp'" | Select State, StartMode, PathName
```

- Native Windows services must implement the Service Control Handler or use a wrapper
  (WinSW, NSSM) for ordinary executables. A plain console app will time out at startup.
- Recovery policy (`sc.exe failure`) is the restart-on-failure equivalent; set it
  explicitly, the default does nothing.
- Service accounts: prefer virtual accounts (`NT SERVICE\MyApp`, gMSA) over `LocalSystem`
  or shared passwords. Grant only required privileges and file rights.
- Delayed start avoids boot-time contention: `sc.exe config MyApp start= delayed-auto`.
- Service start timeout (default 30s) is configurable per service; fix slow startup
  rather than extending blindly.

## Event Log

```powershell
Get-WinEvent -LogName System -MaxEvents 50 |
    Where-Object LevelDisplayName -in 'Error', 'Critical' |
    Format-Table TimeCreated, Id, ProviderName, Message -Wrap

$filter = @{ LogName = 'Application'; Level = 1, 2
             StartTime = (Get-Date).AddDays(-1) }
Get-WinEvent -FilterHashtable $filter |
    Group-Object Id, ProviderName | Sort-Object Count -Descending

wevtutil qe Security /q:"*[System[(EventID=4625)]]" /f:text /c:20
wevtutil epl System C:\diag\system.evtx        # export for offline analysis
```

- `Get-WinEvent -FilterHashtable` is server-side filtering (fast); `Where-Object` is
  client-side (slow) — filter first, format later.
- Event ID landmarks: 4624/4625 logon success/failure, 4672 special privileges, 4688
  process creation (requires audit policy), 7045 service installed, 6008 unexpected
  shutdown, 1074 clean shutdown/restart reason.
- Audit policy must be enabled for Security events (4688, 4697, etc.): `auditpol /get
  /category:*`; set via GPO or `auditpol /set`.
- Log sizes are capped; increase with `wevtutil sl System /ms:104857600` for busy hosts.
- Centralize with Windows Event Forwarding (WEF) or an agent; local logs are lost on
  disk failure and rolled over quickly.

## Active Directory Basics

```powershell
Import-Module ActiveDirectory
Get-ADUser -Filter "Enabled -eq 'True'" -Properties LastLogonDate |
    Sort-Object LastLogonDate | Select-Object -First 20 Name, LastLogonDate
Get-ADGroupMember 'Domain Admins' | Select Name, SamAccountName
Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' -Properties OperatingSystem |
    Group-Object OperatingSystem
Search-ADAccount -AccountDisabled -UsersOnly | Select Name, SamAccountName
gpresult /h gpo-report.html; gpupdate /force
```

- RSAT (`Install-WindowsFeature RSAT-AD-PowerShell` or the Windows capabilities) is
  required; install on admin workstations, not servers, where possible.
- LDAP queries against a Domain Controller for read-heavy tasks; the AD module is a
  wrapper. Use paging and filters, never enumerate the whole domain.
- Kerberos: SPNs must be unique; `setspn -L account` audits registration. Clock skew
  beyond 5 minutes breaks authentication; ensure W32Time/PDC synchronization.
- Group Policy preferences can embed credentials (cpassword) — audit and eliminate.
  LAPS for local admin passwords, tiered administrative model for privileged accounts.
- Entra ID (hybrid/cloud) increasingly holds identity; sync via Entra Connect, and
  treat conditional access as the control plane for cloud apps.
- Recycle Bin, fine-grained password policies, and protected users group are baseline
  hygiene items to verify, not assume.

## Anti-Patterns

- Using Windows PowerShell 5.1 idioms in 7 (`Get-WmiObject`, `Measure-Command ||`, etc.)
  without a compatibility reason.
- `Write-Host` for data or logging; it bypasses the pipeline and cannot be suppressed.
- `Invoke-Expression` on strings; it is arbitrary code execution.
- Storing credentials in scripts or Scheduled Task arguments.
- Using SYSTEM for tasks that need network resource access.
- Assuming winget is present on servers, or that Store apps install in audit/SYSTEM
  contexts.
- Editing the registry with `reg add` when a cmdlet, GPO, or DSC resource exists.
- Treating execution policy as a security boundary.
- Editing files under `C:\Windows` or using `takeown`/`icacls` to force permissions.

## Checklist

- [ ] Windows 10 inventory complete; ESU/upgrade path decided.
- [ ] PowerShell 7 deployed; modules version-pinned and signed scripts where required.
- [ ] winget/Chocolatey baseline captured as code (YAML/Brewfile-equivalent).
- [ ] WSL2 configured with `.wslconfig` and `/etc/wsl.conf`; backups exported.
- [ ] Scheduled tasks use explicit principals, settings, and start-when-available.
- [ ] Services have recovery policy and least-privilege accounts.
- [ ] Event log sizes raised; Security auditing enabled per baseline; logs forwarded.
- [ ] AD privileged groups reviewed; LAPS and tiered admin understood.
- [ ] Patch cadence defined (WUfB/WSUS) with reboot windows.
- [ ] Backups for host state, not just data; restore tested.

Related: [security hardening](./09-security-hardening.md) for account and patch
baselines, [storage](./06-storage-filesystems.md) for volume and backup planning.
