#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/runtime.sh"

APP_NAME="codex-app-extension"

log() {
  printf '[%s] %s\n' "$APP_NAME" "$1"
}

fail() {
  printf '[%s] ERROR: %s\n' "$APP_NAME" "$1" >&2
  exit 1
}

contains_anchor() {
  local file_path="$1"
  local anchor="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -a -q -F -- "$anchor" "$file_path"
    return
  fi

  LC_ALL=C grep -aFq -- "$anchor" "$file_path"
}

append_launch_test_event() {
  local event="$1"

  if [[ -n "${LAUNCH_TEST_EVENTS:-}" ]]; then
    LAUNCH_TEST_EVENTS="${LAUNCH_TEST_EVENTS}|${event}"
  else
    LAUNCH_TEST_EVENTS="$event"
  fi
}

assert_launch_test_equal() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf '[%s] ERROR: %s expected <%s>, got <%s>\n' \
      "$APP_NAME" "$test_name" "$expected" "$actual" >&2
    return 1
  fi
}

install_safe_launch_test_stubs() {
  LAUNCH_TEST_EVENTS=""
  LAUNCH_TEST_PROCESS_RUNNING=0
  PORT=9229

  resolve_codex_app_path() {
    printf '%s\n' "/Applications/ChatGPT.app"
  }

  resolve_codex_node_bin() {
    printf '%s\n' "/stub/node"
  }

  resolve_codex_main_process_name() {
    printf '%s\n' "ChatGPT"
  }

  read_codex_app_bundle_value() {
    case "$2" in
      CFBundleDisplayName)
        printf '%s\n' "ChatGPT"
        ;;
      CFBundleShortVersionString)
        printf '%s\n' "1.0"
        ;;
    esac
  }

  initialize_config_if_missing() {
    return 0
  }

  is_codex_main_process_running() {
    [[ "$LAUNCH_TEST_PROCESS_RUNNING" -eq 1 ]]
  }

  force_terminate_codex_main_process() {
    append_launch_test_event "kill:$1"
    LAUNCH_TEST_PROCESS_RUNNING=0
    return 0
  }

  open_codex_app_with_debugging() {
    append_launch_test_event "open:$1:$2"
    return 0
  }

  wait_for_debug_port() {
    append_launch_test_event "wait:$1"
    return 0
  }

  inject_extension() {
    append_launch_test_event "inject:$1:$2"
    return 0
  }
}

test_force_termination_confirmation_reader() (
  local answer
  local expected_status
  local confirmation_status

  source "$SCRIPT_DIR/launch.sh"

  is_interactive_stdin() {
    return 0
  }

  for answer in "Y" "y" "" "N" "yes" " Y " "y "; do
    case "$answer" in
      Y|y)
        expected_status=0
        ;;
      *)
        expected_status=2
        ;;
    esac

    confirmation_status=0
    confirm_force_termination "ChatGPT" <<< "$answer" >/dev/null 2>&1 \
      || confirmation_status=$?
    assert_launch_test_equal \
      "confirmation reader status for <$answer>" \
      "$expected_status" \
      "$confirmation_status" || return 1
  done

  confirmation_status=0
  confirm_force_termination "ChatGPT" </dev/null >/dev/null 2>&1 \
    || confirmation_status=$?
  assert_launch_test_equal \
    "confirmation reader EOF status" \
    "1" \
    "$confirmation_status"
)

test_valid_tcp_port_boundaries() (
  local port

  source "$SCRIPT_DIR/lib/runtime.sh"

  for port in "1" "65535" "00001" "00065535"; do
    if ! is_valid_tcp_port "$port"; then
      printf '[%s] ERROR: valid TCP port <%s> was rejected\n' \
        "$APP_NAME" "$port" >&2
      return 1
    fi
  done

  for port in "" "abc" "0" "65536"; do
    if is_valid_tcp_port "$port"; then
      printf '[%s] ERROR: invalid TCP port <%s> was accepted\n' \
        "$APP_NAME" "$port" >&2
      return 1
    fi
  done
)

test_resolve_codex_main_process_name() (
  local process_name_case
  local resolved_name
  local resolve_status

  source "$SCRIPT_DIR/lib/runtime.sh"
  RESOLVER_RAW_VALUE="ChatGPT"
  RESOLVER_READER_STATUS=0

  read_codex_app_bundle_value() {
    assert_launch_test_equal \
      "main process resolver app path" \
      "/Selected/ChatGPT.app" \
      "$1" || return 1
    assert_launch_test_equal \
      "main process resolver bundle key" \
      "CFBundleExecutable" \
      "$2" || return 1
    if [[ "$RESOLVER_READER_STATUS" -ne 0 ]]; then
      return "$RESOLVER_READER_STATUS"
    fi
    printf '%s\n' "$RESOLVER_RAW_VALUE"
  }

  resolve_status=0
  resolved_name="$(resolve_codex_main_process_name "/Selected/ChatGPT.app")" \
    || resolve_status=$?
  assert_launch_test_equal \
    "main process resolver normal status" \
    "0" \
    "$resolve_status" || return 1
  assert_launch_test_equal \
    "main process resolver executable" \
    "ChatGPT" \
    "$resolved_name" || return 1

  RESOLVER_READER_STATUS=7
  resolve_status=0
  resolved_name="$(resolve_codex_main_process_name "/Selected/ChatGPT.app")" \
    || resolve_status=$?
  assert_launch_test_equal \
    "main process resolver reader failure status" \
    "7" \
    "$resolve_status" || return 1
  assert_launch_test_equal \
    "main process resolver reader failure output" \
    "" \
    "$resolved_name" || return 1

  RESOLVER_READER_STATUS=0
  for process_name_case in \
    "trailing-lf" \
    "embedded-lf" \
    "carriage-return" \
    "tab" \
    "delete-control"; do
    case "$process_name_case" in
      trailing-lf)
        RESOLVER_RAW_VALUE=$'ChatGPT\n'
        ;;
      embedded-lf)
        RESOLVER_RAW_VALUE=$'Chat\nGPT'
        ;;
      carriage-return)
        RESOLVER_RAW_VALUE=$'Chat\rGPT'
        ;;
      tab)
        RESOLVER_RAW_VALUE=$'Chat\tGPT'
        ;;
      delete-control)
        RESOLVER_RAW_VALUE=$'Chat\x7fGPT'
        ;;
    esac

    resolve_status=0
    resolved_name="$(resolve_codex_main_process_name "/Selected/ChatGPT.app")" \
      || resolve_status=$?
    assert_launch_test_equal \
      "main process resolver $process_name_case status" \
      "2" \
      "$resolve_status" || return 1
    assert_launch_test_equal \
      "main process resolver $process_name_case output" \
      "" \
      "$resolved_name" || return 1
  done
)

test_raw_bundle_identity_scalar_boundaries() (
  local bundle_status=0
  local captured_value
  local identity_case
  local scalar_status=0

  source "$SCRIPT_DIR/lib/runtime.sh"
  identity_case="nul-at-byte-16"

  read_codex_app_bundle_value() {
    case "$identity_case" in
      nul-at-byte-16)
        printf '123456789012345\000tail\n'
        ;;
      bundle-id-extra-trailing-lf)
        printf 'com.openai.codex\n\n'
        ;;
      *)
        return 1
        ;;
    esac
  }

  captured_value="$(
    read_codex_app_bundle_identity_scalar \
      "/Selected/ChatGPT.app" \
      CFBundleExecutable
  )" || scalar_status=$?
  assert_launch_test_equal \
    "raw identity NUL at byte 16 status" \
    "2" \
    "$scalar_status" || return 1
  assert_launch_test_equal \
    "raw identity NUL at byte 16 output" \
    "" \
    "$captured_value" || return 1

  identity_case="bundle-id-extra-trailing-lf"
  bundle_status=0
  is_codex_app_bundle "$SCRIPT_DIR" || bundle_status=$?
  assert_launch_test_equal \
    "raw bundle identifier extra trailing LF status" \
    "2" \
    "$bundle_status"
)

