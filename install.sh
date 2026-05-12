#!/usr/bin/env bash
# install.sh — symlink the SoftCo skill into ~/.claude/skills/softco so
# Claude Code can pick it up.
#
# Usage:
#   ./install.sh             # install (creates symlink)
#   ./install.sh --uninstall # remove symlink
#   ./install.sh --force     # overwrite an existing symlink/dir at the target

set -euo pipefail

err() { printf '\033[31m[install]\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m[install]\033[0m %s\n' "$*"; }
log() { printf '[install] %s\n' "$*"; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SOURCE="$SCRIPT_DIR/skill"
TARGET_DIR="$HOME/.claude/skills"
TARGET="$TARGET_DIR/softco"

UNINSTALL=0
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) UNINSTALL=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) err "unknown flag: $1" ;;
  esac
  shift
done

if [[ $UNINSTALL -eq 1 ]]; then
  if [[ -L "$TARGET" || -e "$TARGET" ]]; then
    rm -rf -- "$TARGET"
    ok "removed $TARGET"
  else
    log "nothing to remove at $TARGET"
  fi
  exit 0
fi

[[ -d "$SOURCE" ]] || err "source dir missing: $SOURCE"
[[ -f "$SOURCE/SKILL.md" ]] || err "SKILL.md missing at $SOURCE/SKILL.md"

mkdir -p "$TARGET_DIR"

if [[ -L "$TARGET" || -e "$TARGET" ]]; then
  if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$SOURCE" ]]; then
    ok "already installed → $TARGET"
    exit 0
  fi
  if [[ $FORCE -eq 1 ]]; then
    rm -rf -- "$TARGET"
  else
    err "target exists: $TARGET (rerun with --force to overwrite)"
  fi
fi

ln -s "$SOURCE" "$TARGET"
ok "installed: $TARGET → $SOURCE"
log "restart Claude Code or open a new session to load the skill"
