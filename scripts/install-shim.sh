#!/usr/bin/env bash
# Replace the 'claude' command on PATH with a shim that auto-sources
# claude-env.sh (enabling OTel telemetry) before exec'ing the real
# binary. Transparent to all CLI args.
#
# Defaults install at ~/local/bin/claude. Override via SHIM_PATH env var.
# Auto-detects real claude binary; override via CLAUDE_REAL_BIN.
# Records prior state at $SHIM_PATH.original so uninstall-shim.sh can
# restore exactly.

set -euo pipefail

SHIM_PATH="${SHIM_PATH:-$HOME/local/bin/claude}"
ORIG_RECORD="$SHIM_PATH.original"
ENV_FILE="${ANTHRO_LOG_ENV_FILE:-$HOME/deai/anthro-log/claude-env.sh}"

# --- already installed? ---
if [[ -f "$SHIM_PATH" ]] && grep -q "ANTHRO_LOG_SHIM_MARKER" "$SHIM_PATH" 2>/dev/null; then
  echo "Shim already installed: $SHIM_PATH"
  echo "(Run uninstall-shim.sh first if you want to reinstall.)"
  exit 0
fi

# --- find real claude binary ---
# Priority:
#  1. CLAUDE_REAL_BIN env override
#  2. If SHIM_PATH is currently a symlink, resolve it (one hop) — most
#     reliable since the symlink already points at the real binary.
#  3. Walk PATH for any 'claude' that isn't SHIM_PATH itself.
REAL_BIN="${CLAUDE_REAL_BIN:-}"
if [[ -z "$REAL_BIN" ]] && [[ -L "$SHIM_PATH" ]]; then
  link_target="$(readlink "$SHIM_PATH")"
  case "$link_target" in
    /*) REAL_BIN="$link_target" ;;
    *)  REAL_BIN="$(cd "$(dirname "$SHIM_PATH")" && readlink -f "$link_target")" ;;
  esac
fi
if [[ -z "$REAL_BIN" ]]; then
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" != "$SHIM_PATH" ]]; then
      REAL_BIN="$p"
      break
    fi
  done < <(type -aP claude 2>/dev/null || true)
fi

if [[ -z "$REAL_BIN" ]]; then
  echo "ERROR: could not locate the real claude binary."
  echo "Set CLAUDE_REAL_BIN explicitly, e.g.:"
  echo "  CLAUDE_REAL_BIN=\$HOME/.local/bin/claude bash $0"
  exit 1
fi
if [[ ! -x "$REAL_BIN" ]]; then
  echo "ERROR: $REAL_BIN is not executable."
  exit 1
fi

# --- record prior state for uninstall ---
mkdir -p "$(dirname "$SHIM_PATH")"
if [[ -L "$SHIM_PATH" ]]; then
  printf 'symlink:%s\n' "$(readlink "$SHIM_PATH")" > "$ORIG_RECORD"
  echo "Recorded prior symlink target."
elif [[ -f "$SHIM_PATH" ]]; then
  cp -p "$SHIM_PATH" "$ORIG_RECORD.copy"
  printf 'file:%s\n' "$ORIG_RECORD.copy" > "$ORIG_RECORD"
  echo "Recorded prior file (saved to $ORIG_RECORD.copy)."
elif [[ -e "$SHIM_PATH" ]]; then
  echo "ERROR: $SHIM_PATH exists and is neither symlink nor regular file."
  exit 1
else
  printf 'absent\n' > "$ORIG_RECORD"
  echo "No prior $SHIM_PATH; recorded 'absent'."
fi

# --- write shim ---
rm -f "$SHIM_PATH"
cat > "$SHIM_PATH" <<EOF
#!/usr/bin/env bash
# ANTHRO_LOG_SHIM_MARKER
# Auto-source anthro-log OTel env, then exec real claude binary.
# Transparent to CLI args. Disable env load with ANTHRO_LOG_DISABLE=1.
#
# Real binary: $REAL_BIN
# Env file:    $ENV_FILE
# Installed by: $0

if [[ -z "\${ANTHRO_LOG_DISABLE:-}" ]] && [[ -r "$ENV_FILE" ]]; then
  # shellcheck disable=SC1091
  source "$ENV_FILE" >/dev/null 2>&1
fi

exec "$REAL_BIN" "\$@"
EOF
chmod +x "$SHIM_PATH"

echo
echo "Installed shim:"
echo "  $SHIM_PATH"
echo "  -> $REAL_BIN"
echo "  env: $ENV_FILE"
echo
echo "Uninstall with: bash $(dirname "$0")/uninstall-shim.sh"