test_process_name_byte_boundaries() (
  local LC_ALL=C
  local ascii_19='Codex.*[](){}+?$^|\'
  local ascii_20="${ascii_19}x"
  local expected_pattern='Codex\.\*\[\]\(\)\{\}\+\?\$\^\|\\'
  local escaped_pattern
  local helper_status
  local multibyte_19=$'\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9A'
  local multibyte_20=$'\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9'
  local process_name

  source "$SCRIPT_DIR/lib/runtime.sh"
  BYTE_BOUNDARY_PGREP_CALLS=0
  BYTE_BOUNDARY_PKILL_CALLS=0

  pgrep() {
    BYTE_BOUNDARY_PGREP_CALLS=$((BYTE_BOUNDARY_PGREP_CALLS + 1))
    return 0
  }

  pkill() {
    BYTE_BOUNDARY_PKILL_CALLS=$((BYTE_BOUNDARY_PKILL_CALLS + 1))
    return 0
  }

  assert_launch_test_equal \
    "safe process name byte length" \
    "19" \
    "${#ascii_19}" || return 1
  helper_status=0
  validate_process_name_safety "$ascii_19" || helper_status=$?
  assert_launch_test_equal \
    "safe process name validation status" \
    "0" \
    "$helper_status" || return 1
  escaped_pattern="$(escape_process_name_for_ere "$ascii_19")" || return $?
  assert_launch_test_equal \
    "safe process name literal ERE" \
    "$expected_pattern" \
    "$escaped_pattern" || return 1

  assert_launch_test_equal \
    "safe multibyte process name byte length" \
    "19" \
    "${#multibyte_19}" || return 1
  helper_status=0
  validate_process_name_safety "$multibyte_19" || helper_status=$?
  assert_launch_test_equal \
    "safe multibyte process name status" \
    "0" \
    "$helper_status" || return 1
  escaped_pattern="$(escape_process_name_for_ere "$multibyte_19")" || return $?
  assert_launch_test_equal \
    "safe multibyte process name literal value" \
    "$multibyte_19" \
    "$escaped_pattern" || return 1

  for process_name in "$ascii_20" "$multibyte_20"; do
    assert_launch_test_equal \
      "unsafe process name byte length" \
      "20" \
      "${#process_name}" || return 1

    helper_status=0
    validate_process_name_safety "$process_name" || helper_status=$?
    assert_launch_test_equal \
      "unsafe process name validation status" \
      "2" \
      "$helper_status" || return 1

    helper_status=0
    escape_process_name_for_ere "$process_name" >/dev/null \
      || helper_status=$?
    assert_launch_test_equal \
      "unsafe process name escape status" \
      "2" \
      "$helper_status" || return 1

    helper_status=0
    is_codex_main_process_running "$process_name" || helper_status=$?
    assert_launch_test_equal \
      "unsafe process name probe status" \
      "2" \
      "$helper_status" || return 1

    helper_status=0
    force_terminate_codex_main_process "$process_name" || helper_status=$?
    assert_launch_test_equal \
      "unsafe process name force status" \
      "2" \
      "$helper_status" || return 1
  done

  assert_launch_test_equal \
    "byte boundary pgrep calls" \
    "0" \
    "$BYTE_BOUNDARY_PGREP_CALLS" || return 1
  assert_launch_test_equal \
    "byte boundary pkill calls" \
    "0" \
    "$BYTE_BOUNDARY_PKILL_CALLS"
)

test_explicit_codex_app_bundle_validation() (
  local resolved_path
  local resolve_status

  source "$SCRIPT_DIR/lib/runtime.sh"
  CODEX_APP="/Explicit/Codex.app"
  BUNDLE_TEST_ID="com.example.not-codex"

  read_codex_app_bundle_value() {
    assert_launch_test_equal \
      "explicit app bundle reader path" \
      "/Explicit/Codex.app" \
      "$1" || return 1
    assert_launch_test_equal \
      "explicit app bundle reader key" \
      "CFBundleIdentifier" \
      "$2" || return 1
    printf '%s\n' "$BUNDLE_TEST_ID"
  }

  is_codex_app_bundle() {
    local bundle_id

    bundle_id="$(read_codex_app_bundle_value "$1" CFBundleIdentifier)" \
      || return $?
    [[ "$bundle_id" == "$CODEX_APP_EXTENSION_BUNDLE_ID" ]]
  }

  resolved_path=""
  resolve_status=0
  resolved_path="$(resolve_codex_app_path)" || resolve_status=$?
  assert_launch_test_equal \
    "explicit app wrong bundle status" \
    "1" \
    "$resolve_status" || return 1
  assert_launch_test_equal \
    "explicit app wrong bundle path" \
    "" \
    "$resolved_path" || return 1

  BUNDLE_TEST_ID="$CODEX_APP_EXTENSION_BUNDLE_ID"
  resolve_status=0
  resolved_path="$(resolve_codex_app_path)" || resolve_status=$?
  assert_launch_test_equal \
    "explicit app valid bundle status" \
    "0" \
    "$resolve_status" || return 1
  assert_launch_test_equal \
    "explicit app valid bundle path" \
    "/Explicit/Codex.app" \
    "$resolved_path"
)

test_literal_ere_process_name() (
  local expected_pattern='Codex\.\*\[\]\(\)\{\}\+\?\$\^\|\\'
  local process_name='Codex.*[](){}+?$^|\'
  local escaped_pattern
  local helper_status

  source "$SCRIPT_DIR/lib/runtime.sh"
  PROCESS_LITERAL_BAD_ARGUMENTS=0
  PROCESS_LITERAL_EVENTS=""
  PROCESS_LITERAL_PGREP_CALLS=0

  escaped_pattern="$(escape_process_name_for_ere "$process_name")" || return $?
  assert_launch_test_equal \
    "literal ERE escaped pattern" \
    "$expected_pattern" \
    "$escaped_pattern" || return 1

  pgrep() {
    PROCESS_LITERAL_PGREP_CALLS=$((PROCESS_LITERAL_PGREP_CALLS + 1))
    if [[ "$#" -ne 2 || "$1" != "-x" || "$2" != "$expected_pattern" ]]; then
      PROCESS_LITERAL_BAD_ARGUMENTS=1
    fi
    append_process_helper_event "pgrep:$*"
    if [[ "$PROCESS_LITERAL_PGREP_CALLS" -le 2 ]]; then
      return 0
    fi
    return 1
  }

  pkill() {
    if [[ "$#" -ne 3 \
      || "$1" != "-KILL" \
      || "$2" != "-x" \
      || "$3" != "$expected_pattern" ]]; then
      PROCESS_LITERAL_BAD_ARGUMENTS=1
    fi
    append_process_helper_event "pkill:$*"
    return 0
  }

  sleep() {
    append_process_helper_event "sleep:$*"
    return 0
  }

  append_process_helper_event() {
    local event="$1"

    if [[ -n "$PROCESS_LITERAL_EVENTS" ]]; then
      PROCESS_LITERAL_EVENTS="${PROCESS_LITERAL_EVENTS}|${event}"
    else
      PROCESS_LITERAL_EVENTS="$event"
    fi
  }

  helper_status=0
  is_codex_main_process_running "$process_name" || helper_status=$?
  assert_launch_test_equal \
    "literal ERE process probe status" \
    "0" \
    "$helper_status" || return 1

  helper_status=0
  force_terminate_codex_main_process "$process_name" || helper_status=$?
  assert_launch_test_equal \
    "literal ERE force status" \
    "0" \
    "$helper_status" || return 1
  assert_launch_test_equal \
    "literal ERE command argument safety" \
    "0" \
    "$PROCESS_LITERAL_BAD_ARGUMENTS" || return 1
  assert_launch_test_equal \
    "literal ERE command events" \
    "pgrep:-x $expected_pattern|pgrep:-x $expected_pattern|pkill:-KILL -x $expected_pattern|pgrep:-x $expected_pattern" \
    "$PROCESS_LITERAL_EVENTS"
)

