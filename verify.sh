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

log "Checking shell syntax..."
bash -n \
  "$SCRIPT_DIR/lib/runtime.sh" \
  "$SCRIPT_DIR/launch.sh" \
  "$SCRIPT_DIR/config.sh" \
  "$SCRIPT_DIR/inject-current.sh" \
  "$SCRIPT_DIR/follow-author-config.sh" \
  "$SCRIPT_DIR/verify.sh"

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
