# Shell Scripting (bash, zsh, POSIX sh)

Writing, reviewing, and debugging shell scripts that run unattended: strict mode, quoting, arrays, traps, portability, shellcheck, and bats testing.

## Choosing the Shell

| Target | Interpreter | Why |
|---|---|---|
| Interactive use, complex automation | bash 5.x | Arrays, `[[ ]]`, `mapfile`, `set -o pipefail` |
| macOS login shell / scripts by users | zsh 5.x | Default on macOS; bash there is 3.2 (2007) |
| Must run everywhere (Alpine, BusyBox, dash, CI) | POSIX `sh` | No arrays, no `[[ ]]`, no `pipefail` in strict POSIX |
| Ownership of behavior matters | Pin `#!/usr/bin/env bash` | Avoid `/bin/sh` ambiguity; document the floor |
| Logic is growing past ~200 lines | Python or Go | Shell lacks types, tests, and data structures |

- `#!/usr/bin/env bash` picks up the user's `PATH`; `#!/bin/bash` is deterministic but
  wrong on systems where bash lives elsewhere (NixOS, FreeBSD).
- zsh is not bash: arrays are 1-indexed, `$array` expands all elements, no word splitting
  by default, `setopt` differs. Run `emulate -L sh` or simply write bash when portability
  across the two is required.
- `checkbashisms` (Debian devscripts) flags bash-only constructs in `sh` scripts.

