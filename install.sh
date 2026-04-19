#!/usr/bin/env bash
# team-panels installer — run this from inside the cloned repo.
# The repo is expected to live at ~/.claude/skills/team-panels/ so that
# Claude Code discovers SKILL.md (a symlink to team-panels.md).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="$HOME/.claude/skills"
TARGET="$SKILLS/team-panels"

chmod +x "$SRC_DIR/scripts/"*.sh

if [[ "$SRC_DIR" != "$TARGET" ]]; then
  echo "warn: this repo is at $SRC_DIR — Claude Code expects it at $TARGET."
  echo "      move/clone the repo to $TARGET, or create a symlink:"
  echo "        ln -s \"$SRC_DIR\" \"$TARGET\""
else
  echo "team-panels installed — Claude Code will pick up SKILL.md (-> team-panels.md)."
fi
