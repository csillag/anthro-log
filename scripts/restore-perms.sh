#!/usr/bin/env bash
# Undo the migrate-perms.sh swap. Removes the symlink at
# ~/chat/.claude/settings.local.json and restores the backed-up file.
# The anthro-log target file stays in place with the perms accumulated
# during the session — it's now ready for use when Claude is launched
# from ~/deai/anthro-log.
#
# RUN THIS WHILE CLAUDE CODE IS NOT RUNNING.

set -euo pipefail

CHAT_FILE="$HOME/chat/.claude/settings.local.json"
BACKUP_FILE="$CHAT_FILE.bak"
ANTHRO_FILE="$HOME/deai/anthro-log/.claude/settings.local.json"

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

# --- expected state: CHAT_FILE is a symlink, BACKUP exists ---
if [[ ! -L "$CHAT_FILE" ]]; then
  if [[ -f "$CHAT_FILE" && -e "$BACKUP_FILE" ]]; then
    echo "ERROR: $CHAT_FILE is a regular file (not symlink) AND backup exists."
    echo "Likely cause: Claude rewrote the symlink as a real file via atomic rename."
    echo "Manual fix needed:"
    echo "  1) Inspect $CHAT_FILE  (current 'live' file, may have new perms)"
    echo "  2) Inspect $BACKUP_FILE (original ~/chat perms)"
    echo "  3) Inspect $ANTHRO_FILE (target — possibly stale/empty)"
    echo "  4) Decide what to merge where, then:"
    echo "       mv $BACKUP_FILE $CHAT_FILE  (or merge first)"
    exit 1
  fi
  echo "ERROR: not in migrated state — $CHAT_FILE is not a symlink."
  echo "Nothing to restore."
  exit 1
fi

if [[ ! -e "$BACKUP_FILE" ]]; then
  echo "ERROR: backup missing at $BACKUP_FILE"
  echo "Cannot restore. Investigate manually."
  exit 1
fi

# --- restore ---
rm "$CHAT_FILE"
echo "Removed symlink: $CHAT_FILE"

mv "$BACKUP_FILE" "$CHAT_FILE"
echo "Restored:        $CHAT_FILE  (from .bak)"

echo
echo "Done. anthro-log perms preserved at:"
echo "  $ANTHRO_FILE"
echo
echo "Next time you work on anthro-log, launch Claude there:"
echo "  cd $HOME/deai/anthro-log && claude"
echo "and the accumulated perms will apply automatically."
