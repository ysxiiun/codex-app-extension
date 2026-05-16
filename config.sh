#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="codex-app-extension"
NODE_BIN="${NODE_BIN:-node}"

if ! "$NODE_BIN" -e "process.exit(0)" >/dev/null 2>&1; then
  NODE_BIN="/Applications/Codex.app/Contents/Resources/node"
fi

if ! "$NODE_BIN" -e "process.exit(0)" >/dev/null 2>&1; then
  echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
  echo "[$APP_NAME] Set NODE_BIN=/path/to/node and retry." >&2
  exit 1
fi

"$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" --configure "$@"