test_unsafe_process_names_are_rejected() (
  local process_name
  local helper_status

  source "$SCRIPT_DIR/lib/runtime.sh"
  UNSAFE_PROCESS_PGREP_CALLS=0
  UNSAFE_PROCESS_PKILL_CALLS=0
  UNSAFE_PROCESS_SLEEP_CALLS=0
  UNSAFE_PROCESS_OPEN_CALLS=0

  pgrep() {
    UNSAFE_PROCESS_PGREP_CALLS=$((UNSAFE_PROCESS_PGREP_CALLS + 1))
    return 0
  }

  pkill() {
    UNSAFE_PROCESS_PKILL_CALLS=$((UNSAFE_PROCESS_PKILL_CALLS + 1))
    return 0
  }

  sleep() {
    UNSAFE_PROCESS_SLEEP_CALLS=$((UNSAFE_PROCESS_SLEEP_CALLS + 1))
    return 0
  }

  open() {
    UNSAFE_PROCESS_OPEN_CALLS=$((UNSAFE_PROCESS_OPEN_CALLS + 1))
    return 0
  }

  for process_name in "" "-ChatGPT" $'Chat\nGPT' $'Chat\rGPT'; do
    helper_status=0
    escape_process_name_for_ere "$process_name" >/dev/null \
      || helper_status=$?
    assert_launch_test_equal \
      "unsafe process escape status" \
      "2" \
      "$helper_status" || return 1

    helper_status=0
    is_codex_main_process_running "$process_name" || helper_status=$?
    assert_launch_test_equal \
      "unsafe process probe status" \
      "2" \
      "$helper_status" || return 1

    helper_status=0
    force_terminate_codex_main_process "$process_name" || helper_status=$?
    assert_launch_test_equal \
      "unsafe process force status" \
      "2" \
      "$helper_status" || return 1
  done

  assert_launch_test_equal \
    "unsafe process pgrep calls" \
    "0" \
    "$UNSAFE_PROCESS_PGREP_CALLS" || return 1
  assert_launch_test_equal \
    "unsafe process pkill calls" \
    "0" \
    "$UNSAFE_PROCESS_PKILL_CALLS" || return 1
  assert_launch_test_equal \
    "unsafe process sleep calls" \
    "0" \
    "$UNSAFE_PROCESS_SLEEP_CALLS" || return 1
  assert_launch_test_equal \
    "unsafe process open calls" \
    "0" \
    "$UNSAFE_PROCESS_OPEN_CALLS"
)

test_exact_process_probe_statuses() (
  local probe_status

  source "$SCRIPT_DIR/lib/runtime.sh"
  PROCESS_PROBE_ARGUMENTS=""
  PROCESS_PROBE_RAW_STATUS=0

  pgrep() {
    PROCESS_PROBE_ARGUMENTS="$*"
    return "$PROCESS_PROBE_RAW_STATUS"
  }

  probe_status=0
  is_codex_main_process_running "ChatGPT" || probe_status=$?
  assert_launch_test_equal \
    "exact process probe running status" \
    "0" \
    "$probe_status" || return 1
  assert_launch_test_equal \
    "exact process probe running arguments" \
    "-x ChatGPT" \
    "$PROCESS_PROBE_ARGUMENTS" || return 1

  PROCESS_PROBE_ARGUMENTS=""
  PROCESS_PROBE_RAW_STATUS=1
  probe_status=0
  is_codex_main_process_running "ChatGPT" || probe_status=$?
  assert_launch_test_equal \
    "exact process probe absent status" \
    "1" \
    "$probe_status" || return 1
  assert_launch_test_equal \
    "exact process probe absent arguments" \
    "-x ChatGPT" \
    "$PROCESS_PROBE_ARGUMENTS" || return 1

  PROCESS_PROBE_ARGUMENTS=""
  PROCESS_PROBE_RAW_STATUS=3
  probe_status=0
  is_codex_main_process_running "ChatGPT" || probe_status=$?
  assert_launch_test_equal \
    "exact process probe error status" \
    "2" \
    "$probe_status" || return 1
  assert_launch_test_equal \
    "exact process probe error arguments" \
    "-x ChatGPT" \
    "$PROCESS_PROBE_ARGUMENTS"
)

test_exact_force_termination_helpers() (
  local helper_status

  source "$SCRIPT_DIR/lib/runtime.sh"
  PROCESS_HELPER_EVENTS=""
  PROCESS_HELPER_PGREP_CALLS=0

  append_process_helper_event() {
    local event="$1"

    if [[ -n "$PROCESS_HELPER_EVENTS" ]]; then
      PROCESS_HELPER_EVENTS="${PROCESS_HELPER_EVENTS}|${event}"
    else
      PROCESS_HELPER_EVENTS="$event"
    fi
  }

  pgrep() {
    append_process_helper_event "pgrep:$*"
    PROCESS_HELPER_PGREP_CALLS=$((PROCESS_HELPER_PGREP_CALLS + 1))
    if [[ "$PROCESS_HELPER_PGREP_CALLS" -eq 1 ]]; then
      return 0
    fi
    return 1
  }

  pkill() {
    append_process_helper_event "pkill:$*"
    return 0
  }

  sleep() {
    append_process_helper_event "sleep:$*"
    return 0
  }

  helper_status=0
  force_terminate_codex_main_process "ChatGPT" || helper_status=$?
  assert_launch_test_equal \
    "exact force termination status" \
    "0" \
    "$helper_status" || return 1
  assert_launch_test_equal \
    "exact force termination events" \
    "pgrep:-x ChatGPT|pkill:-KILL -x ChatGPT|pgrep:-x ChatGPT" \
    "$PROCESS_HELPER_EVENTS" || return 1

  PROCESS_HELPER_EVENTS=""
  pgrep() {
    append_process_helper_event "pgrep:$*"
    return 3
  }
  pkill() {
    append_process_helper_event "pkill:$*"
    return 0
  }
  sleep() {
    append_process_helper_event "sleep:$*"
    return 0
  }

  helper_status=0
  force_terminate_codex_main_process "ChatGPT" || helper_status=$?
  assert_launch_test_equal \
    "force termination probe error status" \
    "2" \
    "$helper_status" || return 1
  assert_launch_test_equal \
    "force termination probe error events" \
    "pgrep:-x ChatGPT" \
    "$PROCESS_HELPER_EVENTS" || return 1

  PROCESS_HELPER_EVENTS=""
  PROCESS_HELPER_PGREP_CALLS=0
  pgrep() {
    append_process_helper_event "pgrep:$*"
    PROCESS_HELPER_PGREP_CALLS=$((PROCESS_HELPER_PGREP_CALLS + 1))
    if [[ "$PROCESS_HELPER_PGREP_CALLS" -eq 1 ]]; then
      return 0
    fi
    return 3
  }
  pkill() {
    append_process_helper_event "pkill:$*"
    return 0
  }
  sleep() {
    append_process_helper_event "sleep:$*"
    return 0
  }

  helper_status=0
  wait_for_codex_main_process_exit "ChatGPT" || helper_status=$?
  assert_launch_test_equal \
    "wait helper probe error status" \
    "2" \
    "$helper_status" || return 1
  assert_launch_test_equal \
    "wait helper probe error events" \
    "pgrep:-x ChatGPT|sleep:0.1|pgrep:-x ChatGPT" \
    "$PROCESS_HELPER_EVENTS"
)

