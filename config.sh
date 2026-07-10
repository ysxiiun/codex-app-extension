#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/runtime.sh"

APP_NAME="codex-app-extension"
CODEX_APP_PATH="$(resolve_codex_app_path || true)"

if ! NODE_BIN="$(resolve_codex_node_bin "$CODEX_APP_PATH")"; then
  echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
  echo "[$APP_NAME] Node.js must expose both fetch and WebSocket." >&2
  exit 1
fi

"$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" --configure "$@"
