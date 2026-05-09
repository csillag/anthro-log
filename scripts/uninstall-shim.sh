#!/usr/bin/env bash
# Reverse of install-shim.sh: remove the shim and restore the prior
# claude binary path (symlink, file, or absent) using the .original
# record left by install-shim.sh.

set -euo pipefail

SHIM_PATH="${SHIM_PATH:-$HOME/local/bin/claude}"
ORIG_RECORD="$SHIM_PATH.original"

# --- safety: only operate on our shim ---
if [[ ! -f "$SHIM_PATH" ]]; then
  echo "ERROR: $SHIM_PATH does not exist or is not a regular file."
  exit 1
fi
if ! grep -q "ANTHRO_LOG_SHIM_MARKER" "$SHIM_PATH" 2>/dev/null; then
  echo "ERROR: $SHIM_PATH is not the anthro-log shim (no marker)."
  echo "Refusing to touch it."
  exit 1
fi

# --- need the record to know what to restore ---
if [[ ! -f "$ORIG_RECORD" ]]; then
  echo "ERROR: no record at $ORIG_RECORD."
  echo "Cannot determine prior state. Manual restore needed."
  exit 1
fi

read -r line < "$ORIG_RECORD"

case "$line" in
  symlink:*)
    target="${line#symlink:}"
    rm "$SHIM_PATH"
    ln -s "$target" "$SHIM_PATH"
    rm -f "$ORIG_RECORD"
    echo "Restored symlink: $SHIM_PATH -> $target"
    ;;
  file:*)
    src="${line#file:}"
    if [[ ! -f "$src" ]]; then
      echo "ERROR: backup file $src missing."
      exit 1
    fi
    rm "$SHIM_PATH"
    mv "$src" "$SHIM_PATH"
    rm -f "$ORIG_RECORD"
    echo "Restored regular file: $SHIM_PATH"
    ;;
  absent)
    rm "$SHIM_PATH"
    rm -f "$ORIG_RECORD"
    echo "Removed $SHIM_PATH (no prior file existed)."
    ;;
  *)
    echo "ERROR: unrecognized record: $line"
    exit 1
    ;;
esac
