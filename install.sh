#!/bin/bash

set -euo pipefail

PROGRAM_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PROJECT_PATH="$SCRIPT_DIR/CodexAppExtension.xcodeproj"
SCHEME_NAME="CodexAppExtension"
APP_NAME="Codex App Extension.app"
BUNDLE_ID="com.ysxiiun.codexappextension"
DEFAULT_DERIVED_DATA="/tmp/codex-app-extension-release"
DEFAULT_INSTALL_PATH="/Applications/$APP_NAME"

DERIVED_DATA="$DEFAULT_DERIVED_DATA"
INSTALL_PATH="$DEFAULT_INSTALL_PATH"
CLEAN_BUILD=0
NO_LAUNCH=0
AUDIT_ONLY_PATH=""

SUCCESS=0
STAGE_CREATED=0
BACKUP_CREATED=0
SWAP_COMPLETED=0
ORIGINAL_WAS_RUNNING=0
USE_SUDO=0
STAGE_PATH=""
BACKUP_PATH=""
INSTALL_PARENT=""
BUILT_APP=""

usage() {
    cat <<EOF
Usage: ./$PROGRAM_NAME [options]

Build, ad-hoc sign, audit, and install Codex App Extension locally.

Options:
  --clean                 Remove the validated DerivedData directory before building
  --no-launch             Install and audit, but skip launch and runtime survival checks
  --derived-data PATH     DerivedData directory (default: $DEFAULT_DERIVED_DATA)
  --install-path PATH     Destination .app path (default: $DEFAULT_INSTALL_PATH)
  --audit-only PATH       Audit an existing .app bundle without building or installing
  --help                  Show this help text

The Release build and codesign steps never run with sudo. sudo is used only when
the destination's parent directory is not writable and an install operation needs it.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

step() {
    printf '\n[%s/8] %s\n' "$1" "$2"
}

require_value() {
    [ "$#" -ge 2 ] || die "$1 requires a non-empty PATH"
    [ -n "$2" ] || die "$1 requires a non-empty PATH"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --clean)
            CLEAN_BUILD=1
            shift
            ;;
        --no-launch)
            NO_LAUNCH=1
            shift
            ;;
        --derived-data)
            require_value "$1" "${2-}"
            DERIVED_DATA="$2"
            shift 2
            ;;
        --install-path)
            require_value "$1" "${2-}"
            INSTALL_PATH="$2"
            shift 2
            ;;
        --audit-only)
            require_value "$1" "${2-}"
            AUDIT_ONLY_PATH="$2"
            shift 2
            ;;
        --*)
            die "unknown option: $1"
            ;;
        *)
            die "unexpected argument: $1"
            ;;
    esac
done

reject_unsafe_spelling() {
    local label="$1"
    local path="$2"

    [ -n "$path" ] || die "$label must not be empty"
    case "$path" in
        /*) ;;
        *) die "$label must be an absolute path: $path" ;;
    esac
    case "$path" in
        *$'\n'*|*$'\r'*) die "$label must not contain newlines" ;;
        *'//'*) die "$label must not contain //: $path" ;;
        */./*|*/.|*/../*|*/..) die "$label must not contain . or .. path components: $path" ;;
        */) die "$label must not end with /: $path" ;;
    esac
}