test_failed_pkill_final_probe_statuses() (
  local expected_status
  local helper_status
  local probe_mode

  source "$SCRIPT_DIR/lib/runtime.sh"
  PKILL_FAILURE_MODE=""
  PKILL_FAILURE_EVENTS=""
  PKILL_FAILURE_PGREP_CALLS=0
  PKILL_FAILURE_BAD_ARGUMENTS=0
  PKILL_FAILURE_SLEEP_CALLS=0
  PKILL_FAILURE_OPEN_CALLS=0

  append_pkill_failure_event() {
    local event="$1"

    if [[ -n "$PKILL_FAILURE_EVENTS" ]]; then
      PKILL_FAILURE_EVENTS="${PKILL_FAILURE_EVENTS}|${event}"
    else
      PKILL_FAILURE_EVENTS="$event"
    fi
  }

  pgrep() {
    PKILL_FAILURE_PGREP_CALLS=$((PKILL_FAILURE_PGREP_CALLS + 1))
    if [[ "$#" -ne 2 || "$1" != "-x" || "$2" != "ChatGPT" ]]; then
      PKILL_FAILURE_BAD_ARGUMENTS=1
    fi
    append_pkill_failure_event "pgrep:$*"
    if [[ "$PKILL_FAILURE_PGREP_CALLS" -eq 1 ]]; then
      return 0
    fi
    case "$PKILL_FAILURE_MODE" in
      absent)
        return 1
        ;;
      running)
        return 0
        ;;
      error)
        return 3
        ;;
    esac
    return 3
  }

  pkill() {
    if [[ "$#" -ne 3 \
      || "$1" != "-KILL" \
      || "$2" != "-x" \
      || "$3" != "ChatGPT" ]]; then
      PKILL_FAILURE_BAD_ARGUMENTS=1
    fi
    append_pkill_failure_event "pkill:$*"
    return 9
  }

  sleep() {
    PKILL_FAILURE_SLEEP_CALLS=$((PKILL_FAILURE_SLEEP_CALLS + 1))
    return 0
  }

  open() {
    PKILL_FAILURE_OPEN_CALLS=$((PKILL_FAILURE_OPEN_CALLS + 1))
    return 0
  }

  for probe_mode in absent running error; do
    case "$probe_mode" in
      absent)
        expected_status=0
        ;;
      running)
        expected_status=1
        ;;
      error)
        expected_status=2
        ;;
    esac

    PKILL_FAILURE_MODE="$probe_mode"
    PKILL_FAILURE_EVENTS=""
    PKILL_FAILURE_PGREP_CALLS=0
    PKILL_FAILURE_BAD_ARGUMENTS=0
    PKILL_FAILURE_SLEEP_CALLS=0
    PKILL_FAILURE_OPEN_CALLS=0
    helper_status=0
    force_terminate_codex_main_process "ChatGPT" || helper_status=$?

    assert_launch_test_equal \
      "failed pkill $probe_mode final status" \
      "$expected_status" \
      "$helper_status" || return 1
    assert_launch_test_equal \
      "failed pkill $probe_mode events" \
      "pgrep:-x ChatGPT|pkill:-KILL -x ChatGPT|pgrep:-x ChatGPT" \
      "$PKILL_FAILURE_EVENTS" || return 1
    assert_launch_test_equal \
      "failed pkill $probe_mode argument safety" \
      "0" \
      "$PKILL_FAILURE_BAD_ARGUMENTS" || return 1
    assert_launch_test_equal \
      "failed pkill $probe_mode sleep calls" \
      "0" \
      "$PKILL_FAILURE_SLEEP_CALLS" || return 1
    assert_launch_test_equal \
      "failed pkill $probe_mode open calls" \
      "0" \
      "$PKILL_FAILURE_OPEN_CALLS" || return 1
  done
)

test_ready_configured_port() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=1

  is_debug_port_ready() {
    [[ "$1" == "9229" ]]
  }

  discover_codex_debug_ports() {
    return 0
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 99
  }

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "T1 configured ready port status" \
    "0" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "T1 configured ready port actions" \
    "inject:/stub/node:9229" \
    "$LAUNCH_TEST_EVENTS"
)

test_ready_discovered_port() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=1

  is_debug_port_ready() {
    [[ "$1" == "9333" ]]
  }

  discover_codex_debug_ports() {
    printf '%s\n' "9333"
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 99
  }

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "T1 discovered ready port status" \
    "0" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "T1 discovered ready port actions" \
    "inject:/stub/node:9333" \
    "$LAUNCH_TEST_EVENTS"
)

test_ready_debugger_injection_failure() (
  local launch_status=0
  local stderr_file="${TMPDIR:-/tmp}/codex-app-extension-ready-inject-$$.err"
  local stderr_output
  local stdout_file="${TMPDIR:-/tmp}/codex-app-extension-ready-inject-$$.out"
  local stdout_output

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=1
  umask 077
  : >"$stdout_file"
  : >"$stderr_file"
  trap 'rm -f "$stdout_file" "$stderr_file"' EXIT

  is_debug_port_ready() {
    [[ "$1" == "9229" ]]
  }

  discover_codex_debug_ports() {
    return 0
  }

  inject_extension() {
    append_launch_test_event "inject:$1:$2"
    return 7
  }

  if launch_main >"$stdout_file" 2>"$stderr_file"; then
    launch_status=0
  else
    launch_status=$?
  fi
  stdout_output="$(<"$stdout_file")"
  stderr_output="$(<"$stderr_file")"

  assert_launch_test_equal \
    "ready debugger injection failure status" \
    "7" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "ready debugger injection failure actions" \
    "inject:/stub/node:9229" \
    "$LAUNCH_TEST_EVENTS" || return 1
  case "$stderr_output" in
    *"Extension injection failed on debugger port 9229."*)
      ;;
    *)
      printf '[%s] ERROR: ready debugger injection failure was not reported on stderr\n' \
        "$APP_NAME" >&2
      return 1
      ;;
  esac
  case "${stdout_output}${stderr_output}" in
    *"Done."*)
      printf '[%s] ERROR: ready debugger injection failure printed Done.\n' \
        "$APP_NAME" >&2
      return 1
      ;;
  esac
)

test_confirmed_relaunch() (
  local test_name="$1"
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=1

  find_ready_debug_port() {
    return 1
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 0
  }

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "$test_name confirmed relaunch status" \
    "0" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "$test_name confirmed relaunch actions" \
    "confirm:ChatGPT|kill:ChatGPT|open:/Applications/ChatGPT.app:9229|wait:9229|inject:/stub/node:9229" \
    "$LAUNCH_TEST_EVENTS"
)

test_safe_confirmation_cancel() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=1

  find_ready_debug_port() {
    return 1
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 2
  }

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "T4 safe cancellation status" \
    "0" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "T4 safe cancellation actions" \
    "confirm:ChatGPT" \
    "$LAUNCH_TEST_EVENTS"
)

test_non_tty_confirmation_failure() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=1

  find_ready_debug_port() {
    return 1
  }

  launch_main </dev/null >/dev/null 2>&1 || launch_status=$?
  if [[ "$launch_status" -eq 0 ]]; then
    printf '[%s] ERROR: T5 non-TTY confirmation unexpectedly succeeded\n' "$APP_NAME" >&2
    return 1
  fi
  assert_launch_test_equal \
    "T5 non-TTY destructive actions" \
    "" \
    "$LAUNCH_TEST_EVENTS"
)

test_normal_debug_launch() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=0

  find_ready_debug_port() {
    return 1
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 99
  }

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "T6 normal launch status" \
    "0" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "T6 normal launch actions" \
    "open:/Applications/ChatGPT.app:9229|wait:9229|inject:/stub/node:9229" \
    "$LAUNCH_TEST_EVENTS"
)

