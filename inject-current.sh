#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/runtime.sh"

APP_NAME="codex-app-extension"
DEFAULT_PORT="${CODEX_APP_EXTENSION_PORT:-${CODEX_WIDE_PORT:-9229}}"
CODEX_APP_PATH="$(resolve_codex_app_path || true)"

print_help() {
  cat <<'HELP'
Usage:
  inject-current.sh [inject-wide-layout options]

Re-injects codex-app-extension into the current ChatGPT/Codex instance.

Port selection order:
  1. --port <number>
  2. CODEX_APP_EXTENSION_PORT / CODEX_WIDE_PORT
  3. listening ChatGPT/Codex process discovered by lsof
  4. 9229

Examples:
  ./inject-current.sh
  ./inject-current.sh --diagnose
  ./inject-current.sh --port 9229 --diagnose
HELP
}

parse_cli_port() {
  local next_is_port=0

  for arg in "$@"; do
    if [[ "$next_is_port" -eq 1 ]]; then
      printf '%s\n' "$arg"
      return 0
    fi

    if [[ "$arg" == "--port" ]]; then
      next_is_port=1
    else
      next_is_port=0
    fi
  done

  return 1
}

add_candidate_port() {
  local port="$1"

  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  if [[ "${#CANDIDATE_PORTS[@]}" -gt 0 ]]; then
    for existing_port in "${CANDIDATE_PORTS[@]}"; do
      if [[ "$existing_port" == "$port" ]]; then
        return 0
      fi
    done
  fi

  CANDIDATE_PORTS+=("$port")
}

is_debug_port_ready() {
  local port="$1"

  curl --silent --fail --max-time 2 "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1
}

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    print_help
    exit 0
  fi
done

if ! NODE_BIN="$(resolve_codex_node_bin "$CODEX_APP_PATH")"; then
  echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
  echo "[$APP_NAME] Node.js must expose both fetch and WebSocket." >&2
  exit 1
fi

CLI_PORT="$(parse_cli_port "$@" || true)"
CANDIDATE_PORTS=()

add_candidate_port "$CLI_PORT"
add_candidate_port "${CODEX_APP_EXTENSION_PORT:-}"
add_candidate_port "${CODEX_WIDE_PORT:-}"

while IFS= read -r discovered_port; do
  add_candidate_port "$discovered_port"
done < <(discover_codex_debug_ports)

add_candidate_port "$DEFAULT_PORT"

SELECTED_PORT=""
for candidate_port in "${CANDIDATE_PORTS[@]}"; do
  if is_debug_port_ready "$candidate_port"; then
    SELECTED_PORT="$candidate_port"
    break
  fi
done

if [[ -z "$SELECTED_PORT" ]]; then
  echo "[$APP_NAME] No running ChatGPT/Codex remote debugging port found." >&2
  echo "[$APP_NAME] Start ChatGPT/Codex with $SCRIPT_DIR/launch.sh first, or pass --port <number>." >&2
  exit 1
fi

echo "[$APP_NAME] Found ChatGPT/Codex debugger on port ${SELECTED_PORT}."
echo "[$APP_NAME] Re-injecting extension into the current Codex workspace..."

if [[ -n "$CLI_PORT" ]]; then
  "$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" "$@"
else
  "$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" --port "$SELECTED_PORT" "$@"
fi
