#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/runtime.sh"

APP_NAME="codex-app-extension"
PORT="${CODEX_APP_EXTENSION_PORT:-${CODEX_WIDE_PORT:-9229}}"
CONFIG_PATH="$HOME/.codex-app-extension/config.json"

if ! CODEX_APP="$(resolve_codex_app_path)"; then
  echo "[$APP_NAME] ChatGPT/Codex app not found." >&2
  echo "[$APP_NAME] Set CODEX_APP=/path/to/ChatGPT.app and retry." >&2
  exit 1
fi

if ! NODE_BIN="$(resolve_codex_node_bin "$CODEX_APP")"; then
  echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
  echo "[$APP_NAME] Node.js must expose both fetch and WebSocket." >&2
  exit 1
fi

APP_DISPLAY_NAME="$(read_codex_app_bundle_value "$CODEX_APP" CFBundleDisplayName || true)"
APP_VERSION="$(read_codex_app_bundle_value "$CODEX_APP" CFBundleShortVersionString || true)"

config_exists() {
  [[ -e "$CONFIG_PATH" || -L "$CONFIG_PATH" ]]
}

initialize_config_if_missing() {
  if config_exists; then
    return 0
  fi

  echo "[$APP_NAME] No local config found at $CONFIG_PATH."
  if [[ ! -t 0 ]]; then
    echo "[$APP_NAME] First-time setup requires an interactive terminal." >&2
    echo "[$APP_NAME] Run $SCRIPT_DIR/follow-author-config.sh or $SCRIPT_DIR/config.sh first." >&2
    exit 1
  fi

  while true; do
    echo "[$APP_NAME] Choose initial config:"
    echo "  1. follow author config"
    echo "  2. 自定义配置"
    read -r -p "[$APP_NAME] Enter 1 or 2: " answer

    case "$answer" in
      1)
        "$SCRIPT_DIR/follow-author-config.sh"
        return 0
        ;;
      2)
        "$SCRIPT_DIR/config.sh"
        return 0
        ;;
      *)
        echo "[$APP_NAME] Please enter 1 or 2."
        ;;
    esac
  done
}

is_debug_port_ready() {
  curl --silent --fail "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1
}

initialize_config_if_missing

if ! is_debug_port_ready; then
  echo "[$APP_NAME] Starting ${APP_DISPLAY_NAME:-ChatGPT} ${APP_VERSION:-} with remote debugging port ${PORT}..."
  echo "[$APP_NAME] App: $CODEX_APP"
  echo "[$APP_NAME] If an existing ChatGPT/Codex window captures the launch, quit it fully and rerun this script."
  open -na "$CODEX_APP" --args "--remote-debugging-address=127.0.0.1" "--remote-debugging-port=${PORT}"

  for _ in {1..60}; do
    if is_debug_port_ready; then
      break
    fi
    sleep 0.5
  done
fi

if ! is_debug_port_ready; then
  echo "[$APP_NAME] ChatGPT/Codex did not expose http://127.0.0.1:${PORT}." >&2
  echo "[$APP_NAME] Quit ChatGPT/Codex fully, then rerun this script." >&2
  exit 1
fi

echo "[$APP_NAME] Waiting for the Codex workspace target, then injecting extension..."
"$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" --port "$PORT"

echo "[$APP_NAME] Done. Config: ~/.codex-app-extension/config.json"
echo "[$APP_NAME] Keep this ChatGPT/Codex instance open to keep the injected layout."