test_launched_debugger_injection_failure() (
  local launch_status=0
  local stderr_file="${TMPDIR:-/tmp}/codex-app-extension-open-inject-$$.err"
  local stderr_output
  local stdout_file="${TMPDIR:-/tmp}/codex-app-extension-open-inject-$$.out"
  local stdout_output

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs
  LAUNCH_TEST_PROCESS_RUNNING=0
  umask 077
  : >"$stdout_file"
  : >"$stderr_file"
  trap 'rm -f "$stdout_file" "$stderr_file"' EXIT

  find_ready_debug_port() {
    return 1
  }

  inject_extension() {
    append_launch_test_event "inject:$1:$2"
    return 7
  }

  launch_main >"$stdout_file" 2>"$stderr_file" || launch_status=$?
  stdout_output="$(<"$stdout_file")"
  stderr_output="$(<"$stderr_file")"

  assert_launch_test_equal \
    "launched debugger injection failure status" \
    "7" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "launched debugger injection failure actions" \
    "open:/Applications/ChatGPT.app:9229|wait:9229|inject:/stub/node:9229" \
    "$LAUNCH_TEST_EVENTS" || return 1
  case "$stderr_output" in
    *"Extension injection failed after launching /Applications/ChatGPT.app."*)
      ;;
    *)
      printf '[%s] ERROR: launched debugger injection failure was not reported on stderr\n' \
        "$APP_NAME" >&2
      return 1
      ;;
  esac
  case "${stdout_output}${stderr_output}" in
    *"Done."*)
      printf '[%s] ERROR: launched debugger injection failure printed Done.\n' \
        "$APP_NAME" >&2
      return 1
      ;;
  esac
)

test_process_probe_error_blocks_launch() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs

  find_ready_debug_port() {
    return 1
  }

  is_codex_main_process_running() {
    return 2
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 0
  }

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "process probe error launch status" \
    "2" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "process probe error launch actions" \
    "" \
    "$LAUNCH_TEST_EVENTS"
)

test_invalid_port_blocks_launch() (
  local invalid_port
  local launch_status

  source "$SCRIPT_DIR/launch.sh"
  install_safe_launch_test_stubs

  initialize_config_if_missing() {
    append_launch_test_event "config"
    return 0
  }

  is_debug_port_ready() {
    return 1
  }

  discover_codex_debug_ports() {
    return 0
  }

  is_codex_main_process_running() {
    append_launch_test_event "process:$1"
    return 0
  }

  confirm_force_termination() {
    append_launch_test_event "confirm:$1"
    return 0
  }

  force_terminate_codex_main_process() {
    append_launch_test_event "kill:$1"
    return 0
  }

  open_codex_app_with_debugging() {
    append_launch_test_event "open:$1:$2"
    return 0
  }

  wait_for_debug_port() {
    append_launch_test_event "wait:$1"
    return 0
  }

  inject_extension() {
    append_launch_test_event "inject:$1:$2"
    return 0
  }

  for invalid_port in "abc" "0" "65536"; do
    PORT="$invalid_port"
    LAUNCH_TEST_EVENTS=""
    launch_status=0
    launch_main >/dev/null 2>&1 || launch_status=$?
    if [[ "$launch_status" -eq 0 ]]; then
      printf '[%s] ERROR: invalid launch port <%s> unexpectedly succeeded\n' \
        "$APP_NAME" "$invalid_port" >&2
      return 1
    fi
    assert_launch_test_equal \
      "invalid launch port <$invalid_port> actions" \
      "config" \
      "$LAUNCH_TEST_EVENTS" || return 1
  done
)

append_raw_process_launch_event() {
  printf '%s\n' "$1" >>"$RAW_PROCESS_LAUNCH_EVENT_FILE"
}

read_raw_process_launch_events() {
  local event
  local events=""

  while IFS= read -r event; do
    if [[ -n "$events" ]]; then
      events="${events}|${event}"
    else
      events="$event"
    fi
  done <"$RAW_PROCESS_LAUNCH_EVENT_FILE"

  printf '%s' "$events"
}

install_raw_process_launch_test_stubs() {
  PORT=9229

  resolve_codex_app_path() {
    append_raw_process_launch_event "app"
    printf '%s\n' "/Applications/ChatGPT.app"
  }

  resolve_codex_node_bin() {
    append_raw_process_launch_event "node"
    printf '%s\n' "/stub/node"
  }

  read_codex_app_bundle_value() {
    append_raw_process_launch_event "bundle:$2"
    if [[ "$2" == "CFBundleExecutable" ]]; then
      if [[ "$RAW_PROCESS_READER_STATUS" -ne 0 ]]; then
        return "$RAW_PROCESS_READER_STATUS"
      fi
      case "${RAW_PROCESS_BUNDLE_OUTPUT:-variable}" in
        nul-at-byte-16)
          printf '123456789012345\000tail\n'
          ;;
        variable)
          printf '%s\n' "$RAW_PROCESS_BUNDLE_VALUE"
          ;;
        *)
          return 1
          ;;
      esac
      return 0
    fi

    case "$2" in
      CFBundleDisplayName)
        printf '%s\n' "ChatGPT"
        ;;
      CFBundleShortVersionString)
        printf '%s\n' "1.0"
        ;;
    esac
  }

  initialize_config_if_missing() {
    append_raw_process_launch_event "config"
    return 0
  }

  is_debug_port_ready() {
    append_raw_process_launch_event "cdp-ready"
    return 1
  }

  discover_codex_debug_ports() {
    append_raw_process_launch_event "cdp-discover"
    return 0
  }

  confirm_force_termination() {
    append_raw_process_launch_event "confirm"
    return 0
  }

  open_codex_app_with_debugging() {
    append_raw_process_launch_event "launch-open"
    return 0
  }

  wait_for_debug_port() {
    append_raw_process_launch_event "debug-wait"
    return 0
  }

  inject_extension() {
    append_raw_process_launch_event "inject"
    return 0
  }

  pgrep() {
    append_raw_process_launch_event "pgrep"
    return 1
  }

  pkill() {
    append_raw_process_launch_event "pkill"
    return 0
  }

  open() {
    append_raw_process_launch_event "open"
    return 0
  }

  sleep() {
    append_raw_process_launch_event "sleep"
    return 0
  }
}

test_raw_process_reader_failure_blocks_launch() (
  local launch_status=0
  local observed_events

  source "$SCRIPT_DIR/launch.sh"
  RAW_PROCESS_LAUNCH_EVENT_FILE="${TMPDIR:-/tmp}/codex-app-extension-reader-failure-$$.events"
  RAW_PROCESS_BUNDLE_VALUE="ChatGPT"
  RAW_PROCESS_BUNDLE_OUTPUT="variable"
  RAW_PROCESS_READER_STATUS=7
  umask 077
  : >"$RAW_PROCESS_LAUNCH_EVENT_FILE"
  trap 'rm -f "$RAW_PROCESS_LAUNCH_EVENT_FILE"' EXIT
  install_raw_process_launch_test_stubs

  launch_main >/dev/null 2>&1 || launch_status=$?
  observed_events="$(read_raw_process_launch_events)"

  assert_launch_test_equal \
    "raw process reader failure launch status" \
    "7" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "raw process reader failure launch boundaries" \
    "app|node|bundle:CFBundleExecutable" \
    "$observed_events"
)

test_raw_process_nul_blocks_launch() (
  local launch_status=0
  local observed_events

  source "$SCRIPT_DIR/launch.sh"
  RAW_PROCESS_LAUNCH_EVENT_FILE="${TMPDIR:-/tmp}/codex-app-extension-nul-raw-$$.events"
  RAW_PROCESS_BUNDLE_VALUE=""
  RAW_PROCESS_BUNDLE_OUTPUT="nul-at-byte-16"
  RAW_PROCESS_READER_STATUS=0
  umask 077
  : >"$RAW_PROCESS_LAUNCH_EVENT_FILE"
  trap 'rm -f "$RAW_PROCESS_LAUNCH_EVENT_FILE"' EXIT
  install_raw_process_launch_test_stubs

  launch_main >/dev/null 2>&1 || launch_status=$?
  observed_events="$(read_raw_process_launch_events)"

  assert_launch_test_equal \
    "raw process NUL launch status" \
    "2" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "raw process NUL launch boundaries" \
    "app|node|bundle:CFBundleExecutable" \
    "$observed_events"
)

