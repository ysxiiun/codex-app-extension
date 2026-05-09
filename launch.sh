#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="codex-app-extension"
PORT="${CODEX_APP_EXTENSION_PORT:-${CODEX_WIDE_PORT:-9229}}"
CODEX_APP="${CODEX_APP:-/Applications/Codex.app}"
NODE_BIN="${NODE_BIN:-node}"

if ! "$NODE_BIN" -e "process.exit(0)" >/dev/null 2>&1; then
  NODE_BIN="/Applications/Codex.app/Contents/Resources/node"
fi

if ! "$NODE_BIN" -e "process.exit(0)" >/dev/null 2>&1; then
  echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
  echo "[$APP_NAME] Set NODE_BIN=/path/to/node and retry." >&2
  exit 1
fi

if [[ ! -d "$CODEX_APP" ]]; then
  echo "[$APP_NAME] Codex app not found: $CODEX_APP" >&2
  exit 1
fi

is_debug_port_ready() {
  curl --silent --fail "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1
}

if ! is_debug_port_ready; then
  echo "[$APP_NAME] Starting Codex with remote debugging port ${PORT}..."
  echo "[$APP_NAME] If an existing Codex window captures the launch, quit Codex fully and rerun this script."
  open -na "$CODEX_APP" --args "--remote-debugging-port=${PORT}"

  for _ in {1..60}; do
    if is_debug_port_ready; then
      break
    fi
    sleep 0.5
  done
fi

if ! is_debug_port_ready; then
  echo "[$APP_NAME] Codex did not expose http://127.0.0.1:${PORT}." >&2
  echo "[$APP_NAME] Quit Codex fully, then rerun this script." >&2
  exit 1
fi

echo "[$APP_NAME] Waiting for Codex page target, then injecting extension..."
"$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" --port "$PORT"

echo "[$APP_NAME] Done. Config: ~/.codex-app-extension/config.json"
echo "[$APP_NAME] Keep this Codex instance open to keep the injected layout."
