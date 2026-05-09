#!/usr/bin/env bash
# Redirect Claude Code's project-local permission file from ~/chat to
# ~/deai/anthro-log via a symlink, so "always allow" choices accumulate
# in the anthro-log repo instead of leaking into the unrelated ~/chat
# project.
#
# RUN THIS WHILE CLAUDE CODE IS NOT RUNNING.
#
# After this script: backup at ~/chat/.claude/settings.local.json.bak,
# symlink at ~/chat/.claude/settings.local.json → anthro-log target.
# Run scripts/restore-perms.sh to undo.

set -euo pipefail

CHAT_FILE="$HOME/chat/.claude/settings.local.json"
BACKUP_FILE="$CHAT_FILE.bak"
ANTHRO_DIR="$HOME/deai/anthro-log/.claude"
ANTHRO_FILE="$ANTHRO_DIR/settings.local.json"

# --- safety: refuse only if a claude session is using ~/chat as its cwd ---
# (Other claude sessions in unrelated projects don't conflict — they don't
# touch ~/chat/.claude/settings.local.json.)
conflicts=()
while IFS= read -r pid; do
  [[ -z "$pid" ]] && continue
  cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
  case "$cwd" in
    "$HOME/chat"|"$HOME/chat"/*) conflicts+=("$pid  $cwd") ;;
  esac
done < <(pgrep -x claude 2>/dev/null || true)

if (( ${#conflicts[@]} > 0 )); then
  echo "ERROR: claude session(s) still running with cwd in ~/chat:"
  printf '  %s\n' "${conflicts[@]}"
  echo "Exit those sessions, then re-run this script."
  echo "(Other claude sessions in unrelated projects are fine — ignored.)"
  exit 1
fi

# --- already migrated? ---
if [[ -L "$CHAT_FILE" ]]; then
  current_target="$(readlink -f "$CHAT_FILE" || true)"
  expected_target="$(readlink -f "$ANTHRO_FILE" 2>/dev/null || echo "$ANTHRO_FILE")"
  if [[ "$current_target" == "$expected_target" ]]; then
    echo "Already migrated: $CHAT_FILE -> $current_target"
    exit 0
  fi
  echo "ERROR: $CHAT_FILE is a symlink but points elsewhere ($current_target)."
  echo "Investigate before re-running."
  exit 1
fi

# --- backup conflict? ---
if [[ -e "$BACKUP_FILE" ]]; then
  echo "ERROR: backup already exists at $BACKUP_FILE"
  echo "Either restore-perms.sh was not run after the last session,"
  echo "or a stale backup is in the way. Resolve before re-running."
  exit 1
fi

# --- prep target ---
mkdir -p "$ANTHRO_DIR"
if [[ ! -e "$ANTHRO_FILE" ]]; then
  echo "{}" > "$ANTHRO_FILE"
  echo "Created empty target: $ANTHRO_FILE"
fi

# --- swap ---
if [[ -e "$CHAT_FILE" ]]; then
  mv "$CHAT_FILE" "$BACKUP_FILE"
  echo "Backed up: $CHAT_FILE -> $BACKUP_FILE"
else
  echo "Note: no existing $CHAT_FILE — nothing to back up."
fi

ln -s "$ANTHRO_FILE" "$CHAT_FILE"
echo "Linked:    $CHAT_FILE -> $ANTHRO_FILE"

echo
echo "Done. New 'always allow' permissions will accumulate at:"
echo "  $ANTHRO_FILE"
echo
echo "Now run:  claude --resume"
echo "Undo with: bash $(dirname "$0")/restore-perms.sh"