test_unsafe_raw_process_values_block_launch() (
  local launch_status
  local observed_events
  local process_name_case

  source "$SCRIPT_DIR/launch.sh"
  RAW_PROCESS_LAUNCH_EVENT_FILE="${TMPDIR:-/tmp}/codex-app-extension-unsafe-raw-$$.events"
  RAW_PROCESS_BUNDLE_OUTPUT="variable"
  RAW_PROCESS_READER_STATUS=0
  umask 077
  : >"$RAW_PROCESS_LAUNCH_EVENT_FILE"
  trap 'rm -f "$RAW_PROCESS_LAUNCH_EVENT_FILE"' EXIT
  install_raw_process_launch_test_stubs

  for process_name_case in \
    "empty" \
    "leading-dash" \
    "trailing-lf" \
    "embedded-lf" \
    "carriage-return" \
    "tab" \
    "delete-control" \
    "ascii-20" \
    "utf8-20"; do
    case "$process_name_case" in
      empty)
        RAW_PROCESS_BUNDLE_VALUE=""
        ;;
      leading-dash)
        RAW_PROCESS_BUNDLE_VALUE="-ChatGPT"
        ;;
      trailing-lf)
        RAW_PROCESS_BUNDLE_VALUE=$'ChatGPT\n'
        ;;
      embedded-lf)
        RAW_PROCESS_BUNDLE_VALUE=$'Chat\nGPT'
        ;;
      carriage-return)
        RAW_PROCESS_BUNDLE_VALUE=$'Chat\rGPT'
        ;;
      tab)
        RAW_PROCESS_BUNDLE_VALUE=$'Chat\tGPT'
        ;;
      delete-control)
        RAW_PROCESS_BUNDLE_VALUE=$'Chat\x7fGPT'
        ;;
      ascii-20)
        RAW_PROCESS_BUNDLE_VALUE="12345678901234567890"
        ;;
      utf8-20)
        RAW_PROCESS_BUNDLE_VALUE=$'\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9'
        ;;
    esac

    : >"$RAW_PROCESS_LAUNCH_EVENT_FILE"
    launch_status=0
    launch_main >/dev/null 2>&1 || launch_status=$?
    observed_events="$(read_raw_process_launch_events)"

    assert_launch_test_equal \
      "unsafe raw process $process_name_case launch status" \
      "2" \
      "$launch_status" || return 1
    assert_launch_test_equal \
      "unsafe raw process $process_name_case launch boundaries" \
      "app|node|bundle:CFBundleExecutable" \
      "$observed_events" || return 1
  done
)

install_process_boundary_launch_test_stubs() {
  PORT=9229
  PROCESS_BOUNDARY_PGREP_CALLS=0
  PROCESS_BOUNDARY_PKILL_CALLS=0
  PROCESS_BOUNDARY_SLEEP_CALLS=0
  PROCESS_BOUNDARY_OPEN_CALLS=0
  PROCESS_BOUNDARY_DEBUG_WAIT_CALLS=0
  PROCESS_BOUNDARY_INJECT_CALLS=0
  PROCESS_BOUNDARY_BAD_ARGUMENTS=0

  resolve_codex_app_path() {
    printf '%s\n' "/Applications/ChatGPT.app"
  }

  resolve_codex_node_bin() {
    printf '%s\n' "/stub/node"
  }

  resolve_codex_main_process_name() {
    printf '%s\n' "ChatGPT"
  }

  read_codex_app_bundle_value() {
    case "$2" in
      CFBundleDisplayName)
        printf '%s\n' "ChatGPT"
        ;;
      CFBundleShortVersionString)
        printf '%s\n' "1.0"
        ;;
    esac
  }

  initialize_config_if_missing() {
    return 0
  }

  is_debug_port_ready() {
    return 1
  }

  discover_codex_debug_ports() {
    return 0
  }

  confirm_force_termination() {
    return 0
  }

  open_codex_app_with_debugging() {
    PROCESS_BOUNDARY_OPEN_CALLS=$((PROCESS_BOUNDARY_OPEN_CALLS + 1))
    return 0
  }

  wait_for_debug_port() {
    PROCESS_BOUNDARY_DEBUG_WAIT_CALLS=$((PROCESS_BOUNDARY_DEBUG_WAIT_CALLS + 1))
    return 0
  }

  inject_extension() {
    PROCESS_BOUNDARY_INJECT_CALLS=$((PROCESS_BOUNDARY_INJECT_CALLS + 1))
    return 0
  }

  pgrep() {
    PROCESS_BOUNDARY_PGREP_CALLS=$((PROCESS_BOUNDARY_PGREP_CALLS + 1))
    if [[ "$*" != "-x ChatGPT" ]]; then
      PROCESS_BOUNDARY_BAD_ARGUMENTS=1
    fi

    case "$PROCESS_BOUNDARY_PGREP_MODE" in
      error-after-kill)
        if [[ "$PROCESS_BOUNDARY_PGREP_CALLS" -le 2 ]]; then
          return 0
        fi
        return 3
        ;;
      final-running)
        case "$PROCESS_BOUNDARY_PGREP_CALLS" in
          1|2|4)
            return 0
            ;;
          3)
            return 1
            ;;
        esac
        return 3
        ;;
      final-error)
        case "$PROCESS_BOUNDARY_PGREP_CALLS" in
          1|2)
            return 0
            ;;
          3)
            return 1
            ;;
          4)
            return 3
            ;;
        esac
        return 3
        ;;
      always-running)
        return 0
        ;;
      *)
        return 3
        ;;
    esac
  }

  pkill() {
    PROCESS_BOUNDARY_PKILL_CALLS=$((PROCESS_BOUNDARY_PKILL_CALLS + 1))
    if [[ "$*" != "-KILL -x ChatGPT" ]]; then
      PROCESS_BOUNDARY_BAD_ARGUMENTS=1
    fi
    return 0
  }

  sleep() {
    PROCESS_BOUNDARY_SLEEP_CALLS=$((PROCESS_BOUNDARY_SLEEP_CALLS + 1))
    if [[ "$*" != "0.1" ]]; then
      PROCESS_BOUNDARY_BAD_ARGUMENTS=1
    fi
    return 0
  }
}

test_launch_force_termination_probe_error() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_process_boundary_launch_test_stubs
  PROCESS_BOUNDARY_PGREP_MODE="error-after-kill"

  launch_main >/dev/null 2>&1 || launch_status=$?
  assert_launch_test_equal \
    "launch force termination probe error status" \
    "2" \
    "$launch_status" || return 1
  assert_launch_test_equal \
    "launch force termination probe error pgrep calls" \
    "3" \
    "$PROCESS_BOUNDARY_PGREP_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination probe error pkill calls" \
    "1" \
    "$PROCESS_BOUNDARY_PKILL_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination probe error sleep calls" \
    "0" \
    "$PROCESS_BOUNDARY_SLEEP_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination probe error open calls" \
    "0" \
    "$PROCESS_BOUNDARY_OPEN_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination probe error debug wait calls" \
    "0" \
    "$PROCESS_BOUNDARY_DEBUG_WAIT_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination probe error inject calls" \
    "0" \
    "$PROCESS_BOUNDARY_INJECT_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination probe error command arguments" \
    "0" \
    "$PROCESS_BOUNDARY_BAD_ARGUMENTS"
)

