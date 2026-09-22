# macOS Administration

Administering and automating Macs: launchd, Homebrew, SIP/Gatekeeper, `defaults`, configuration profiles, TCC privacy, and APFS quirks.

## Platform Landscape (2026)

| Topic | State | Notes |
|---|---|---|
| Current release line | macOS 26 (2025 naming scheme) | Verify the exact current version and support matrix upstream |
| Still-supported older lines | Typically current and two prior | Apple publishes security update scope per release |
| Hardware | Apple silicon (M-series) is the default | Intel Macs only on older supported releases |
| Scripting shell | zsh 5.x at `/bin/zsh`; bash 3.2 at `/bin/bash` | Never assume bash 4+ features in system scripts |
| Package manager | Homebrew on Apple silicon at `/opt/homebrew` | Intel path `/usr/local`; never hardcode both |
| Init/scheduler | launchd (PID 1) | cron exists but is deprecated in practice |

- Apple silicon changed defaults: Homebrew prefix, some paths, and the behavior of
  virtualization; do not port Intel-era scripts blindly.
- System integrity is strict: `/System` is a read-only signed volume, SIP blocks most
  modifications even as root, and third-party kernel extensions are effectively legacy.
- MDM (Jamf, Kandji, Mosyle, Intune) is the supported fleet automation path; scripting
  alone does not scale or survive OS upgrades reliably.

## launchd: Jobs and Services

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.example.sync</string>
  <key>ProgramArguments</key>
  <array><string>/usr/local/bin/sync</string><string>--once</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/var/log/example-sync.log</string>
  <key>StandardErrorPath</key><string>/var/log/example-sync.err</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
