#!/usr/bin/env bash
# Tests for install.sh. Every run uses a throwaway HOME; the real home is never touched.
# shellcheck disable=SC2015 # "cond && ok || no" is the intended assertion idiom here
set -u

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
INSTALL="$ROOT/install.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok  %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  NO  %s\n' "$1"; [ $# -lt 2 ] || printf '      %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2] got [$3]"; fi; }
has() { case $3 in *"$2"*) ok "$1" ;; *) no "$1" "[$2] not in [$3]" ;; esac; }

N=0
newhome() { N=$((N + 1)); H="$TMP/home$N"; mkdir -p "$H"; }
# inst <args...>: run install.sh against $H with a PATH that includes ~/.local/bin unless NOPATH=1.
inst() {
  local p=$PATH
  [ "${NOPATH:-}" = 1 ] || p="$H/.local/bin:$PATH"
  OUT=$(HOME="$H" PATH="$p" bash "$INSTALL" "$@" 2>&1)
  RC=$?
}

BIN_L() { printf '%s/.local/bin/readout' "$H"; }
CLAUDE_L() { printf '%s/.claude/skills/readout' "$H"; }
AGENTS_L() { printf '%s/.agents/skills/readout' "$H"; }

echo "fresh install"
newhome
inst
check "exits 0" 0 "$RC"
check "bin link" "$ROOT/bin/readout" "$(readlink "$(BIN_L)")"
check "claude skill link" "$ROOT/skills/readout" "$(readlink "$(CLAUDE_L)")"
check "agents skill link" "$ROOT/skills/readout" "$(readlink "$(AGENTS_L)")"
[ -x "$(BIN_L)" ] && ok "linked CLI is executable" || no "linked CLI is executable"
check "linked CLI runs" "readout 0.2.2" "$(HOME="$H" "$(BIN_L)" version)"

echo "re-run"
inst
check "second run exits 0" 0 "$RC"
check "bin link unchanged" "$ROOT/bin/readout" "$(readlink "$(BIN_L)")"
has "reports already linked" "already linked" "$OUT"

echo "conflicts"
newhome
mkdir -p "$H/.local/bin"
printf 'mine\n' >"$H/.local/bin/readout"
inst
check "existing file: exits 1" 1 "$RC"
check "existing file: untouched" "mine" "$(cat "$H/.local/bin/readout")"
[ ! -L "$H/.local/bin/readout" ] && ok "existing file: still a regular file" || no "existing file: still a regular file"
has "existing file: warns" "not a symlink" "$OUT"
check "other targets still linked" "$ROOT/skills/readout" "$(readlink "$(CLAUDE_L)")"

newhome
mkdir -p "$H/.claude/skills" "$TMP/other-repo/skills/readout"
ln -s "$TMP/other-repo/skills/readout" "$H/.claude/skills/readout"
inst
check "foreign symlink: left in place" "$TMP/other-repo/skills/readout" "$(readlink "$(CLAUDE_L)")"
has "foreign symlink: warns" "not owned by this repo" "$OUT"
check "foreign symlink: other links still made" "$ROOT/skills/readout" "$(readlink "$(AGENTS_L)")"

newhome
mkdir -p "$H/.agents/skills/readout"
inst
check "existing directory: exits 1" 1 "$RC"
[ -d "$H/.agents/skills/readout" ] && [ ! -L "$H/.agents/skills/readout" ] && ok "existing directory: untouched" || no "existing directory: untouched"

newhome
mkdir -p "$H/.local/bin"
ln -s "$ROOT/bin/readout-old" "$H/.local/bin/readout"
inst
check "stale link into this repo is replaced" "$ROOT/bin/readout" "$(readlink "$(BIN_L)")"

newhome
mkdir -p "$H/.claude"
ln -s "$ROOT/skills" "$H/.claude/skills"
inst
check "skills dir symlinked into the repo: exits 1" 1 "$RC"
[ ! -e "$ROOT/skills/skills" ] && ok "repo not polluted" || no "repo not polluted"

echo "dry run"
newhome
inst --dry-run
check "dry run exits 0" 0 "$RC"
has "dry run lists the CLI link" ".local/bin/readout" "$OUT"
has "dry run lists the skill link" ".claude/skills/readout" "$OUT"
check "dry run creates nothing" "" "$(find "$H" -mindepth 1 | head -1)"
inst -n
check "-n exits 0" 0 "$RC"
check "-n creates nothing" "" "$(find "$H" -mindepth 1 | head -1)"

echo "PATH warning"
newhome
NOPATH=1 inst
has "warns when ~/.local/bin is not on PATH" "is not on your PATH" "$OUT"
newhome
inst
case $OUT in *"is not on your PATH"*) no "no warning when on PATH" ;; *) ok "no warning when on PATH" ;; esac

echo "uninstall"
newhome
inst
inst --uninstall
check "uninstall exits 0" 0 "$RC"
[ ! -e "$(BIN_L)" ] && [ ! -L "$(BIN_L)" ] && ok "bin link removed" || no "bin link removed"
[ ! -L "$(CLAUDE_L)" ] && [ ! -L "$(AGENTS_L)" ] && ok "skill links removed" || no "skill links removed"

newhome
mkdir -p "$H/.claude/skills" "$H/.local/bin" "$TMP/other-repo/skills/readout"
ln -s "$TMP/other-repo/skills/readout" "$H/.claude/skills/readout"
printf 'mine\n' >"$H/.local/bin/readout"
inst --uninstall
check "uninstall leaves a foreign symlink" "$TMP/other-repo/skills/readout" "$(readlink "$(CLAUDE_L)")"
check "uninstall leaves a regular file" "mine" "$(cat "$H/.local/bin/readout")"
check "uninstall with nothing owned exits 0" 0 "$RC"

newhome
inst
inst --uninstall --dry-run
[ -L "$(BIN_L)" ] && ok "uninstall --dry-run removes nothing" || no "uninstall --dry-run removes nothing"

echo "usage"
newhome
inst --bogus
check "unknown option exits 2" 2 "$RC"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