test_launch_final_process_recheck() (
  local expected_status
  local launch_status
  local probe_mode

  source "$SCRIPT_DIR/launch.sh"

  for probe_mode in final-running final-error; do
    install_process_boundary_launch_test_stubs
    PROCESS_BOUNDARY_PGREP_MODE="$probe_mode"
    case "$probe_mode" in
      final-running)
        expected_status=1
        ;;
      final-error)
        expected_status=2
        ;;
    esac

    launch_status=0
    if launch_main >/dev/null 2>&1; then
      launch_status=0
    else
      launch_status=$?
    fi

    assert_launch_test_equal \
      "launch $probe_mode status" \
      "$expected_status" \
      "$launch_status" || return 1
    assert_launch_test_equal \
      "launch $probe_mode pgrep calls" \
      "4" \
      "$PROCESS_BOUNDARY_PGREP_CALLS" || return 1
    assert_launch_test_equal \
      "launch $probe_mode pkill calls" \
      "1" \
      "$PROCESS_BOUNDARY_PKILL_CALLS" || return 1
    assert_launch_test_equal \
      "launch $probe_mode wait sleep calls" \
      "0" \
      "$PROCESS_BOUNDARY_SLEEP_CALLS" || return 1
    assert_launch_test_equal \
      "launch $probe_mode open calls" \
      "0" \
      "$PROCESS_BOUNDARY_OPEN_CALLS" || return 1
    assert_launch_test_equal \
      "launch $probe_mode debug wait calls" \
      "0" \
      "$PROCESS_BOUNDARY_DEBUG_WAIT_CALLS" || return 1
    assert_launch_test_equal \
      "launch $probe_mode inject calls" \
      "0" \
      "$PROCESS_BOUNDARY_INJECT_CALLS" || return 1
    assert_launch_test_equal \
      "launch $probe_mode command arguments" \
      "0" \
      "$PROCESS_BOUNDARY_BAD_ARGUMENTS" || return 1
  done
)

test_launch_force_termination_timeout() (
  local launch_status=0

  source "$SCRIPT_DIR/launch.sh"
  install_process_boundary_launch_test_stubs
  PROCESS_BOUNDARY_PGREP_MODE="always-running"

  launch_main >/dev/null 2>&1 || launch_status=$?
  if [[ "$launch_status" -eq 0 ]]; then
    printf '[%s] ERROR: launch force termination timeout unexpectedly succeeded\n' \
      "$APP_NAME" >&2
    return 1
  fi
  assert_launch_test_equal \
    "launch force termination timeout pgrep calls" \
    "52" \
    "$PROCESS_BOUNDARY_PGREP_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination timeout pkill calls" \
    "1" \
    "$PROCESS_BOUNDARY_PKILL_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination timeout bounded sleep calls" \
    "50" \
    "$PROCESS_BOUNDARY_SLEEP_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination timeout open calls" \
    "0" \
    "$PROCESS_BOUNDARY_OPEN_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination timeout debug wait calls" \
    "0" \
    "$PROCESS_BOUNDARY_DEBUG_WAIT_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination timeout inject calls" \
    "0" \
    "$PROCESS_BOUNDARY_INJECT_CALLS" || return 1
  assert_launch_test_equal \
    "launch force termination timeout command arguments" \
    "0" \
    "$PROCESS_BOUNDARY_BAD_ARGUMENTS"
)

test_unready_discovered_port() (
  local selected_port

  source "$SCRIPT_DIR/launch.sh"

  is_debug_port_ready() {
    [[ "$1" == "not-a-port" ]]
  }

  discover_codex_debug_ports() {
    printf '%s\n' "not-a-port" "9333"
  }

  selected_port="$(find_ready_debug_port 9229 || true)"
  assert_launch_test_equal \
    "T7 invalid or unready discovered port" \
    "" \
    "$selected_port"
)

test_debug_port_http_contract() (
  local curl_arguments=""
  local invalid_status=0

  source "$SCRIPT_DIR/launch.sh"

  curl() {
    curl_arguments="$*"
    return 0
  }

  is_debug_port_ready "not-a-port" || invalid_status=$?
  if [[ "$invalid_status" -eq 0 ]]; then
    printf '[%s] ERROR: HTTP contract accepted a nonnumeric port\n' "$APP_NAME" >&2
    return 1
  fi
  assert_launch_test_equal \
    "HTTP contract curl calls for nonnumeric port" \
    "" \
    "$curl_arguments"

  is_debug_port_ready 9444
  case "$curl_arguments" in
    *"http://127.0.0.1:9444/json/version"*)
      ;;
    *)
      printf '[%s] ERROR: HTTP contract did not use the loopback version endpoint\n' "$APP_NAME" >&2
      return 1
      ;;
  esac
)

run_launch_regression_test() {
  local test_name="$1"
  shift

  if "$@"; then
    log "Shell regression $test_name: ok"
    return 0
  fi

  fail "Shell regression $test_name failed."
}

run_launch_regression_tests() {
  run_launch_regression_test "confirmation reader" test_force_termination_confirmation_reader
  run_launch_regression_test "TCP port boundaries" test_valid_tcp_port_boundaries
  run_launch_regression_test "main process resolver" test_resolve_codex_main_process_name
  run_launch_regression_test "raw bundle identity scalar boundaries" test_raw_bundle_identity_scalar_boundaries
  run_launch_regression_test "process name byte boundaries" test_process_name_byte_boundaries
  run_launch_regression_test "explicit app bundle validation" test_explicit_codex_app_bundle_validation
  run_launch_regression_test "literal ERE process name" test_literal_ere_process_name
  run_launch_regression_test "unsafe process names" test_unsafe_process_names_are_rejected
  run_launch_regression_test "exact process probe statuses" test_exact_process_probe_statuses
  run_launch_regression_test "exact force termination helpers" test_exact_force_termination_helpers
  run_launch_regression_test "failed pkill final statuses" test_failed_pkill_final_probe_statuses
  run_launch_regression_test "T1 configured ready port" test_ready_configured_port
  run_launch_regression_test "T1 discovered ready port" test_ready_discovered_port
  run_launch_regression_test "ready debugger injection failure" test_ready_debugger_injection_failure
  run_launch_regression_test "T2 uppercase Y-equivalent confirmation" test_confirmed_relaunch "T2"
  run_launch_regression_test "T3 lowercase y-equivalent confirmation" test_confirmed_relaunch "T3"
  run_launch_regression_test "T4 safe confirmation cancel" test_safe_confirmation_cancel
  run_launch_regression_test "T5 non-TTY confirmation" test_non_tty_confirmation_failure
  run_launch_regression_test "T6 normal debug launch" test_normal_debug_launch
  run_launch_regression_test "launched debugger injection failure" test_launched_debugger_injection_failure
  run_launch_regression_test "process probe error blocks launch" test_process_probe_error_blocks_launch
  run_launch_regression_test "invalid ports block launch" test_invalid_port_blocks_launch
  run_launch_regression_test "raw process reader failure blocks launch" test_raw_process_reader_failure_blocks_launch
  run_launch_regression_test "raw process NUL blocks launch" test_raw_process_nul_blocks_launch
  run_launch_regression_test "unsafe raw process values block launch" test_unsafe_raw_process_values_block_launch
  run_launch_regression_test "launch force termination probe error" test_launch_force_termination_probe_error
  run_launch_regression_test "launch final process recheck" test_launch_final_process_recheck
  run_launch_regression_test "launch force termination timeout" test_launch_force_termination_timeout
  run_launch_regression_test "T7 invalid or unready discovered port" test_unready_discovered_port
  run_launch_regression_test "loopback HTTP readiness contract" test_debug_port_http_contract
}

log "Checking shell syntax..."
bash -n \
  "$SCRIPT_DIR/lib/runtime.sh" \
  "$SCRIPT_DIR/launch.sh" \
  "$SCRIPT_DIR/config.sh" \
  "$SCRIPT_DIR/inject-current.sh" \
  "$SCRIPT_DIR/follow-author-config.sh" \
  "$SCRIPT_DIR/verify.sh"

run_launch_regression_tests

if ! CODEX_APP_PATH="$(resolve_codex_app_path)"; then
  fail "ChatGPT/Codex app not found. Set CODEX_APP=/path/to/ChatGPT.app and retry."
fi