## Strict Mode

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
```

| Option | Effect | Caveat |
|---|---|---|
| `-e` / `errexit` | Exit on unchecked failure | Ignored in `if`, `while`, `&&`, `\|\|` contexts |
| `-u` / `nounset` | Error on unset variable | `"$@"` with no args is fine; `$1` is not |
| `-o pipefail` | Pipeline fails on any stage | Not POSIX; bash/zsh/ksh only |
| `-E` / `errtrace` | `ERR` trap inherited by functions/subshells | Required for useful ERR traps |
| `IFS=$'\n\t'` | Safer word splitting | Omit tab only if you need multi-line reads |

`set -e` caveats worth memorizing:

- Failure inside command substitution aborts only with `set -e` in effect for the
  subshell; `local x=$(false)` returns 0 because `local` masks the status. Split it:
  `local x; x=$(false)`.
- Arithmetic `((i++))` returns 1 when the result is 0 and can abort the script.
  Use `i=$((i + 1))` or `((++i))`.
- `grep pattern file` returns 1 when there are no matches; under `-e` that is fatal.
  Write `if grep -q ...; then` or `grep ... || true` deliberately.
- `read` returning 1 at EOF aborts loops if unguarded: `while read -r line; do ...; done < file`
  fails on the loop condition — use `while IFS= read -r line || [[ -n $line ]]`.
- A function that is meant to return non-zero will kill the caller under `-e` unless the
  call site handles it (`if ! f; then`).

## Quoting and Expansion

```bash
printf '%s\n' "$name" "$@"              # always quote
[[ $path == "$prefix"/* ]] || exit 1    # [[ ]] suppresses splitting, still quote for clarity
out=$(cmd --flag)                       # capture stdout, don't quote $( ) inner args
files=( "$dir"/*.txt )                  # glob into array without word-splitting surprises
cp -- "$src" "$dst"                     # -- ends option parsing for hostile paths
```

| Form | Meaning | Never do |
|---|---|---|
| `"$var"` | Expand, no splitting/globbing | `$var` unquoted |
| `"${var:-default}"` | Default if unset/empty | `$var` with `set -u` |
| `"${var:?message}"` | Abort with message if unset | Silent empty expansion |
| `"${#var}"` | Length | `expr length` |
| `"${var##*/}"` / `"${var%%/*}"` | Basename / dirname without forks | `basename`/`dirname` in hot loops |
| `"${var//pat/repl}"` | Replace all | `sed` for simple substitution |
| `"$@"` | All positional params, one word each | `$*` or `"$*"` unless deliberate |
| `${!prefix@}` | Variable indirection | `eval` |

- Bash expansion order: brace → tilde → parameter/variable → command substitution →
  arithmetic → word splitting → pathname expansion. Quote to suppress the last two.
- `printf` over `echo`: `echo -e` is not portable, `echo` mangles backslashes, and
  `printf '%s\n'` is explicit. Use `printf -v var '%s' ...` to assign.
- `IFS= read -r line` preserves backslashes and leading whitespace; without `-r`, backslash
  escapes are processed.

## Arrays (bash)

```bash
declare -a files=("a b.txt" "c.txt")     # indexed
declare -A seen=([a]=1 [b]=2)            # associative
files+=("d.txt")
for f in "${files[@]}"; do printf '%s\n' "$f"; done
mapfile -t lines < <(journalctl -n 50 -o cat)   # safe line reader
keys=("${!seen[@]}")                     # assoc keys
[[ -v seen[a] ]] && printf 'present\n'   # membership
```

- `${arr[@]}` unquoted splits and globs; `${arr[*]}` joins with `IFS[0]`.
- Sparse arrays iterate indices; `${#arr[@]}` is the count, `${#arr[0]}` is a length.
- Bash 4.3+ supports namerefs: `declare -n ref=$1`, but prefer explicit variables in
  scripts meant to be read by others.
- zsh differs: `"${(@)arr}"` semantics, `$arr[1]` indexing, no associative `declare -A`
  (use `typeset -A`). Prefer bash for array-heavy scripts.

## Functions, Exit Codes, Traps

```bash
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  local rc=$?
  [[ -n ${tmpdir:-} ]] && rm -rf -- "$tmpdir"
  exit "$rc"
}
on_err() { printf 'FAIL line %d: %s\n' "$1" "$2" >&2; }
trap cleanup EXIT
trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR
trap 'echo interrupted; exit 130' INT TERM HUP

tmpdir=$(mktemp -d) || die "mktemp failed"
```

- `EXIT` traps run on every exit path, including `exit` in nested functions; keep cleanup
  idempotent and never `set -e` inside it.
- Signal traps should exit with 128+N (`130` for SIGINT, `143` for SIGTERM) so supervisors
  see the right status. In a container, PID 1 must forward signals or `docker stop` will
  SIGKILL after the grace period.
- `trap - EXIT` removes a handler; re-entry from cleanup is a classic source of double
  deletes.
- Function-local variables require `local` (`declare` inside a function is local to it,
  but `declare` in bash without a function is global). Arrays passed by name are error-prone;
  echo results or use global naming conventions instead.
- Exit codes: reserve `0` success, `1` generic, `2` usage, `126` not executable, `127` not
  found, `128+N` fatal signal. Document any script-specific codes.

## Control Flow

```bash
if [[ -f $file && -r $file ]]; then ...; fi
[[ $name =~ ^[a-z][a-z0-9_]*$ ]] || die "invalid name"
case $1 in
  -v|--verbose) verbose=1 ;;
  -h|--help) usage; exit 0 ;;
  --) shift; break ;;
  *) die "unknown option: $1" ;;
esac
command -v jq >/dev/null || die "jq required"
```

- Prefer `[[ ]]` in bash (no word splitting, `&&`/`||`, `=~`, `-v`, lexicographic `<`).
  Use `[ ]` only for POSIX scripts; quote everything inside it.
- `[[ a == b ]]` is a pattern match on the right side unless quoted: `[[ $x == "$y" ]]`.
- `test -v var` checks set-ness under `set -u`; `${var+x}` is the portable equivalent.
- `getopts` handles short options only; long options need a `while (($#)); do case ...`
  loop. Never `shift` past `$#`.
- `trap ... DEBUG` and `set -x` are for debugging, not production; `PS4='+${BASH_SOURCE}:${LINENO}: '`
  makes traces useful.

## Portability: POSIX vs bash vs zsh

| Construct | POSIX sh | bash | zsh |
|---|---|---|---|
| `[[ ]]` | No | Yes | Yes (different regex) |
| Arrays | No | Yes | Yes (1-indexed) |
| `local` | Not specified (widely supported) | Yes | Yes |
| `set -o pipefail` | No | Yes | Yes |
| `${var//a/b}` | No | Yes | Yes |
| `read -r -a arr` | No | Yes | `-A` |
| `mapfile`/`readarray` | No | 4.0+ | `read -A` |
| `printf -v` | No | Yes | `printf -v` |
| `$RANDOM` | No | Yes | Yes |
| `mktemp` | Not specified but universal | Yes | Yes |
| `seq` | Not POSIX (BSD differs) | GNU | BSD flavor |

- For POSIX scripts use `#!/bin/sh`, avoid arrays and `[[ ]]`, use `$(...)` not backticks,
  and prefer `case` over `getopts` for long options.
- Test on the actual floor: `dash -n script.sh` catches bashisms fast; run in a container
  if the target uses BusyBox.
- `command -v` is the portable "is this installed" check; `which` is not reliable.

## Testing and Static Analysis

```bash
# bats-core test
@test "usage exits 2" {
  run ./deploy.sh --bogus
  [ "$status" -eq 2 ]
  [[ $output == *"Usage:"* ]]
}

@test "dry run creates no files" {
  run ./deploy.sh --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
}
```

```bash
shellcheck -x -S style script.sh     # -x follows sourced files
shfmt -i 2 -ci -w script.sh          # deterministic formatting
bats --print-output-on-failure tests/ # run the suite
```

- shellcheck codes worth knowing: SC2086 (quote to prevent splitting), SC2046 (quote
  command substitution), SC2181 (check `$?` directly), SC2155 (declare/assign masks
  status), SC2164 (`cd` without `|| exit`), SC2310/SC2311 (function masking `-e`).
- Disable rules narrowly with a reason: `# shellcheck disable=SC2086 # intentional glob`.
- bats-core uses `$BATS_TEST_TMPDIR` for isolated scratch space; `setup_file` runs once
  per file, `setup` before each test. Avoid asserting on timing.
- Test the failure paths: missing dependency, bad input, permission denied, interrupt.
  Unattended scripts fail at 3 a.m.; your tests should reach those branches.

## Common Footguns

- `CMD=$(command) > file` redirects the *outer* assignment, not the command; use
  `command > file`.
- `cd` failure ignored, then `rm -rf "$PWD"/*` deletes the wrong tree. Always
  `cd ... || die`.
- Pipelines run in subshells: `while read -r x; do n=$((n+1)); done < f` works, but
  `... | while read` loses `n` after the pipe.
- `PIPESTATUS` must be read immediately; any intervening command resets it.
- `xargs` without `-0` breaks on spaces/newlines: pair with `find -print0` and `-0`.
- `find . -name '*.log' -delete` races with new files; quote patterns so the shell does
  not expand them first.
- `rm -rf -- "$dir/"` with a typo'd variable (`dir=/`) is catastrophic: guard with
  `${dir:?}`, use `--`, and prefer `find -delete` or targeted paths.
- Backticks nest badly and process escapes; always `$(...)`.
- `eval` on untrusted input is code execution; `${!var}` indirection is the safe form.
- Writing to a file in place (`cmd > file`) truncates before the command reads it; write
  to a temp file and `mv`.
- `sudo` in scripts requires a TTY by default; `sudo -n` fails fast, and `BEGIN{...}`.
- Locale-dependent `sort`/`grep` output changes under `LC_ALL`; set `LC_ALL=C` for
  deterministic parsing.
- Relying on `$PATH` in cron/systemd: set an explicit `PATH=` or use absolute binaries.

## Anti-Patterns

- Parsing `ls` output; use globs, `find`, or shellcheck-clean loops.
- `cat file | grep x`; use `grep x file` (UUOC).
- `for i in $(seq 1 10)`; use `for ((i=1;i<=10;i++))` in bash or `while` for POSIX.
- `set -e` plus blanket `|| true`, which nullifies strict mode.
- Long inline `awk`/`sed` scripts doing what a small Python script does legibly.
- Reading secrets from argv (visible in `ps`); read from env or file descriptor.
- `chmod 777` to make a permission error disappear instead of fixing ownership.
- Ignoring `shellcheck` findings because "it works on my machine".

## Checklist

- [ ] Shebang matches the constructs used; interpreter floor documented.
- [ ] `set -Eeuo pipefail` (bash) or deliberate POSIX equivalent.
- [ ] All expansions quoted; `"$@"` for positional parameters; `--` before paths.
- [ ] Traps set for EXIT and INT/TERM; cleanup idempotent; 128+N exit codes.
- [ ] Temporaries via `mktemp`, cleaned on exit; no fixed `/tmp` filenames.
- [ ] Dependencies checked with `command -v` and a clear error.
- [ ] `shellcheck` and `shfmt` clean; bats tests cover failure paths.
- [ ] Logs go to stderr; machine-readable output goes to stdout.
- [ ] No secrets in argv, environment dumps, or `set -x` traces.
- [ ] Idempotent where plausible (safe to re-run after partial failure).

Related: [Linux administration](./02-linux-admin.md) for scheduling and services,
[security hardening](./09-security-hardening.md) for privilege and secret handling.
