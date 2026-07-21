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

read_codex_app_bundle_identity_scalar() {
  local app_path="$1"
  local key="$2"
  local temp_path
  local byte_dump
  local captured_value
  local scalar_value
  local read_status=0
  local od_status=0
  local capture_status=0
  local result_status=0
  local sentinel="__CODEX_APP_EXTENSION_BUNDLE_VALUE_END__"
  local LC_ALL=C

  temp_path="$(mktemp "${TMPDIR:-/tmp}/codex-app-extension.bundle-value.XXXXXX")" || return 1

  # 先把原始字节落入独立临时文件，避免 Bash 3.2 在变量转换时静默丢弃 NUL。
  read_codex_app_bundle_value "$app_path" "$key" >"$temp_path" || read_status=$?
  if [[ "$read_status" -ne 0 ]]; then
    result_status="$read_status"
  else
    byte_dump="$(od -An -v -t x1 "$temp_path")" || od_status=$?
    if [[ "$od_status" -ne 0 ]]; then
      result_status=1
    elif [[ "$byte_dump" =~ (^|[[:space:]])00($|[[:space:]]) ]]; then
      result_status=2
    else
      captured_value="$(
        local file_status=0
        /bin/cat "$temp_path" || file_status=$?
        printf '%s' "$sentinel" || exit 1
        exit "$file_status"
      )" || capture_status=$?

      if [[ "$capture_status" -ne 0 ]]; then
        result_status=1
      elif [[ "$captured_value" != *"$sentinel" ]]; then
        result_status=1
      else
        scalar_value="${captured_value%"$sentinel"}"
        # PlistBuddy 会为标量额外输出一个换行，只移除它生成的这一个。
        scalar_value="${scalar_value%$'\n'}"
        case "$scalar_value" in
          *[[:cntrl:]]*)
            result_status=2
            ;;
        esac
      fi
    fi
  fi

  # 仅清理本次安全创建的精确路径，不修改调用方的 trap。
  if ! rm -f "$temp_path"; then
    # 原始读取失败时仍保留其状态；否则清理工具失败属于普通读取错误。
    [[ "$read_status" -ne 0 ]] || result_status=1
  fi

  [[ "$result_status" -eq 0 ]] || return "$result_status"
  printf '%s\n' "$scalar_value"
}

is_codex_app_bundle() {
  local app_path="$1"
  local bundle_id

  [[ -d "$app_path" ]] || return 1
  bundle_id="$(read_codex_app_bundle_identity_scalar "$app_path" CFBundleIdentifier)" || return $?
  [[ "$bundle_id" == "$CODEX_APP_EXTENSION_BUNDLE_ID" ]]
}

resolve_codex_app_path() {
  local candidate

  # 显式 CODEX_APP 继续作为开发版、非标准安装目录和旧环境的最高优先级兼容入口。
  if [[ -n "${CODEX_APP:-}" ]]; then
    is_codex_app_bundle "$CODEX_APP" || return 1
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

resolve_codex_main_process_name() {
  local app_path="$1"
  local executable

  executable="$(read_codex_app_bundle_identity_scalar "$app_path" CFBundleExecutable)" || return $?
  validate_process_name_safety "$executable" || return $?
  printf '%s\n' "$executable"
}

validate_process_name_safety() {
  local process_name="${1:-}"
  local byte_length
  local LC_ALL=C

  [[ -n "$process_name" ]] || return 2
  [[ "$process_name" != -* ]] || return 2
  case "$process_name" in
    *[[:cntrl:]]*)
      return 2
      ;;
  esac

  byte_length="${#process_name}"
  [[ "$byte_length" -le 19 ]] || return 2
}

escape_process_name_for_ere() {
  local process_name="${1:-}"
  local escaped_pattern=""
  local character
  local index=0

  # macOS pgrep/pkill 不支持 --，且不带 -f 时进程名最多匹配 19 字节。
  validate_process_name_safety "$process_name" || return $?

  # 将每个 ERE 元字符逐字转义，同时保留普通空格和 Unicode 名称。
  while [[ "$index" -lt "${#process_name}" ]]; do
    character="${process_name:$index:1}"
    case "$character" in
      '\'|'.'|'^'|'$'|'*'|'+'|'?'|'('|')'|'['|']'|'{'|'}'|'|')
        escaped_pattern="${escaped_pattern}\\${character}"
        ;;
      *)
        escaped_pattern="${escaped_pattern}${character}"
        ;;
    esac
    index=$((index + 1))
  done

  printf '%s\n' "$escaped_pattern"
}

is_codex_main_process_running() {
  local process_name="$1"
  local escaped_pattern
  local probe_status

  escaped_pattern="$(escape_process_name_for_ere "$process_name")" || return $?
  if pgrep -x "$escaped_pattern" >/dev/null 2>&1; then
    return 0
  else
    probe_status=$?
  fi

  # pgrep 仅以 1 表示明确未匹配；其他非零状态都属于探测错误。
  if [[ "$probe_status" -eq 1 ]]; then
    return 1
  fi
  return 2
}

wait_for_codex_main_process_exit() {
  local process_name="$1"
  local attempt=0
  local probe_status

  while [[ "$attempt" -lt 50 ]]; do
    if is_codex_main_process_running "$process_name"; then
      :
    else
      probe_status=$?
      if [[ "$probe_status" -eq 1 ]]; then
        return 0
      fi
      return "$probe_status"
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done

  return 1
}

force_terminate_codex_main_process() {
  local process_name="$1"
  local escaped_pattern
  local probe_status

  escaped_pattern="$(escape_process_name_for_ere "$process_name")" || return $?
  if is_codex_main_process_running "$process_name"; then
    :
  else
    probe_status=$?
    if [[ "$probe_status" -eq 1 ]]; then
      return 0
    fi
    return "$probe_status"
  fi

  # 用户确认后直接发送强制终止信号，不先尝试优雅退出。
  if ! pkill -KILL -x "$escaped_pattern" 2>/dev/null; then
    if is_codex_main_process_running "$process_name"; then
      return 1
    else
      probe_status=$?
      if [[ "$probe_status" -eq 1 ]]; then
        return 0
      fi
      return "$probe_status"
    fi
  fi

  wait_for_codex_main_process_exit "$process_name"
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

is_valid_tcp_port() {
  local port="${1:-}"
  local normalized_port

  [[ "$port" =~ ^0*([1-9][0-9]*)$ ]] || return 1
  normalized_port="${BASH_REMATCH[1]}"

  # 去除前导零后再按十进制范围判断，避免 Bash 将端口解析为八进制。
  [[ "${#normalized_port}" -le 5 ]] || return 1
  [[ "$normalized_port" -le 65535 ]]
}

is_debug_port_ready() {
  local port="$1"

  is_valid_tcp_port "$port" || return 1
  curl --silent --fail --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1
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
