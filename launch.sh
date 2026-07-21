#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/runtime.sh"

APP_NAME="codex-app-extension"
PORT="${CODEX_APP_EXTENSION_PORT:-${CODEX_WIDE_PORT:-9229}}"
CONFIG_PATH="$HOME/.codex-app-extension/config.json"

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
    return 1
  fi

  while true; do
    echo "[$APP_NAME] Choose initial config:"
    echo "  1. follow author config"
    echo "  2. 自定义配置"
    read -r -p "[$APP_NAME] Enter 1 or 2: " answer

    case "$answer" in
      1)
        "$SCRIPT_DIR/follow-author-config.sh"
        return $?
        ;;
      2)
        "$SCRIPT_DIR/config.sh"
        return $?
        ;;
      *)
        echo "[$APP_NAME] Please enter 1 or 2."
        ;;
    esac
  done
}

find_ready_debug_port() {
  local preferred_port="$1"
  local candidate_port
  local seen_ports="|"

  if is_debug_port_ready "$preferred_port"; then
    printf '%s\n' "$preferred_port"
    return 0
  fi
  seen_ports="${seen_ports}${preferred_port}|"

  while IFS= read -r candidate_port; do
    [[ "$candidate_port" =~ ^[0-9]+$ ]] || continue
    case "$seen_ports" in
      *"|${candidate_port}|"*)
        continue
        ;;
    esac
    seen_ports="${seen_ports}${candidate_port}|"

    if is_debug_port_ready "$candidate_port"; then
      printf '%s\n' "$candidate_port"
      return 0
    fi
  done < <(discover_codex_debug_ports)

  return 1
}

is_force_termination_confirmed() {
  local answer="${1:-}"

  [[ "$answer" == "Y" || "$answer" == "y" ]]
}

is_interactive_stdin() {
  [[ -t 0 ]]
}

confirm_force_termination() {
  local process_name="$1"
  local answer

  if ! is_interactive_stdin; then
    echo "[$APP_NAME] ${process_name} is running without a ready remote debugging port." >&2
    echo "[$APP_NAME] Relaunch confirmation requires an interactive terminal." >&2
    return 1
  fi

  echo "[$APP_NAME] ${process_name} is running without a ready remote debugging port."
  echo "[$APP_NAME] WARNING: Y/y immediately force-terminates the app and may lose unsent text or running state."
  if ! IFS= read -r -p "[$APP_NAME] Force-terminate and relaunch? [y/N]: " answer; then
    echo "[$APP_NAME] Unable to read confirmation; cancelled safely." >&2
    return 1
  fi

  if ! is_force_termination_confirmed "$answer"; then
    echo "[$APP_NAME] Cancelled. The running app was not terminated or relaunched."
    return 2
  fi

  return 0
}

open_codex_app_with_debugging() {
  local app_path="$1"
  local port="$2"

  open -na "$app_path" --args "--remote-debugging-address=127.0.0.1" "--remote-debugging-port=${port}"
}

wait_for_debug_port() {
  local port="$1"
  local attempt=0

  while [[ "$attempt" -lt 60 ]]; do
    if is_debug_port_ready "$port"; then
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done

  is_debug_port_ready "$port"
}

inject_extension() {
  local node_bin="$1"
  local port="$2"

  echo "[$APP_NAME] Waiting for the Codex workspace target, then injecting extension..."
  "$node_bin" "$SCRIPT_DIR/inject-wide-layout.mjs" --port "$port"
}

