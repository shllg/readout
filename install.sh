#!/usr/bin/env bash
#
# Install the readout CLI and skill from this checkout.
#
# Everything is a symlink into this repository, so `git pull` updates it. Re-running is
# safe: nothing is replaced unless it is a symlink this repository owns.
#
#   bin/readout        -> ~/.local/bin/readout
#   skills/readout     -> ~/.claude/skills/readout
#   skills/readout     -> ~/.agents/skills/readout
#
# Usage: install.sh [-n|--dry-run] [--uninstall]
# Exit:  0 done, 1 a target was skipped (conflict), 2 usage error

set -euo pipefail

REPO=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

DRY=0
UNINSTALL=0
for arg in "$@"; do
  case $arg in
    -n | --dry-run) DRY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h | --help)
      sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'install.sh: unknown option %s\n' "$arg" >&2
      printf 'Usage: install.sh [-n|--dry-run] [--uninstall]\n' >&2
      exit 2
      ;;
  esac
done

FAILED=0
say() { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
shorten() { printf '%s' "${1/#"$HOME"/\~}"; }

# owned <symlink>: true when the link points into this repository.
owned() {
  local target
  target=$(readlink "$1")
  case $target in
    "$REPO" | "$REPO"/*) return 0 ;;
  esac
  return 1
}

# Refuse to write per-skill links into this checkout through a symlinked parent.
guard_dir() {
  local dir=$1 phys
  [ -L "$dir" ] || return 0
  phys=$(cd -P -- "$dir" 2>/dev/null && pwd -P) || return 0
  case $phys in
    "$REPO" | "$REPO"/*)
      warn "$(shorten "$dir") is a symlink into this repository ($phys); refusing to install"
      exit 1
      ;;
  esac
}

ensure_dir() {
  [ -d "$1" ] && return 0
  if [ "$DRY" = 1 ]; then
    say "would create $(shorten "$1")"
  else
    mkdir -p -- "$1"
    say "created $(shorten "$1")"
  fi
}

# link <src> <dst>
link() {
  local src=$1 dst=$2
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      say "$(shorten "$dst") (already linked)"
      return 0
    fi
    if ! owned "$dst"; then
      warn "$(shorten "$dst") is a symlink not owned by this repository; left untouched"
      return 0
    fi
    if [ "$DRY" = 1 ]; then
      say "would relink $(shorten "$dst") -> $src"
      return 0
    fi
    rm -f -- "$dst"
  elif [ -e "$dst" ]; then
    warn "$(shorten "$dst") exists and is not a symlink; left untouched"
    FAILED=1
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    say "would link $(shorten "$dst") -> $src"
    return 0
  fi
  ln -s -- "$src" "$dst"
  say "$(shorten "$dst") -> $src"
}

# unlink_owned <dst>: remove only a symlink that points into this repository.
unlink_owned() {
  local dst=$1
  if [ -L "$dst" ] && owned "$dst"; then
    if [ "$DRY" = 1 ]; then
      say "would remove $(shorten "$dst")"
    else
      rm -f -- "$dst"
      say "removed $(shorten "$dst")"
    fi
  elif [ -L "$dst" ] || [ -e "$dst" ]; then
    warn "$(shorten "$dst") is not owned by this repository; left untouched"
  else
    say "$(shorten "$dst") (not installed)"
  fi
}

BIN_DIR="$HOME/.local/bin"
CLAUDE_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.agents/skills"

if [ "$UNINSTALL" = 1 ]; then
  unlink_owned "$BIN_DIR/readout"
  unlink_owned "$CLAUDE_DIR/readout"
  unlink_owned "$AGENTS_DIR/readout"
else
  for d in "$BIN_DIR" "$CLAUDE_DIR" "$AGENTS_DIR"; do guard_dir "$d"; done
  ensure_dir "$BIN_DIR"
  link "$REPO/bin/readout" "$BIN_DIR/readout"
  ensure_dir "$CLAUDE_DIR"
  link "$REPO/skills/readout" "$CLAUDE_DIR/readout"
  ensure_dir "$AGENTS_DIR"
  link "$REPO/skills/readout" "$AGENTS_DIR/readout"

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$(shorten "$BIN_DIR") is not on your PATH; add it so \`readout\` resolves" ;;
  esac
  for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || warn "$tool was not found on PATH; readout needs it"
  done
  say "Next: set READOUT_TOKEN, then run \`readout whoami\`."
fi

[ "$DRY" = 1 ] && say "(dry run: nothing was changed)"
[ "$FAILED" = 0 ] || exit 1
exit 0