validate_install_path() {
    local requested="$1"
    local parent
    local base
    local physical_parent
    local stem

    reject_unsafe_spelling "install path" "$requested"
    [ "$requested" != "/" ] || die "install path must not be /"

    parent="$(dirname "$requested")"
    base="$(basename "$requested")"
    case "$base" in
        *.app) ;;
        *) die "install path must end in .app: $requested" ;;
    esac
    stem="${base%.app}"
    [ -n "$stem" ] && [ "$stem" != "." ] || die "install path must name a concrete app bundle"
    [ "$parent" != "/" ] || die "refusing to install an app directly under /"
    [ -d "$parent" ] || die "install parent does not exist: $parent"

    physical_parent="$(cd "$parent" && pwd -P)" || die "cannot resolve install parent: $parent"
    [ "$physical_parent" != "/" ] || die "refusing to use / as the install parent"
    case "$physical_parent" in
        *.app|*.app/*)
            die "refusing to install inside another app bundle: $physical_parent"
            ;;
        /System|/System/*|/Library|/Library/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/etc|/etc/*|/private/etc|/private/etc/*|/private/var|/private/var/*)
            die "refusing protected system install parent: $physical_parent"
            ;;
        /Users|/Volumes)
            die "refusing broad install parent: $physical_parent"
            ;;
    esac
    INSTALL_PARENT="$physical_parent"
    INSTALL_PATH="$physical_parent/$base"

    if [ -L "$INSTALL_PATH" ]; then
        die "install path must not be a symbolic link: $INSTALL_PATH"
    fi
    if [ -e "$INSTALL_PATH" ] && [ ! -d "$INSTALL_PATH" ]; then
        die "install path exists but is not an app directory: $INSTALL_PATH"
    fi
}

validate_derived_data() {
    local requested="$1"
    local parent
    local base
    local physical_parent
    local home_path="${HOME-}"

    reject_unsafe_spelling "DerivedData path" "$requested"
    case "$requested" in
        /|/tmp|/private/tmp|/Applications|/Users|/Volumes|/Library|/System)
            die "refusing dangerous DerivedData path: $requested"
            ;;
    esac
    if [ -n "$home_path" ] && [ "$requested" = "$home_path" ]; then
        die "DerivedData path must not be the home directory"
    fi
    [ "$requested" != "$SCRIPT_DIR" ] || die "DerivedData path must not be the repository root"

    parent="$(dirname "$requested")"
    base="$(basename "$requested")"
    [ -n "$base" ] && [ "$base" != "." ] && [ "$base" != ".." ] || die "invalid DerivedData path"
    [ -d "$parent" ] || die "DerivedData parent does not exist: $parent"
    physical_parent="$(cd "$parent" && pwd -P)" || die "cannot resolve DerivedData parent: $parent"
    DERIVED_DATA="$physical_parent/$base"

    case "$DERIVED_DATA" in
        "$INSTALL_PATH"|"$INSTALL_PATH/"*|"$INSTALL_PARENT")
            die "DerivedData path must not overlap the install destination"
            ;;
    esac
    case "$INSTALL_PATH" in
        "$DERIVED_DATA/"*) die "install destination must not be inside DerivedData" ;;
    esac
    if [ -L "$DERIVED_DATA" ]; then
        die "DerivedData path must not be a symbolic link: $DERIVED_DATA"
    fi
    if [ -e "$DERIVED_DATA" ] && [ ! -d "$DERIVED_DATA" ]; then
        die "DerivedData path exists but is not a directory: $DERIVED_DATA"
    fi
}

validate_derived_data_for_clean() {
    local marker="$DERIVED_DATA/info.plist"
    local workspace_path

    [ "$CLEAN_BUILD" -eq 1 ] || return 0
    [ -e "$DERIVED_DATA" ] || return 0
    [ -f "$marker" ] || die "refusing to clean directory without Xcode DerivedData marker: $DERIVED_DATA"
    [ ! -L "$marker" ] || die "refusing a symbolic-link DerivedData marker: $marker"
    if ! workspace_path="$(/usr/bin/plutil -extract WorkspacePath raw -o - "$marker" 2>/dev/null)"; then
        die "refusing to clean directory with unreadable DerivedData marker: $marker"
    fi
    [ "$workspace_path" = "$PROJECT_PATH" ] || die "refusing to clean DerivedData owned by another project: $workspace_path"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

RUNNING_QUERY_DETAIL=""

query_bundle_running() {
    local result

    RUNNING_QUERY_DETAIL=""
    if ! result="$(/usr/bin/osascript -l JavaScript \
        -e 'ObjC.import("AppKit"); function run(argv) { return String(Number($.NSRunningApplication.runningApplicationsWithBundleIdentifier($(argv[0])).count)); }' \
        "$BUNDLE_ID" 2>&1)"; then
        RUNNING_QUERY_DETAIL="$result"
        return 2
    fi
    case "$result" in
        ''|*[!0-9]*)
            RUNNING_QUERY_DETAIL="unexpected running-app query result: $result"
            return 2
            ;;
        0) return 1 ;;
        *) return 0 ;;
    esac
}

query_exact_installed_app_running() {
    local expected_executable="$1"
    local result
    local count
    local declared_path
    local physical_path
    local tab

    RUNNING_QUERY_DETAIL=""
    if ! result="$(/usr/bin/osascript -l JavaScript \
        -e 'ObjC.import("AppKit"); ObjC.import("Foundation"); function run(argv) { const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier($(argv[0])); const count = Number(apps.count); const fields = [String(count)]; for (let i = 0; i < count; i++) { const url = apps.objectAtIndex(i).executableURL; if (!url) { fields.push("", ""); } else { fields.push(ObjC.unwrap(url.path), ObjC.unwrap(url.path.stringByResolvingSymlinksInPath)); } } return fields.join("\t"); }' \
        "$BUNDLE_ID" 2>&1)"; then
        RUNNING_QUERY_DETAIL="$result"
        return 2
    fi

    tab="$(printf '\t')"
    IFS="$tab" read -r count declared_path physical_path <<EOF
$result
EOF
    case "$count" in
        ''|*[!0-9]*)
            RUNNING_QUERY_DETAIL="unexpected exact-path query result: $result"
            return 2
            ;;
        0) return 1 ;;
        1) ;;
        *)
            RUNNING_QUERY_DETAIL="expected one running instance, found $count"
            return 3
            ;;
    esac
    if [ "$declared_path" != "$expected_executable" ] || [ "$physical_path" != "$expected_executable" ]; then
        RUNNING_QUERY_DETAIL="running executable mismatch: declared=$declared_path physical=$physical_path expected=$expected_executable"
        return 3
    fi
    return 0
}

print_latest_diagnostic_report() {
    local report_dir="${HOME-}/Library/Logs/DiagnosticReports"
    local latest=""

    [ -n "${HOME-}" ] && [ -d "$report_dir" ] || return 0
    latest="$(/bin/ls -1t "$report_dir"/"Codex App Extension-"*.ips 2>/dev/null | /usr/bin/head -n 1 || true)"
    if [ -n "$latest" ]; then
        printf 'Latest diagnostic report: %s\n' "$latest" >&2
    fi
}

die_with_diagnostic_report() {
    print_latest_diagnostic_report
    die "$*"
}

wait_until_stopped() {
    local attempts=0
    local query_status
    while [ "$attempts" -lt 20 ]; do
        if query_bundle_running; then
            query_status=0
        else
            query_status=$?
        fi
        case "$query_status" in
            0) ;;
            1) return 0 ;;
            *) return 2 ;;
        esac
        attempts=$((attempts + 1))
        /bin/sleep 0.5
    done
    return 1
}

quit_bundle_instances_if_running() {
    local query_status
    local wait_status

    if query_bundle_running; then
        query_status=0
    else
        query_status=$?
    fi
    case "$query_status" in
        1) return 0 ;;
        2) die "cannot query running app instances: $RUNNING_QUERY_DETAIL" ;;
    esac

    ORIGINAL_WAS_RUNNING=1
    printf 'Requesting normal application quit through bundle id %s.\n' "$BUNDLE_ID"
    if ! /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit"; then
        die "normal application quit request failed"
    fi
    if wait_until_stopped; then
        return 0
    else
        wait_status=$?
    fi
    case "$wait_status" in
        1) die "application did not quit normally within 10 seconds; operation aborted" ;;
        *) die "running-app query failed while waiting for quit: $RUNNING_QUERY_DETAIL" ;;
    esac
}

run_parent_operation() {
    if [ "$USE_SUDO" -eq 1 ]; then
        /usr/bin/sudo -- "$@"
    else
        "$@"
    fi
}

validate_temporary_path() {
    local path="$1"
    local suffix="$2"
    [ -n "$path" ] || return 1
    [ "$(dirname "$path")" = "$INSTALL_PARENT" ] || return 1
    [ "$path" = "$INSTALL_PATH.$suffix.$$" ] || return 1
}

remove_stage_if_present() {
    if [ "$STAGE_CREATED" -eq 1 ] && [ -e "$STAGE_PATH" ]; then
        if validate_temporary_path "$STAGE_PATH" "installing"; then
            run_parent_operation /bin/rm -rf -- "$STAGE_PATH"
        else
            printf 'warning: refused unsafe stage cleanup: %s\n' "$STAGE_PATH" >&2
        fi
    fi
    STAGE_CREATED=0
}

rollback_install() {
    set +e
    printf '\nInstallation failed; attempting rollback.\n' >&2

    if [ "$SWAP_COMPLETED" -eq 1 ] && [ -e "$INSTALL_PATH" ]; then
        if validate_temporary_path "$STAGE_PATH" "installing"; then
            if [ -e "$STAGE_PATH" ]; then
                run_parent_operation /bin/rm -rf -- "$STAGE_PATH"
            fi
            run_parent_operation /bin/mv -- "$INSTALL_PATH" "$STAGE_PATH"
            STAGE_CREATED=1
        else
            printf 'warning: cannot quarantine failed install; unsafe stage path\n' >&2
        fi
    fi

    if [ "$BACKUP_CREATED" -eq 1 ] && [ -e "$BACKUP_PATH" ]; then
        if validate_temporary_path "$BACKUP_PATH" "backup" && [ ! -e "$INSTALL_PATH" ]; then
            run_parent_operation /bin/mv -- "$BACKUP_PATH" "$INSTALL_PATH"
            BACKUP_CREATED=0
            printf 'Restored previous app: %s\n' "$INSTALL_PATH" >&2
            if [ "$ORIGINAL_WAS_RUNNING" -eq 1 ]; then
                /usr/bin/open "$INSTALL_PATH" >/dev/null 2>&1
            fi
        else
            printf 'warning: automatic backup restore was not safe; backup remains at %s\n' "$BACKUP_PATH" >&2
        fi
    fi

    remove_stage_if_present
}

on_exit() {
    local status="$1"
    if [ "$SUCCESS" -eq 0 ] && [ "$status" -ne 0 ]; then
        rollback_install
    fi
}

audit_error() {
    printf 'audit error (%s): %s\n' "$1" "$2" >&2
    return 1
}

audit_bundle() {
    local app="$1"
    local label="$2"
    local plist="$app/Contents/Info.plist"
    local resources_dir="$app/Contents/Resources"
    local executable_name
    local executable_path
    local identifier
    local ui_element
    local minimum_system_version
    local framework="$app/Contents/Frameworks/ExtensionCore.framework"
    local framework_binary="$framework/Versions/A/ExtensionCore"
    local install_names
    local dependencies
    local extension_dependencies
    local rpaths
    local invalid_rpaths
    local required_rpath_count
    local swift_rpath_count
    local total_rpath_count
    local resource
    local retired_focus_resource
    local js_manifest
    local expected_js_manifest
    local forbidden_focus_pattern

    [ -d "$app" ] || { audit_error "$label" "app bundle is missing: $app"; return 1; }
    [ ! -L "$app" ] || { audit_error "$label" "app bundle must not be a symbolic link"; return 1; }
    [ -f "$plist" ] || { audit_error "$label" "Contents/Info.plist is missing"; return 1; }

    if ! identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null)"; then
        audit_error "$label" "cannot read CFBundleIdentifier"
        return 1
    fi
    [ "$identifier" = "$BUNDLE_ID" ] || { audit_error "$label" "unexpected bundle id: $identifier"; return 1; }

    if ! executable_name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$plist" 2>/dev/null)"; then
        audit_error "$label" "cannot read CFBundleExecutable"
        return 1
    fi
    [ -n "$executable_name" ] || { audit_error "$label" "CFBundleExecutable is empty"; return 1; }
    executable_path="$app/Contents/MacOS/$executable_name"
    [ -f "$executable_path" ] && [ -x "$executable_path" ] || { audit_error "$label" "main executable is missing or not executable"; return 1; }
    [ ! -L "$executable_path" ] || { audit_error "$label" "main executable must not be a symbolic link"; return 1; }

    if ! ui_element="$(/usr/bin/plutil -extract LSUIElement raw -o - "$plist" 2>/dev/null)"; then
        audit_error "$label" "cannot read LSUIElement"
        return 1
    fi
    [ "$ui_element" = "true" ] || { audit_error "$label" "LSUIElement must be true"; return 1; }

    if ! minimum_system_version="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$plist" 2>/dev/null)"; then
        audit_error "$label" "cannot read LSMinimumSystemVersion"
        return 1
    fi
    [ "$minimum_system_version" = "13.0" ] || { audit_error "$label" "LSMinimumSystemVersion must be 13.0, got: $minimum_system_version"; return 1; }

    [ -d "$resources_dir" ] || { audit_error "$label" "Contents/Resources is missing"; return 1; }
    [ ! -L "$resources_dir" ] || { audit_error "$label" "Contents/Resources must not be a symbolic link"; return 1; }
    [ -d "$framework" ] || { audit_error "$label" "embedded ExtensionCore.framework is missing"; return 1; }
    [ ! -L "$framework" ] || { audit_error "$label" "ExtensionCore.framework must not be a symbolic link"; return 1; }
    [ -f "$framework_binary" ] || { audit_error "$label" "ExtensionCore framework binary is missing"; return 1; }
    [ ! -L "$framework_binary" ] || { audit_error "$label" "ExtensionCore framework binary must not be a symbolic link"; return 1; }

    for resource in \
        bootstrap.js \
        header-offset.js \
        ime-enter-guard.js \
        wide-layout.js \
        markdown-semantic-theme.js; do
        [ -f "$resources_dir/$resource" ] || { audit_error "$label" "resource is missing: Contents/Resources/$resource"; return 1; }
        [ ! -L "$resources_dir/$resource" ] || { audit_error "$label" "JavaScript resource must not be a symbolic link: $resource"; return 1; }
    done
    retired_focus_resource='focus''-ring.js'
    [ ! -e "$resources_dir/$retired_focus_resource" ] || {
        audit_error "$label" "retired $retired_focus_resource must not remain in Contents/Resources"
        return 1
    }

    expected_js_manifest='./bootstrap.js
./header-offset.js
./ime-enter-guard.js
./markdown-semantic-theme.js
./wide-layout.js'
    if ! js_manifest="$(cd "$resources_dir" && /usr/bin/find . -name '*.js' -print | LC_ALL=C /usr/bin/sort)"; then
        audit_error "$label" "cannot enumerate JavaScript resources"
        return 1
    fi
    [ "$js_manifest" = "$expected_js_manifest" ] || {
        audit_error "$label" "JavaScript resource manifest must contain exactly the five expected files"
        return 1
    }
    forbidden_focus_pattern='data-cae-focus-ring|--cae-focus-ring-color|cae-focus-ring-style|:focus-visible'
    for resource in bootstrap.js header-offset.js ime-enter-guard.js markdown-semantic-theme.js wide-layout.js; do
        if LC_ALL=C /usr/bin/grep -nE "$forbidden_focus_pattern" "$resources_dir/$resource" >/dev/null; then
            audit_error "$label" "retired keyboard-focus marker remains in Contents/Resources/$resource"
            return 1
        else
            local grep_status=$?
            if [ "$grep_status" -ne 1 ]; then
                audit_error "$label" "cannot inspect retired keyboard-focus markers in Contents/Resources/$resource"
                return 1
            fi
        fi
    done

    if ! dependencies="$(/usr/bin/otool -L "$executable_path" | /usr/bin/awk 'NR > 1 { print $1 }')"; then
        audit_error "$label" "cannot inspect main executable dependencies"
        return 1
    fi
    extension_dependencies="$(printf '%s\n' "$dependencies" | /usr/bin/grep -F 'ExtensionCore' || true)"
    [ "$extension_dependencies" = '@rpath/ExtensionCore.framework/Versions/A/ExtensionCore' ] || {
        audit_error "$label" "main executable must contain exactly one required ExtensionCore @rpath dependency and no alternatives"
        return 1
    }

    if ! install_names="$(/usr/bin/otool -D "$framework_binary" | /usr/bin/awk 'NR > 1 { print }')"; then
        audit_error "$label" "cannot inspect ExtensionCore install name"
        return 1
    fi
    [ "$install_names" = '@rpath/ExtensionCore.framework/Versions/A/ExtensionCore' ] || {
        audit_error "$label" "unexpected ExtensionCore install name: $install_names"
        return 1
    }

    if ! rpaths="$(/usr/bin/otool -l "$executable_path" | /usr/bin/awk '$1 == "cmd" && $2 == "LC_RPATH" { wanted = 1; next } wanted && $1 == "path" { print $2; wanted = 0 }')"; then
        audit_error "$label" "cannot inspect executable runpaths"
        return 1
    fi
    invalid_rpaths="$(printf '%s\n' "$rpaths" | /usr/bin/grep -Fvx -e '/usr/lib/swift' -e '@executable_path/../Frameworks' || true)"
    [ -z "$invalid_rpaths" ] || {
        audit_error "$label" "executable contains a runpath outside the strict allowlist: $invalid_rpaths"
        return 1
    }
    required_rpath_count="$(printf '%s\n' "$rpaths" | /usr/bin/grep -Fxc '@executable_path/../Frameworks' || true)"
    swift_rpath_count="$(printf '%s\n' "$rpaths" | /usr/bin/grep -Fxc '/usr/lib/swift' || true)"
    total_rpath_count="$(printf '%s\n' "$rpaths" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')"
    [ "$required_rpath_count" -eq 1 ] && [ "$swift_rpath_count" -le 1 ] && [ "$total_rpath_count" -eq $((required_rpath_count + swift_rpath_count)) ] || {
        audit_error "$label" "executable runpaths must be exactly the required app runpath plus optional /usr/lib/swift"
        return 1
    }

    if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"; then
        audit_error "$label" "code signature verification failed"
        return 1
    fi

    return 0
}

if [ -n "$AUDIT_ONLY_PATH" ]; then
    reject_unsafe_spelling "audit-only path" "$AUDIT_ONLY_PATH"
    case "$AUDIT_ONLY_PATH" in
        *.app) ;;
        *) die "audit-only path must end in .app: $AUDIT_ONLY_PATH" ;;
    esac
    for command_name in codesign otool plutil awk grep find sort; do
        require_command "$command_name"
    done
    audit_bundle "$AUDIT_ONLY_PATH" "audit-only bundle" || die "audit-only bundle audit failed"
    printf 'Audit-only bundle passed: %s\n' "$AUDIT_ONLY_PATH"
    SUCCESS=1
    exit 0
fi

step 1 "Preflight"
[ "$(/usr/bin/id -u)" -ne 0 ] || die "do not run this installer as root or through sudo"
validate_install_path "$INSTALL_PATH"
validate_derived_data "$DERIVED_DATA"
validate_derived_data_for_clean

for command_name in xcodebuild codesign otool plutil ditto diff osascript open awk grep find sort; do
    require_command "$command_name"
done
[ -d "$PROJECT_PATH" ] || die "Xcode project not found: $PROJECT_PATH"

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
STAGE_PATH="$INSTALL_PATH.installing.$$"
BACKUP_PATH="$INSTALL_PATH.backup.$$"
validate_temporary_path "$STAGE_PATH" "installing" || die "internal stage path validation failed"
validate_temporary_path "$BACKUP_PATH" "backup" || die "internal backup path validation failed"
[ ! -e "$STAGE_PATH" ] || die "stage path already exists: $STAGE_PATH"
[ ! -e "$BACKUP_PATH" ] || die "backup path already exists: $BACKUP_PATH"

if [ -w "$INSTALL_PARENT" ]; then
    USE_SUDO=0
else
    require_command sudo
    USE_SUDO=1
fi
printf 'DerivedData: %s\nInstall path: %s\n' "$DERIVED_DATA" "$INSTALL_PATH"

trap 'on_exit $?' EXIT

step 2 "Incremental Release build"
if [ "$CLEAN_BUILD" -eq 1 ] && [ -e "$DERIVED_DATA" ]; then
    printf 'Removing validated DerivedData for clean build: %s\n' "$DERIVED_DATA"
    /bin/rm -rf -- "$DERIVED_DATA"
fi
/usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build
[ -d "$BUILT_APP" ] || die "Release build did not produce: $BUILT_APP"

step 3 "Local ad-hoc sign"
FRAMEWORK_TO_SIGN="$BUILT_APP/Contents/Frameworks/ExtensionCore.framework"
[ -d "$FRAMEWORK_TO_SIGN" ] || die "embedded framework is missing before signing"
/usr/bin/codesign --force --sign - --timestamp=none "$FRAMEWORK_TO_SIGN"
/usr/bin/codesign --force --sign - --timestamp=none "$BUILT_APP"

step 4 "Built bundle audit"
audit_bundle "$BUILT_APP" "built bundle" || die "built bundle audit failed"
printf 'Built bundle audit passed.\n'

step 5 "Sibling stage/swap install"
if [ -d "$INSTALL_PATH" ] && audit_bundle "$INSTALL_PATH" "existing install" >/dev/null 2>&1 && /usr/bin/diff -qr "$BUILT_APP" "$INSTALL_PATH" >/dev/null 2>&1; then
    if [ "$NO_LAUNCH" -eq 0 ]; then
        quit_bundle_instances_if_running
    fi
    printf 'Installed bundle is identical; swap skipped.\n'
else
    STAGE_CREATED=1
    run_parent_operation /usr/bin/ditto "$BUILT_APP" "$STAGE_PATH"
    audit_bundle "$STAGE_PATH" "staged bundle" || die "staged bundle audit failed"
    quit_bundle_instances_if_running

    if [ -e "$INSTALL_PATH" ]; then
        BACKUP_CREATED=1
        run_parent_operation /bin/mv -- "$INSTALL_PATH" "$BACKUP_PATH"
    fi
    SWAP_COMPLETED=1
    run_parent_operation /bin/mv -- "$STAGE_PATH" "$INSTALL_PATH"
    STAGE_CREATED=0
    printf 'Installed new bundle with same-parent atomic rename.\n'
fi

step 6 "Installed bundle audit"
audit_bundle "$INSTALL_PATH" "installed bundle" || die "installed bundle audit failed"
INSTALLED_EXECUTABLE_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INSTALL_PATH/Contents/Info.plist")"
INSTALLED_EXECUTABLE_PATH="$INSTALL_PATH/Contents/MacOS/$INSTALLED_EXECUTABLE_NAME"
printf 'Installed bundle audit passed.\n'
if [ "$NO_LAUNCH" -eq 1 ] && [ "$BACKUP_CREATED" -eq 1 ]; then
    validate_temporary_path "$BACKUP_PATH" "backup" || die "internal backup cleanup validation failed"
    run_parent_operation /bin/rm -rf -- "$BACKUP_PATH"
    BACKUP_CREATED=0
    SWAP_COMPLETED=0
    printf 'Previous app backup removed after installed audit; cold-launch remains unverified.\n'
fi

step 7 "Launch"
if [ "$NO_LAUNCH" -eq 1 ]; then
    printf 'Skipped by --no-launch.\n'
else
    if ! /usr/bin/open "$INSTALL_PATH"; then
        die_with_diagnostic_report "failed to request application launch"
    fi
fi

step 8 "Running and survival check"
if [ "$NO_LAUNCH" -eq 1 ]; then
    printf 'Skipped by --no-launch; cold-launch survival is not proven.\n'
else
    launch_attempts=0
    while [ "$launch_attempts" -lt 20 ]; do
        if query_exact_installed_app_running "$INSTALLED_EXECUTABLE_PATH"; then
            launch_query_status=0
        else
            launch_query_status=$?
        fi
        case "$launch_query_status" in
            0) break ;;
            1) ;;
            2) die_with_diagnostic_report "running-app query failed: $RUNNING_QUERY_DETAIL" ;;
            *) die_with_diagnostic_report "$RUNNING_QUERY_DETAIL" ;;
        esac
        launch_attempts=$((launch_attempts + 1))
        /bin/sleep 0.5
    done
    if query_exact_installed_app_running "$INSTALLED_EXECUTABLE_PATH"; then
        launch_query_status=0
    else
        launch_query_status=$?
    fi
    case "$launch_query_status" in
        0) ;;
        1) die_with_diagnostic_report "application was not running within 10 seconds" ;;
        2) die_with_diagnostic_report "running-app query failed: $RUNNING_QUERY_DETAIL" ;;
        *) die_with_diagnostic_report "$RUNNING_QUERY_DETAIL" ;;
    esac
    printf 'Application is running; checking 3-second survival window.\n'
    /bin/sleep 3
    if query_exact_installed_app_running "$INSTALLED_EXECUTABLE_PATH"; then
        launch_query_status=0
    else
        launch_query_status=$?
    fi
    case "$launch_query_status" in
        0) ;;
        1) die_with_diagnostic_report "application exited during the 3-second survival window" ;;
        2) die_with_diagnostic_report "running-app query failed: $RUNNING_QUERY_DETAIL" ;;
        *) die_with_diagnostic_report "$RUNNING_QUERY_DETAIL" ;;
    esac
    printf 'Application remained running for the required survival window.\n'

    if [ "$BACKUP_CREATED" -eq 1 ]; then
        validate_temporary_path "$BACKUP_PATH" "backup" || die "internal backup cleanup validation failed"
        run_parent_operation /bin/rm -rf -- "$BACKUP_PATH"
        BACKUP_CREATED=0
        SWAP_COMPLETED=0
    fi
fi

remove_stage_if_present
SUCCESS=1
printf '\nInstallation completed successfully: %s\n' "$INSTALL_PATH"
