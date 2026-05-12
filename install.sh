#!/usr/bin/env bash
# install.sh — install SoftCo skill to all supported agent paths
#
# Usage:
#   ./install.sh              # install to all agents (symlinks)
#   ./install.sh --agent NAME # install to one agent (claude|opencode|codex|gemini|openclaw)
#   ./install.sh --uninstall  # remove from all agents
#   ./install.sh --force      # overwrite existing installs
#   ./install.sh --copy       # copy files instead of symlinking

set -euo pipefail

err() { printf '\033[31m[install]\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m[install]\033[0m %s\n' "$*"; }
log() { printf '[install] %s\n' "$*"; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SKILL="softco"
SKILL_SRC="$SCRIPT_DIR/skill"

UNINSTALL=0
FORCE=0
COPY=0
TARGET_AGENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) UNINSTALL=1 ;;
    --force)     FORCE=1 ;;
    --copy)      COPY=1 ;;
    --agent)     TARGET_AGENT="${2:-}"; shift ;;
    -h|--help)   sed -n '2,7p' "$0"; exit 0 ;;
    *)           err "unknown flag: $1" ;;
  esac
  shift
done

[[ $UNINSTALL -eq 0 ]] && {
  [[ -d "$SKILL_SRC" ]]          || err "source dir missing: $SKILL_SRC"
  [[ -f "$SKILL_SRC/SKILL.md" ]] || err "SKILL.md missing at $SKILL_SRC/SKILL.md"
}

handle() {
  local name="$1" dest="$2"
  [[ -n "$TARGET_AGENT" && "$name" != "$TARGET_AGENT" ]] && return

  if [[ $UNINSTALL -eq 1 ]]; then
    if [[ -L "$dest" || -e "$dest" ]]; then
      rm -rf -- "$dest"
      ok "[$name] removed $dest"
    else
      log "[$name] nothing at $dest"
    fi
    return
  fi

  if [[ -L "$dest" && "$(readlink "$dest")" == "$SKILL_SRC" ]]; then
    ok "[$name] already installed → $dest"; return
  fi

  if [[ -L "$dest" || -e "$dest" ]]; then
    if [[ $FORCE -eq 1 ]]; then rm -rf -- "$dest"
    else log "[$name] exists (use --force to overwrite): $dest"; return
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  if [[ $COPY -eq 1 ]]; then
    cp -r "$SKILL_SRC" "$dest"
    ok "[$name] copied: $dest"
  else
    ln -s "$SKILL_SRC" "$dest"
    ok "[$name] installed: $dest → $SKILL_SRC"
  fi
}

handle "claude"   "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/$SKILL"
handle "opencode" "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/$SKILL"
handle "codex"    "$HOME/.agents/skills/$SKILL"
handle "gemini"   "$HOME/.gemini/antigravity/skills/$SKILL"
handle "openclaw" "$HOME/.openclaw/workspace/skills/$SKILL"

[[ $UNINSTALL -eq 0 ]] && log "restart your agent session to load the skill"