</dict>
</plist>
```

```bash
launchctl bootstrap system /Library/LaunchDaemons/com.example.sync.plist
launchctl kickstart -k system/com.example.sync
launchctl print system/com.example.sync
launchctl bootout system/com.example.sync
plutil -lint /Library/LaunchDaemons/com.example.sync.plist
```

| Location | Type | Runs as | Loaded |
|---|---|---|---|
| `/Library/LaunchDaemons` | Daemon | root (or `UserName=`) | Boot, system context |
| `/Library/LaunchAgents` | Agent | logged-in user | User login, all users |
| `~/Library/LaunchAgents` | Agent | owner | That user only |
| `/System/Library/...` | Apple | Apple | Never modify |

- `launchctl load/unload` is legacy; use `bootstrap`/`bootout` with a domain
  (`system`, `gui/<uid>`, `user/<uid>`).
- `KeepAlive` (with optional conditions) restarts on exit; `ThrottleInterval` (default
  10s) prevents crash loops. `StartCalendarInterval` mimics cron.
- launchd jobs get a minimal environment: absolute paths, no `.zshrc`, and `PATH` must
  include Homebrew's `bin` explicitly. This is the top cause of "works in terminal".
- `StartInterval` and `StartCalendarInterval` jobs that miss a wake window do not run;
  the Mac must be awake. `pmset schedule` and `caffeinate` interact with this.
- Logs stdout/stderr to files (launchd does not capture to unified logging for job
  output). Use `log show --last 1h --predicate 'process == "sync"'` for `os_log` output.
- Disable a job without deleting it: `launchctl disable system/com.example.sync`.
- SIP protects `/System`; launchd daemons belong in `/Library/LaunchDaemons`, never
  inside app bundles you modify.

## Homebrew

```bash
brew --prefix                     # /opt/homebrew (arm64), /usr/local (x86_64)
brew install jq gh                # formulae
brew install --cask docker        # GUI apps
brew bundle dump --file Brewfile
brew bundle install --file Brewfile
brew update && brew upgrade && brew cleanup -s
brew services list                # launchd-backed services
brew doctor
brew pin python@3.13
```

- Never run `brew` as root or via `sudo`; it refuses and breaks ownership. Use
  `brew services` (per-user) rather than system daemons for Homebrew software.
- Brewfile is the reproducibility unit for workstations: commit it, install with
  `brew bundle`, and review diffs like any dependency file.
- Homebrew is not a patch-management or MDM replacement; critical software should come
  from managed channels.
- Rosetta runs x86_64 formulae in separate prefixes when needed; prefer native arm64
  bottles and mix only when a dependency requires it.
- `brew bundle cleanup --force` removes packages not in the Brewfile; run with care on
  machines with manual installs.

## SIP, Gatekeeper, Notarization

```bash
csrutil status                       # System Integrity Protection
spctl --status                       # Gatekeeper assessment
xattr -l /Applications/Some.app      # look for com.apple.quarantine
spctl -a -vv --type execute Some.app # why was it blocked
codesign -dv --verbose=4 Some.app    # signature and team ID
codesign --verify --deep --strict Some.app
```

| Control | Blocks | Admin bypass |
|---|---|---|
| SIP | Modification of system paths, code injection | `csrutil disable` from Recovery only; avoid |
| Gatekeeper | Unsigned/unnotarized apps | `spctl --master-disable` weakens the whole machine |
| Notarization | Distribution of un-notarized binaries | Developer staple via `notarytool` |
| Quarantine attribute | First-run of downloaded files | `xattr -d com.apple.quarantine` per-file |

- Production Apple software must be signed with a Developer ID and notarized; verify the
  full chain with `codesign --verify --deep --strict` and `spctl -a -vv`.
- Removing quarantine is a per-file workaround, not a deployment strategy; do not script
  it wholesale.
- MDM can allow specific apps and system extensions; user-approved kernel/system
  extension flows have largely replaced kexts (`systemextensionsctl list`).
- `csrutil authenticated-root` and sealed system volumes mean even root cannot edit
  `/System`; install into `/usr/local` or `/opt` instead.

## defaults, TCC, and Privacy

```bash
defaults read com.apple.dock
defaults write com.apple.dock autohide -bool true && killall Dock
defaults read ~/Library/Preferences/com.example.app.plist
defaults delete com.example.app KeyName
```

- `defaults` writes preferences; some daemons cache values, so restart the app or
  `killall` the relevant process. Per-host managed preferences override user values.
- `defaults` is not a supported configuration mechanism for every setting; Apple may
  change keys between releases. Prefer MDM profiles for anything fleet-wide.
- TCC (Transparency, Consent, Control) gates camera, microphone, screen recording,
  accessibility, and full disk access. Databases are protected by SIP; do not attempt
  to edit them directly.
- `tccutil reset <service> <bundle-id>` resets prompts for testing. End users or MDM
  must grant consent; scripts cannot click the dialogs.
- Full Disk Access must be granted to backup and security tools explicitly; this is a
  common automation blocker.
- Screen recording and accessibility permissions are required for remote-control and
  UI-testing tools; document them in onboarding.

## Configuration Profiles and MDM Basics

```bash
profiles list                        # installed profiles (may need root)
profiles show -type configuration
profiles -I -F profile.mobileconfig  # install manually (dev only)
```

- A `.mobileconfig` profile is a signed plist with `PayloadType` entries
  (`com.apple.security.firewall`, `com.apple.MCX`, `com.apple.SoftwareUpdate`, etc.).
- Profiles can be user-scoped or device-scoped; device profiles require MDM or admin.
- Declarative device management (DDM) is the modern MDM model: the device reports status
  and applies declarations, rather than the server pushing profiles blindly. Verify
  current MDM support upstream.
- Manual `profiles install` is for testing only: unsigned or unreviewed profiles are a
  security risk, and user-installed profiles can be removed by the user unless the
  device is supervised.
- FileVault, firewall, software update deferral, and password policy are the common
  baseline payloads. Keep a written baseline per device class.
- `sudo fdesetup status` confirms FileVault; escrow recovery keys through MDM for
  fleet devices.

## Filesystem Quirks (APFS)

```bash
diskutil list; diskutil apfs list
diskutil info / | grep -E 'File System|Volume Name|Case'
tmutil listlocalsnapshots /
tmutil localsnapshot
tmutil listbackups; tmutil status
mount | grep -E 'apfs|hfs'
```

- APFS is the default and mandatory for boot volumes; HFS+ only remains on some
  external/legacy media.
- Boot volumes are a volume group: a read-only signed `System` volume and a writable
  `Data` volume joined by firmlinks. Paths like `/Users`, `/Applications`, and
  `/private/var` live on the Data volume.
- Default formatting is case-insensitive (case-preserving); code and archives that
  assume case sensitivity must be tested. Some build systems require a case-sensitive
  volume.
- APFS snapshots are instantaneous and cheap, but Time Machine local snapshots
  accumulate and consume space until purged; `tmutil thinlocalsnapshots` frees them.
- `df` output is misleading on APFS: containers share free space, and purgeable space
  is not reported as available until reclaimed. Use `diskutil apfs list` and
  `df -h` together.
- Time Machine to a network destination uses sparse bundles; verify backups with
  `tmutil verifychecksums` and periodic restore drills.
- Extended attributes and resource forks survive on APFS but are lost on FAT/exFAT
  media; zip archives need `--keepResourceFork` equivalents or `ditto` to preserve
  metadata for app bundles.

## Security Baseline

- Enable FileVault, the application firewall (`/usr/libexec/ApplicationFirewall/socketfilterfw
  --getglobalstate`), and automatic security updates where policy allows.
- Track OS version against Apple's security release notes; Macs fall behind silently.
- Audit login items and background items: `sfltool dumpbtm` (privileged), System
  Settings > General > Login Items, and `launchctl print` for stray agents.
- Secure Enclave backs FileVault keys and Touch ID; do not attempt to script around it.
- XProtect and Gatekeeper are not a complete EDR; pair them with MDM and endpoint
  tooling for fleets.

## Anti-Patterns

- `sudo` with Homebrew, or installing Homebrew as root.
- Editing `/System` or TCC databases directly.
- Writing daemons into `~/Library/LaunchAgents` for system-wide services.
- Assuming `cron` behavior; macOS may sleep through scheduled cron/timer runs.
- Hardcoding `/usr/local` or `/opt/homebrew` without detecting `brew --prefix`.
- Parsing `system_profiler` output for structured data when `diskutil -plist` or
  `plutil` provides stable formats.
- Disabling SIP/Gatekeeper to make an unsigned tool run on a managed fleet.
- Ignoring local Time Machine snapshots when diagnosing "disk full".

## Checklist

- [ ] Fleet devices enrolled in MDM; baseline profiles documented and versioned.
- [ ] FileVault on with escrowed recovery key; firewall enabled.
- [ ] Software update policy explicit; deferrals deliberate, not accidental.
- [ ] Homebrew prefix discovered dynamically; Brewfile committed for workstations.
- [ ] LaunchDaemons vs LaunchAgents chosen correctly; labels reverse-DNS.
- [ ] Job `PATH` and filesystem paths absolute; outputs logged to files.
- [ ] Scripts pass `plutil -lint` for plists and `shellcheck` for shell.
- [ ] Full Disk Access and TCC-sensitive tooling granted deliberately.
- [ ] Time Machine or equivalent verified with a restore test.
- [ ] No reliance on deprecated `load/unload` or unsupported `defaults` keys.

Related: [shell scripting](./01-shell-scripting.md) for script hygiene,
[security hardening](./09-security-hardening.md) for cross-platform controls.