launch_main() {
  local selected_port
  local process_name
  local process_status
  local confirmation_status
  local app_display_name
  local app_version
  local inject_status

  if ! CODEX_APP="$(resolve_codex_app_path)"; then
    echo "[$APP_NAME] ChatGPT/Codex app not found." >&2
    echo "[$APP_NAME] Set CODEX_APP=/path/to/ChatGPT.app and retry." >&2
    return 1
  fi

  if ! NODE_BIN="$(resolve_codex_node_bin "$CODEX_APP")"; then
    echo "[$APP_NAME] Cannot find a usable Node.js runtime." >&2
    echo "[$APP_NAME] Node.js must expose both fetch and WebSocket." >&2
    return 1
  fi

  process_status=0
  process_name="$(resolve_codex_main_process_name "$CODEX_APP")" || process_status=$?
  if [[ "$process_status" -ne 0 ]]; then
    if [[ "$process_status" -eq 2 ]]; then
      echo "[$APP_NAME] Unsafe CFBundleExecutable in $CODEX_APP; refusing to inspect or launch the app." >&2
    else
      echo "[$APP_NAME] Cannot read CFBundleExecutable from $CODEX_APP." >&2
    fi
    return "$process_status"
  fi

  # 在探测、强杀、注入或启动前拒绝无法安全传给 macOS pgrep/pkill 的进程名。
  if ! escape_process_name_for_ere "$process_name" >/dev/null; then
    echo "[$APP_NAME] Unsafe CFBundleExecutable in $CODEX_APP; refusing to inspect or launch the app." >&2
    return 2
  fi

  app_display_name="$(read_codex_app_bundle_value "$CODEX_APP" CFBundleDisplayName || true)"
  app_version="$(read_codex_app_bundle_value "$CODEX_APP" CFBundleShortVersionString || true)"

  initialize_config_if_missing || return $?

  if ! is_valid_tcp_port "$PORT"; then
    echo "[$APP_NAME] Invalid remote debugging port '${PORT}'; expected a decimal integer from 1 to 65535." >&2
    return 1
  fi

  selected_port="$(find_ready_debug_port "$PORT" || true)"
  if [[ -n "$selected_port" ]]; then
    PORT="$selected_port"
    echo "[$APP_NAME] Found ChatGPT/Codex debugger on port ${PORT}."
    inject_status=0
    inject_extension "$NODE_BIN" "$PORT" || inject_status=$?
    if [[ "$inject_status" -ne 0 ]]; then
      echo "[$APP_NAME] Extension injection failed on debugger port ${PORT}." >&2
      return "$inject_status"
    fi
    echo "[$APP_NAME] Done. Config: ~/.codex-app-extension/config.json"
    echo "[$APP_NAME] Keep this ChatGPT/Codex instance open to keep the injected layout."
    return 0
  fi

  process_status=0
  if is_codex_main_process_running "$process_name"; then
    confirmation_status=0
    confirm_force_termination "$process_name" || confirmation_status=$?
    if [[ "$confirmation_status" -eq 2 ]]; then
      return 0
    fi
    if [[ "$confirmation_status" -ne 0 ]]; then
      return "$confirmation_status"
    fi

    process_status=0
    force_terminate_codex_main_process "$process_name" || process_status=$?
    if [[ "$process_status" -ne 0 ]]; then
      if [[ "$process_status" -eq 2 ]]; then
        echo "[$APP_NAME] Failed to verify whether ${process_name} exited after force-termination; refusing to relaunch." >&2
      else
        echo "[$APP_NAME] Failed to force-terminate the exact ${process_name} main process." >&2
      fi
      return "$process_status"
    fi

    if is_codex_main_process_running "$process_name"; then
      echo "[$APP_NAME] ${process_name} is still running; refusing to relaunch." >&2
      return 1
    else
      process_status=$?
      if [[ "$process_status" -ne 1 ]]; then
        echo "[$APP_NAME] Failed to verify whether ${process_name} exited; refusing to relaunch." >&2
        return "$process_status"
      fi
    fi
  else
    process_status=$?
    if [[ "$process_status" -ne 1 ]]; then
      echo "[$APP_NAME] Failed to determine whether ${process_name} is running; refusing to launch." >&2
      return "$process_status"
    fi
  fi

  echo "[$APP_NAME] Starting ${app_display_name:-ChatGPT} ${app_version:-} with remote debugging port ${PORT}..."
  echo "[$APP_NAME] App: $CODEX_APP"
  if ! open_codex_app_with_debugging "$CODEX_APP" "$PORT"; then
    echo "[$APP_NAME] Failed to launch $CODEX_APP." >&2
    return 1
  fi

  if ! wait_for_debug_port "$PORT"; then
    echo "[$APP_NAME] ChatGPT/Codex did not expose http://127.0.0.1:${PORT}." >&2
    echo "[$APP_NAME] Quit ChatGPT/Codex fully, then rerun this script." >&2
    return 1
  fi

  inject_status=0
  inject_extension "$NODE_BIN" "$PORT" || inject_status=$?
  if [[ "$inject_status" -ne 0 ]]; then
    echo "[$APP_NAME] Extension injection failed after launching $CODEX_APP." >&2
    return "$inject_status"
  fi

  echo "[$APP_NAME] Done. Config: ~/.codex-app-extension/config.json"
  echo "[$APP_NAME] Keep this ChatGPT/Codex instance open to keep the injected layout."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  launch_main "$@"
fi
