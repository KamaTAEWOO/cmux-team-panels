#!/usr/bin/env bash
# team-panels installer — places files into ~/.claude/skills/ with the layout
# Claude Code expects for a standalone-file skill with sibling resource folder.
set -euo pipefail

SKILLS="$HOME/.claude/skills"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="team-panels"
SKILL_FILE="$SKILL_NAME.md"
TARGET_DIR="$SKILLS/$SKILL_NAME"

mkdir -p "$SKILLS"

# Skill definition → ~/.claude/skills/team-panels.md
if [[ "$SRC_DIR/$SKILL_FILE" != "$SKILLS/$SKILL_FILE" ]]; then
  cp "$SRC_DIR/$SKILL_FILE" "$SKILLS/$SKILL_FILE"
fi

# Resource scripts → ~/.claude/skills/team-panels/scripts/
mkdir -p "$TARGET_DIR/scripts"
if [[ "$SRC_DIR/scripts" != "$TARGET_DIR/scripts" ]]; then
  cp "$SRC_DIR/scripts/run.sh" "$SRC_DIR/scripts/role.sh" "$TARGET_DIR/scripts/"
fi
chmod +x "$TARGET_DIR/scripts/"*.sh

echo "team-panels installed:"
echo "  $SKILLS/$SKILL_FILE"
echo "  $TARGET_DIR/scripts/run.sh"
echo "  $TARGET_DIR/scripts/role.sh"