BUNDLE_ID="$(read_codex_app_bundle_value "$CODEX_APP_PATH" CFBundleIdentifier || true)"
APP_VERSION="$(read_codex_app_bundle_value "$CODEX_APP_PATH" CFBundleShortVersionString || true)"
if [[ "$BUNDLE_ID" != "$CODEX_APP_EXTENSION_BUNDLE_ID" ]]; then
  fail "Unexpected app bundle identifier '$BUNDLE_ID' at $CODEX_APP_PATH"
fi
log "App: $CODEX_APP_PATH (${APP_VERSION:-unknown}, $BUNDLE_ID)"

if ! NODE_BIN="$(resolve_codex_node_bin "$CODEX_APP_PATH")"; then
  fail "No Node.js runtime with both fetch and WebSocket was found."
fi
log "Node: $NODE_BIN ($("$NODE_BIN" --version))"

BUNDLED_NODE="$CODEX_APP_PATH/Contents/Resources/cua_node/bin/node"
if [[ -x "$BUNDLED_NODE" ]]; then
  resolve_node_candidate "$BUNDLED_NODE" >/dev/null \
    || fail "Bundled ChatGPT/Codex Node.js does not expose fetch and WebSocket: $BUNDLED_NODE"
  log "Bundled Node fallback: $BUNDLED_NODE ($("$BUNDLED_NODE" --version))"
fi

"$NODE_BIN" --check "$SCRIPT_DIR/inject-wide-layout.mjs"

INJECTOR_PATH="$SCRIPT_DIR/inject-wide-layout.mjs" "$NODE_BIN" --input-type=module <<'NODE'
import { readFileSync } from "node:fs";

const injectorPath = process.env.INJECTOR_PATH;
const originalSource = readFileSync(injectorPath, "utf8");
const sourceWithoutMain = originalSource.replace(
  /main\(\)\.catch\(\(error\) => \{[\s\S]*?\n\}\);\s*$/,
  `export {
    buildInstallerSource,
    buildDiagnoseSource,
    buildSurfaceCompatibilitySource,
    buildCss,
    selectTarget,
    DEFAULT_CONFIG,
    CODEX_SURFACE_SELECTORS
  };`,
);
if (sourceWithoutMain === originalSource) {
  throw new Error("Unable to expose injector helpers for verification");
}

const moduleUrl = "data:text/javascript;base64," + Buffer.from(sourceWithoutMain).toString("base64");
const injector = await import(moduleUrl);
const options = {
  ...injector.DEFAULT_CONFIG,
  configPath: "/tmp/codex-app-extension-verify-config.json",
  configCreated: false,
  port: 9229,
  target: "",
  targetTimeoutMs: 30000,
  diagnose: false,
};

new Function("return " + injector.buildSurfaceCompatibilitySource());
for (const optionVariant of [options, { ...options, wideLayoutEnhancement: false }]) {
  new Function("return " + injector.buildDiagnoseSource(optionVariant));
  new Function("return " + injector.buildInstallerSource(optionVariant));

  const css = injector.buildCss(optionVariant);
  if (!css.includes('html[data-codex-app-extension-surface="true"]')) {
    throw new Error("Generated CSS is missing the Codex surface guard");
  }
  if (/\n(?:\.max-w-|\.w-|\.app-shell-left-panel|\[data-codex-app-extension-native-floating-panel)/.test(css)) {
    throw new Error("Generated enhancement CSS contains an unscoped Codex selector");
  }
  if (!css.includes("--codex-app-extension-theme-blockquote-text: inherit !important")) {
    throw new Error("Generated CSS blockquote text should default to inherit");
  }
  const nestedBlockquoteRule = css.match(/main\.main-surface :where\(blockquote\) blockquote \{([^}]*)\}/);
  if (!nestedBlockquoteRule) {
    throw new Error("Generated CSS is missing the nested blockquote flattening rule");
  }
  for (const declaration of [
    "background: transparent !important;",
    "border-left: 0 !important;",
    "border-radius: 0 !important;",
    "margin-inline: 0 !important;",
    "padding: 0 !important;",
  ]) {
    if (!nestedBlockquoteRule[1].includes(declaration)) {
      throw new Error("Nested blockquote reset is missing declaration: " + declaration);
    }
  }
  const topBlockquoteRule = css.match(/main\.main-surface :where\(blockquote\) \{([^}]*)\}/);
  if (!topBlockquoteRule
    || !topBlockquoteRule[1].includes("background: var(--codex-app-extension-theme-blockquote-background) !important;")
    || !topBlockquoteRule[1].includes("border-left: 3px solid var(--codex-app-extension-theme-blockquote-border) !important;")) {
    throw new Error("Top-level blockquote background/border should be preserved");
  }
}

const arbitraryTarget = {
  type: "page",
  title: "Unrelated settings",
  url: "https://example.com/settings",
  webSocketDebuggerUrl: "ws://127.0.0.1/arbitrary",
};
const codexTarget = {
  type: "page",
  title: "Codex",
  url: "app://codex",
  webSocketDebuggerUrl: "ws://127.0.0.1/codex",
};
if (injector.selectTarget([arbitraryTarget], "") !== null) {
  throw new Error("Target selection still falls back to an unrelated page");
}
if (injector.selectTarget([arbitraryTarget, codexTarget], "") !== codexTarget) {
  throw new Error("Target selection did not prefer the Codex workspace candidate");
}

const selectors = injector.CODEX_SURFACE_SELECTORS;
function evaluateSurface(activeSelectors) {
  const active = new Set(activeSelectors);
  globalThis.document = {
    querySelectorAll(selector) {
      return { length: active.has(selector) ? 1 : 0 };
    },
    title: "Codex",
    readyState: "complete",
  };
  globalThis.location = { href: "app://codex" };
  return new Function("return " + injector.buildSurfaceCompatibilitySource())();
}

const supportedSurface = evaluateSurface([
  selectors.layoutRoot,
  selectors.leftPanel,
  selectors.composer,
  selectors.requestNavigation,
]);
if (!supportedSurface.supported || supportedSurface.requestInputProtocol !== "chatgpt-codex-data-attributes") {
  throw new Error("ChatGPT Codex surface signature was not accepted");
}
const unsupportedSurface = evaluateSurface([selectors.composer]);
if (unsupportedSurface.supported) {
  throw new Error("An incomplete/non-Codex surface signature was accepted");
}
delete globalThis.document;
delete globalThis.location;

if (!originalSource.includes("data-codex-composer-request-navigation")
  || !originalSource.includes("data-request-input-dismiss")
  || !originalSource.includes("data-request-input-skip")) {
  throw new Error("New request input protocol anchors are missing from the injector");
}

console.log("[codex-app-extension] Generated sources, target guard, surface guard, and request input adapter: ok");
NODE

APP_ASAR="$CODEX_APP_PATH/Contents/Resources/app.asar"
if [[ "$(basename "$CODEX_APP_PATH")" == "ChatGPT.app" ]]; then
  [[ -f "$APP_ASAR" ]] || fail "ChatGPT app.asar not found: $APP_ASAR"
  for anchor in \
    "data-app-shell-main-content-layout" \
    "app-shell-left-panel" \
    "thread-scroll-container" \
    "ProseMirror" \
    "data-codex-composer-request-navigation" \
    "data-request-input-dismiss" \
    "data-request-input-skip" \
    "data-request-input-other-row"; do
    contains_anchor "$APP_ASAR" "$anchor" || fail "ChatGPT Codex anchor missing from app.asar: $anchor"
  done
  log "ChatGPT Codex surface and request input anchors: ok"
else
  log "Legacy Codex app detected; new ChatGPT request input anchor check skipped."
fi

if [[ "${CODEX_APP_EXTENSION_VERIFY_LIVE:-0}" == "1" ]]; then
  log "Running read-only live diagnosis..."
  "$SCRIPT_DIR/inject-current.sh" --diagnose
else
  log "Live CDP diagnosis skipped (set CODEX_APP_EXTENSION_VERIFY_LIVE=1 to enable)."
fi

if command -v git >/dev/null 2>&1 && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$SCRIPT_DIR" diff --check
fi

log "Verification passed."
