#!/usr/bin/env bash
set -euo pipefail

CODEX_APP_EXTENSION_BUNDLE_ID="com.openai.codex"

read_codex_app_bundle_value() {
  local app_path="$1"
  local key="$2"
  local plist_path="$app_path/Contents/Info.plist"

  if [[ ! -f "$plist_path" || ! -x /usr/libexec/PlistBuddy ]]; then
    return 1
  fi

  /usr/libexec/PlistBuddy -c "Print:$key" "$plist_path" 2>/dev/null
}

is_codex_app_bundle() {
  local app_path="$1"
  local bundle_id

  [[ -d "$app_path" ]] || return 1
  bundle_id="$(read_codex_app_bundle_value "$app_path" CFBundleIdentifier || true)"
  [[ "$bundle_id" == "$CODEX_APP_EXTENSION_BUNDLE_ID" ]]
}

resolve_codex_app_path() {
  local candidate

  # 显式 CODEX_APP 继续作为开发版、非标准安装目录和旧环境的最高优先级兼容入口。
  if [[ -n "${CODEX_APP:-}" ]]; then
    [[ -d "$CODEX_APP" ]] || return 1
    printf '%s\n' "$CODEX_APP"
    return 0
  fi

  for candidate in \
    "/Applications/ChatGPT.app" \
    "/Applications/Codex.app" \
    "$HOME/Applications/ChatGPT.app" \
    "$HOME/Applications/Codex.app"; do
    if is_codex_app_bundle "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_node_candidate() {
  local candidate="$1"
  local resolved="$candidate"

  [[ -n "$candidate" ]] || return 1
  if [[ "$candidate" != */* ]]; then
    resolved="$(command -v "$candidate" 2>/dev/null || true)"
  fi
  [[ -n "$resolved" && -x "$resolved" ]] || return 1

  # 注入脚本同时依赖原生 fetch 和 WebSocket，不能只用 process.exit(0) 判断 Node 是否可用。
  if ! "$resolved" -e 'process.exit(typeof fetch === "function" && typeof WebSocket === "function" ? 0 : 1)' >/dev/null 2>&1; then
    return 1
  fi

  printf '%s\n' "$resolved"
}

resolve_codex_node_bin() {
  local app_path="${1:-}"
  local candidate
  local resolved
  local candidates=()

  if [[ -n "${NODE_BIN:-}" ]]; then
    candidates+=("$NODE_BIN")
  fi
  candidates+=("node")

  if [[ -n "$app_path" ]]; then
    candidates+=(
      "$app_path/Contents/Resources/cua_node/bin/node"
      "$app_path/Contents/Resources/node"
    )
  fi

  candidates+=(
    "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
    "/Applications/Codex.app/Contents/Resources/cua_node/bin/node"
    "/Applications/Codex.app/Contents/Resources/node"
  )

  for candidate in "${candidates[@]}"; do
    resolved="$(resolve_node_candidate "$candidate" || true)"
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  done

  return 1
}

discover_codex_debug_ports() {
  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  # ChatGPT 是新版主进程名，Codex 继续覆盖旧应用和仍保留旧名称的 helper。
  {
    lsof -nP -a -c ChatGPT -iTCP -sTCP:LISTEN 2>/dev/null || true
    lsof -nP -a -c Codex -iTCP -sTCP:LISTEN 2>/dev/null || true
  } | sed -nE 's/.*TCP .*:([0-9]+) \(LISTEN\).*/\1/p' | awk '!seen[$0]++'
}
