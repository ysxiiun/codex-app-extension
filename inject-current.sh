#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

APP_NAME="codex-app-extension"
DEFAULT_PORT="${CODEX_APP_EXTENSION_PORT:-${CODEX_WIDE_PORT:-9229}}"
NODE_BIN="${NODE_BIN:-node}"

print_help() {
  cat <<'HELP'
Usage:
  inject-current.sh [inject-wide-layout options]

Re-injects codex-app-extension into the currently running Codex instance.

Port selection order:
  1. --port <number>
  2. CODEX_APP_EXTENSION_PORT / CODEX_WIDE_PORT
  3. listening Codex process discovered by lsof
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

discover_codex_ports() {
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  # lsof only discovers candidate ports; the HTTP debugger endpoint check below is authoritative.
  lsof -nP -a -c Codex -iTCP -sTCP:LISTEN 2>/dev/null \
    | sed -nE 's/.*TCP .*:([0-9]+) \(LISTEN\).*/\1/p'
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

if ! "$NODE_BIN" -e "process.exit(0)" >/dev/null 2>&1; then
  NODE_BIN="/Applications/Codex.app/Contents/Resources/node"
fi

if ! "$NODE_BIN" -e "process.exit(0)" >/dev/null 2>&1; then
  echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
  echo "[$APP_NAME] Set NODE_BIN=/path/to/node and retry." >&2
  exit 1
fi

CLI_PORT="$(parse_cli_port "$@" || true)"
CANDIDATE_PORTS=()

add_candidate_port "$CLI_PORT"
add_candidate_port "${CODEX_APP_EXTENSION_PORT:-}"
add_candidate_port "${CODEX_WIDE_PORT:-}"

while IFS= read -r discovered_port; do
  add_candidate_port "$discovered_port"
done < <(discover_codex_ports)

add_candidate_port "$DEFAULT_PORT"

SELECTED_PORT=""
for candidate_port in "${CANDIDATE_PORTS[@]}"; do
  if is_debug_port_ready "$candidate_port"; then
    SELECTED_PORT="$candidate_port"
    break
  fi
done

if [[ -z "$SELECTED_PORT" ]]; then
  echo "[$APP_NAME] No running Codex remote debugging port found." >&2
  echo "[$APP_NAME] Start Codex with $SCRIPT_DIR/launch.sh first, or pass --port <number>." >&2
  exit 1
fi

echo "[$APP_NAME] Found Codex debugger on port ${SELECTED_PORT}."
echo "[$APP_NAME] Re-injecting extension into the current Codex instance..."

if [[ -n "$CLI_PORT" ]]; then
  "$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" "$@"
else
  "$NODE_BIN" "$SCRIPT_DIR/inject-wide-layout.mjs" --port "$SELECTED_PORT" "$@"
fi
