#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const APP_NAME = "codex-app-extension";
const STYLE_ID = "codex-app-extension-style";
const LEGACY_STYLE_ID = "codex-wide-layout-style";

const DEFAULT_PORT = 9229;
const DEFAULT_SIDE_PADDING = "32px";
const DEFAULT_CONFIG = Object.freeze({
  contentMaxWidth: "1800px",
  fullscreenHeaderOffset: "46px",
  imeEnterGuard: true,
});

function parseCliArgs(argv) {
  const cli = {};

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const value = argv[i + 1];

    if (arg === "--port" && value) {
      cli.port = value;
      i += 1;
    } else if (arg === "--content-max-width" && value) {
      cli.contentMaxWidth = value;
      i += 1;
    } else if (["--thread-max", "--composer-max", "--markdown-max"].includes(arg) && value) {
      cli.contentMaxWidth = value;
      i += 1;
    } else if (arg === "--fullscreen-header-offset" && value) {
      cli.fullscreenHeaderOffset = value;
      i += 1;
    } else if (arg === "--side-padding" && value) {
      cli.sidePadding = value;
      i += 1;
    } else if (arg === "--target" && value) {
      cli.target = value;
      i += 1;
    } else if (arg === "--diagnose") {
      cli.diagnose = true;
    } else if (arg === "--disable-ime-enter-guard") {
      cli.imeEnterGuard = false;
    } else if (arg === "--enable-ime-enter-guard") {
      cli.imeEnterGuard = true;
    } else if (arg === "--help" || arg === "-h") {
      cli.help = true;
    } else {
      throw new Error(`Unknown or incomplete argument: ${arg}`);
    }
  }

  return cli;
}

function printHelp() {
  console.log(`
Usage:
  node inject-wide-layout.mjs [options]

Options:
  --port <number>                    Remote debugging port. Default: ${DEFAULT_PORT}
  --content-max-width <css-size>      Max width for thread, composer, and wide blocks.
                                     Default: ${DEFAULT_CONFIG.contentMaxWidth}
  --fullscreen-header-offset <size>   Top offset used in macOS fullscreen.
                                     Default: ${DEFAULT_CONFIG.fullscreenHeaderOffset}
  --side-padding <size>               Window side padding used in calc(). Default: ${DEFAULT_SIDE_PADDING}
  --target <text>                     Prefer a debugger target whose title/url includes this text.
  --disable-ime-enter-guard           Disable IME Enter guard for this run.
  --enable-ime-enter-guard            Enable IME Enter guard for this run.
  --diagnose                          Print current Codex layout facts without changing CSS.

Config:
  ~/.codex-app-extension/config.json

Legacy aliases:
  --thread-max, --composer-max, --markdown-max all map to --content-max-width.
`);
}

async function main() {
  if (typeof WebSocket !== "function") {
    throw new Error("This Node.js runtime does not expose WebSocket. Try NODE_BIN=/Applications/Codex.app/Contents/Resources/node.");
  }

  const cli = parseCliArgs(process.argv.slice(2));
  if (cli.help) {
    printHelp();
    process.exit(0);
  }

  const configInfo = ensureConfig();
  const options = buildOptions(cli, configInfo);
  const targets = await getJson(`http://127.0.0.1:${options.port}/json/list`);
  const target = selectTarget(targets, options.target);

  if (!target) {
    const known = targets.map((item) => `${item.type || "unknown"} ${item.title || ""} ${item.url || ""}`).join("\n");
    throw new Error(`No attachable Codex page target found on port ${options.port}.\nKnown targets:\n${known}`);
  }

  const client = await connectCdp(target.webSocketDebuggerUrl);
  try {
    await client.send("Runtime.enable");
    await client.send("Page.enable").catch(() => null);

    const source = options.diagnose ? buildDiagnoseSource(options) : buildInstallerSource(options);
    if (!options.diagnose) {
      await client.send("Page.addScriptToEvaluateOnNewDocument", { source }).catch(() => null);
    }
    const result = await client.send("Runtime.evaluate", {
      expression: wrapForJsonResult(source),
      awaitPromise: true,
      returnByValue: true,
    });
    if (process.env.CODEX_APP_EXTENSION_DEBUG || process.env.CODEX_WIDE_DEBUG) {
      console.error(JSON.stringify(result, null, 2));
    }
    assertEvaluateSucceeded(result);

    const value = parseJsonResult(result?.result?.result?.value);
    console.log(JSON.stringify({
      ok: true,
      target: {
        title: target.title,
        type: target.type,
        url: target.url,
      },
      applied: value || null,
    }, null, 2));
  } finally {
    client.close();
  }
}

function ensureConfig() {
  const configDir = join(homedir(), ".codex-app-extension");
  const configPath = join(configDir, "config.json");
  let created = false;

  if (!existsSync(configPath)) {
    mkdirSync(configDir, { recursive: true });
    writeFileSync(configPath, `${JSON.stringify(DEFAULT_CONFIG, null, 2)}\n`, "utf8");
    created = true;
  }

  const raw = readFileSync(configPath, "utf8");
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    throw new Error(`Invalid config JSON at ${configPath}: ${error.message}`);
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`Invalid config at ${configPath}: expected a JSON object`);
  }

  return {
    path: configPath,
    created,
    values: {
      contentMaxWidth: stringOrUndefined(parsed.contentMaxWidth),
      fullscreenHeaderOffset: stringOrUndefined(parsed.fullscreenHeaderOffset),
      imeEnterGuard: booleanOrUndefined(parsed.imeEnterGuard, "imeEnterGuard"),
    },
  };
}

function buildOptions(cli, configInfo) {
  const env = process.env;
  const port = Number(firstValue(
    cli.port,
    env.CODEX_APP_EXTENSION_PORT,
    env.CODEX_WIDE_PORT,
    DEFAULT_PORT,
  ));

  if (!Number.isFinite(port) || port <= 0) {
    throw new Error(`Invalid port: ${port}`);
  }

  const options = {
    port,
    contentMaxWidth: firstValue(
      cli.contentMaxWidth,
      env.CODEX_APP_EXTENSION_CONTENT_MAX_WIDTH,
      env.CODEX_WIDE_THREAD_MAX,
      env.CODEX_WIDE_COMPOSER_MAX,
      env.CODEX_WIDE_MARKDOWN_MAX,
      configInfo.values.contentMaxWidth,
      DEFAULT_CONFIG.contentMaxWidth,
    ),
    fullscreenHeaderOffset: firstValue(
      cli.fullscreenHeaderOffset,
      env.CODEX_APP_EXTENSION_FULLSCREEN_HEADER_OFFSET,
      configInfo.values.fullscreenHeaderOffset,
      DEFAULT_CONFIG.fullscreenHeaderOffset,
    ),
    sidePadding: firstValue(
      cli.sidePadding,
      env.CODEX_APP_EXTENSION_SIDE_PADDING,
      env.CODEX_WIDE_SIDE_PADDING,
      DEFAULT_SIDE_PADDING,
    ),
    target: firstValue(
      cli.target,
      env.CODEX_APP_EXTENSION_TARGET,
      env.CODEX_WIDE_TARGET,
      "",
    ),
    imeEnterGuard: parseBooleanOption("imeEnterGuard", firstValue(
      cli.imeEnterGuard,
      env.CODEX_APP_EXTENSION_IME_ENTER_GUARD,
      configInfo.values.imeEnterGuard,
      DEFAULT_CONFIG.imeEnterGuard,
    )),
    diagnose: Boolean(cli.diagnose),
    configPath: configInfo.path,
    configCreated: configInfo.created,
  };

  assertCssSize("contentMaxWidth", options.contentMaxWidth);
  assertCssSize("fullscreenHeaderOffset", options.fullscreenHeaderOffset);
  assertCssSize("sidePadding", options.sidePadding);

  return options;
}

function firstValue(...values) {
  return values.find((value) => value !== undefined && value !== null && String(value).trim() !== "");
}

function stringOrUndefined(value) {
  return typeof value === "string" && value.trim() ? value : undefined;
}

function booleanOrUndefined(value, name) {
  if (value === undefined || value === null) return undefined;
  if (typeof value === "boolean") return value;
  if (typeof value === "string" && !value.trim()) return undefined;
  return parseBooleanOption(name, value);
}

function parseBooleanOption(name, value) {
  if (typeof value === "boolean") return value;
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "off"].includes(normalized)) return false;
  throw new Error(`Invalid ${name}: expected true/false`);
}

function assertCssSize(name, value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Invalid ${name}: expected a non-empty CSS size`);
  }
}

async function getJson(url) {
  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    throw new Error(`Cannot connect to ${url}. Start Codex with --remote-debugging-port first. ${error.message}`);
  }

  if (!response.ok) {
    throw new Error(`HTTP ${response.status} while reading ${url}`);
  }

  return response.json();
}

function selectTarget(targets, preferredText) {
  const attachable = targets.filter((target) => {
    if (!target.webSocketDebuggerUrl) return false;
    if (target.type && !["page", "webview"].includes(target.type)) return false;
    if (target.url?.startsWith("devtools://")) return false;
    return true;
  });

  if (preferredText) {
    const lower = preferredText.toLowerCase();
    const preferred = attachable.find((target) => {
      return `${target.title || ""} ${target.url || ""}`.toLowerCase().includes(lower);
    });
    if (preferred) return preferred;
  }

  return attachable.find((target) => /codex|app:|file:|localhost/i.test(`${target.title || ""} ${target.url || ""}`))
    || attachable[0]
    || null;
}

async function connectCdp(webSocketUrl) {
  const socket = new WebSocket(webSocketUrl);
  const pending = new Map();
  let nextId = 1;

  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(decodeMessage(event.data));
    if (!message.id) return;
    const callback = pending.get(message.id);
    if (!callback) return;
    pending.delete(message.id);
    clearTimeout(callback.timer);
    if (message.error) {
      callback.reject(new Error(`${message.error.message || "CDP error"} ${message.error.data || ""}`.trim()));
    } else {
      callback.resolve(message);
    }
  });

  socket.addEventListener("close", () => {
    for (const callback of pending.values()) {
      clearTimeout(callback.timer);
      callback.reject(new Error("CDP websocket closed before a response was received"));
    }
    pending.clear();
  });

  return {
    send(method, params = {}) {
      const id = nextId;
      nextId += 1;
      const payload = JSON.stringify({ id, method, params });
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`Timed out waiting for ${method}`));
        }, 8000);
        pending.set(id, { resolve, reject, timer });
        socket.send(payload);
      });
    },
    close() {
      socket.close();
    },
  };
}

function wrapForJsonResult(source) {
  return `JSON.stringify((() => {
    const __codexAppExtensionValue = ${source}
    return __codexAppExtensionValue;
  })())`;
}

function parseJsonResult(value) {
  if (typeof value !== "string") return value ?? null;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function assertEvaluateSucceeded(result) {
  if (!result?.result?.exceptionDetails) return;
  const details = result.result.exceptionDetails;
  const text = details.exception?.description || details.text || "unknown runtime exception";
  throw new Error(`Runtime.evaluate failed: ${text}`);
}

function decodeMessage(data) {
  if (typeof data === "string") return data;
  if (data instanceof ArrayBuffer) return Buffer.from(data).toString("utf8");
  if (ArrayBuffer.isView(data)) {
    return Buffer.from(data.buffer, data.byteOffset, data.byteLength).toString("utf8");
  }
  return String(data);
}

function buildDiagnoseSource(options) {
  const meta = buildMeta(options);
  return `(() => {
    const meta = ${JSON.stringify(meta)};

    function isProbablyFullscreen() {
      const threshold = 4;
      const screenWidth = window.screen?.width || 0;
      const screenHeight = window.screen?.height || 0;
      if (!screenWidth || !screenHeight) return false;
      const widthMatches = Math.abs(window.innerWidth - screenWidth) <= threshold
        || Math.abs(window.outerWidth - screenWidth) <= threshold;
      const heightMatches = Math.abs(window.innerHeight - screenHeight) <= threshold
        || Math.abs(window.outerHeight - screenHeight) <= threshold;
      return widthMatches && heightMatches;
    }

    const pick = (selector) => {
      const element = document.querySelector(selector);
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return {
        selector,
        tag: element.tagName.toLowerCase(),
        className: String(element.className),
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        top: Math.round(rect.top),
        left: Math.round(rect.left),
        maxWidth: style.maxWidth,
        paddingTop: style.paddingTop,
        marginLeft: style.marginLeft,
        marginRight: style.marginRight,
        threadContentMaxWidth: style.getPropertyValue("--thread-content-max-width").trim(),
        threadComposerMaxWidth: style.getPropertyValue("--thread-composer-max-width").trim(),
        markdownWideBlockMaxWidth: style.getPropertyValue("--markdown-wide-block-max-width").trim(),
        fullscreenHeaderOffset: style.getPropertyValue("--codex-app-extension-fullscreen-header-offset").trim()
      };
    };

    const describeElement = (element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return {
        tag: element.tagName.toLowerCase(),
        className: String(element.className),
        id: element.id || "",
        role: element.getAttribute("role") || "",
        dataTestid: element.getAttribute("data-testid") || "",
        ariaLabel: element.getAttribute("aria-label") || "",
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        top: Math.round(rect.top),
        left: Math.round(rect.left),
        maxWidth: style.maxWidth,
        marginLeft: style.marginLeft,
        marginRight: style.marginRight,
        position: style.position
      };
    };

    const composerElement = document.querySelector("textarea, [contenteditable='true'], [role='textbox']");
    const composerAncestors = [];
    for (let element = composerElement; element && composerAncestors.length < 8; element = element.parentElement) {
      composerAncestors.push(describeElement(element));
    }

    const bottomCandidates = Array.from(document.querySelectorAll("body *"))
      .map(describeElement)
      .filter((item) => item.top > window.innerHeight - 260 && item.width >= 300)
      .sort((a, b) => b.width - a.width)
      .slice(0, 30);

    const classSamples = Array.from(document.querySelectorAll("[class]"))
      .map((element) => String(element.className))
      .filter((className) => /thread|max-w|composer|markdown|mx-auto|container|viewport/.test(className))
      .slice(0, 80);

    const imeGuard = window.__codexAppExtensionImeGuard || null;
    const imeGuardState = imeGuard ? {
      installed: Boolean(imeGuard.installed),
      enabled: Boolean(imeGuard.enabled),
      lastCompositionEvent: imeGuard.lastCompositionEvent || null,
      lastKeydownEvent: imeGuard.lastKeydownEvent || null,
      lastBlockedEvent: imeGuard.lastBlockedEvent || null
    } : null;

    return {
      tool: ${JSON.stringify(APP_NAME)},
      config: meta,
      imeEnterGuardEnabled: Boolean(meta.imeEnterGuard),
      imeEnterGuardInstalled: Boolean(imeGuardState?.installed),
      imeEnterGuardState: imeGuardState,
      href: location.href,
      title: document.title,
      readyState: document.readyState,
      viewport: {
        innerWidth: window.innerWidth,
        innerHeight: window.innerHeight,
        outerWidth: window.outerWidth,
        outerHeight: window.outerHeight,
        screenWidth: window.screen?.width,
        screenHeight: window.screen?.height
      },
      detectedFullscreen: isProbablyFullscreen(),
      fullscreenAttribute: document.documentElement.dataset.codexAppExtensionFullscreen || "",
      injectedStyleExists: Boolean(document.getElementById(${JSON.stringify(STYLE_ID)})),
      legacyStyleExists: Boolean(document.getElementById(${JSON.stringify(LEGACY_STYLE_ID)})),
      root: pick("html"),
      body: pick("body"),
      header: pick("header.app-header-tint"),
      main: pick("main.main-surface"),
      mainViewport: pick(".app-shell-main-content-viewport"),
      layout: pick("[data-app-shell-main-content-layout]"),
      threadScrollContainer: pick(".thread-scroll-container"),
      threadMaxWidth: pick(".max-w-\\\\(--thread-content-max-width\\\\)"),
      threadMaxWidthVar: pick(".max-w-\\\\[var\\\\(--thread-content-max-width\\\\)\\\\]"),
      composerMaxWidth: pick(".max-w-\\\\[var\\\\(--thread-composer-max-width\\\\)\\\\]"),
      minThreadWidth: pick(".w-\\\\[min\\\\(100\\\\%\\\\,var\\\\(--thread-content-max-width\\\\)\\\\)\\\\]"),
      composerAncestors,
      bottomCandidates,
      sampleClasses: classSamples
    };
  })();`;
}

function buildInstallerSource(options) {
  const css = buildCss(options);
  const meta = buildMeta(options);
  const unifiedWidth = `min(${options.contentMaxWidth}, calc(100vw - ${options.sidePadding}))`;
  const variables = {
    "--thread-content-max-width": unifiedWidth,
    "--thread-composer-max-width": unifiedWidth,
    "--markdown-wide-block-max-width": unifiedWidth,
    "--codex-app-extension-fullscreen-header-offset": options.fullscreenHeaderOffset,
  };

  return `(() => {
    const STYLE_ID = ${JSON.stringify(STYLE_ID)};
    const LEGACY_STYLE_ID = ${JSON.stringify(LEGACY_STYLE_ID)};
    const css = ${JSON.stringify(css)};
    const variables = ${JSON.stringify(variables)};
    const meta = ${JSON.stringify(meta)};

    function cleanupLegacyWideLayout() {
      const legacyStyle = document.getElementById(LEGACY_STYLE_ID);
      if (legacyStyle) legacyStyle.remove();
      if (window.__codexWideLayoutObserver) {
        try {
          window.__codexWideLayoutObserver.disconnect();
        } catch {
          // Ignore stale observer cleanup failures.
        }
        delete window.__codexWideLayoutObserver;
      }
    }

    function upsertStyle() {
      const head = document.head || document.documentElement;
      let style = document.getElementById(STYLE_ID);
      if (!style) {
        style = document.createElement("style");
        style.id = STYLE_ID;
        style.dataset.owner = ${JSON.stringify(APP_NAME)};
        head.appendChild(style);
      }
      if (style.textContent !== css) {
        style.textContent = css;
      }
    }

    function applyVariables() {
      const targets = [
        document.documentElement,
        document.body,
        ...document.querySelectorAll(".app-shell-main-content-viewport, [data-app-shell-main-content-layout]")
      ].filter(Boolean);

      for (const target of targets) {
        for (const [name, value] of Object.entries(variables)) {
          if (target.style.getPropertyValue(name) !== value || target.style.getPropertyPriority(name) !== "important") {
            target.style.setProperty(name, value, "important");
          }
        }
      }
    }

    function isProbablyFullscreen() {
      const threshold = 4;
      const screenWidth = window.screen?.width || 0;
      const screenHeight = window.screen?.height || 0;
      if (!screenWidth || !screenHeight) return false;
      const widthMatches = Math.abs(window.innerWidth - screenWidth) <= threshold
        || Math.abs(window.outerWidth - screenWidth) <= threshold;
      const heightMatches = Math.abs(window.innerHeight - screenHeight) <= threshold
        || Math.abs(window.outerHeight - screenHeight) <= threshold;
      return widthMatches && heightMatches;
    }

    function applyFullscreenState() {
      const fullscreen = isProbablyFullscreen();
      document.documentElement.dataset.codexAppExtensionFullscreen = fullscreen ? "true" : "false";
      return fullscreen;
    }

    function installResizeListener() {
      window.__codexAppExtensionApplyFullscreenState = applyFullscreenState;
      if (window.__codexAppExtensionResizeHandler) return;

      window.__codexAppExtensionResizeHandler = () => {
        requestAnimationFrame(() => {
          window.__codexAppExtensionApplyFullscreenState?.();
        });
      };
      window.addEventListener("resize", window.__codexAppExtensionResizeHandler, { passive: true });
    }

    function installObserver() {
      if (window.__codexAppExtensionObserver) {
        try {
          window.__codexAppExtensionObserver.disconnect();
        } catch {
          // Ignore stale observer cleanup failures.
        }
      }

      let queued = false;
      const observer = new MutationObserver(() => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => {
          queued = false;
          upsertStyle();
          applyVariables();
          applyFullscreenState();
        });
      });
      observer.observe(document.documentElement, {
        attributes: true,
        childList: true,
        subtree: true,
        attributeFilter: ["class", "style", "data-app-shell-main-content-layout"]
      });
      window.__codexAppExtensionObserver = observer;
    }

    function getEditableElement(target) {
      let element = target;
      if (element?.nodeType === Node.TEXT_NODE) element = element.parentElement;
      if (!(element instanceof Element)) return null;
      return element.closest("textarea, input, [contenteditable='true'], [contenteditable='plaintext-only'], [role='textbox']");
    }

    function isTextInput(element) {
      if (!element) return false;
      if (element instanceof HTMLTextAreaElement) return true;
      if (element instanceof HTMLInputElement) {
        const type = (element.getAttribute("type") || "text").toLowerCase();
        return ["", "email", "number", "password", "search", "tel", "text", "url"].includes(type);
      }
      return element.isContentEditable || element.getAttribute("role") === "textbox";
    }

    function describeImeTarget(element) {
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      return {
        tag: element.tagName.toLowerCase(),
        className: String(element.className || "").slice(0, 160),
        role: element.getAttribute("role") || "",
        ariaLabel: element.getAttribute("aria-label") || "",
        contenteditable: element.getAttribute("contenteditable") || "",
        top: Math.round(rect.top),
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      };
    }

    function installImeEnterGuard() {
      const existing = window.__codexAppExtensionImeGuard;
      if (existing?.handlers) {
        document.removeEventListener("compositionstart", existing.handlers.compositionStart, true);
        document.removeEventListener("compositionend", existing.handlers.compositionEnd, true);
        window.removeEventListener("keydown", existing.handlers.keydown, true);
        document.removeEventListener("keydown", existing.handlers.keydown, true);
      }

      const state = {
        enabled: Boolean(meta.imeEnterGuard),
        installed: false,
        composingTargets: new WeakSet(),
        activeTarget: null,
        lastCompositionEndAt: 0,
        lastCompositionEvent: null,
        lastKeydownEvent: null,
        lastBlockedEvent: null,
        handlers: null
      };
      window.__codexAppExtensionImeGuard = state;

      if (!state.enabled) return state;

      const compositionStart = (event) => {
        const editable = getEditableElement(event.target);
        if (!isTextInput(editable)) return;
        state.activeTarget = editable;
        state.composingTargets.add(editable);
        state.lastCompositionEvent = {
          type: event.type,
          time: Date.now(),
          data: event.data || "",
          target: describeImeTarget(editable)
        };
      };

      const compositionEnd = (event) => {
        const editable = getEditableElement(event.target) || state.activeTarget;
        if (!isTextInput(editable)) return;
        state.lastCompositionEndAt = Date.now();
        state.lastCompositionEvent = {
          type: event.type,
          time: state.lastCompositionEndAt,
          data: event.data || "",
          target: describeImeTarget(editable)
        };

        window.setTimeout(() => {
          if (editable) state.composingTargets.delete(editable);
          if (state.activeTarget === editable) state.activeTarget = null;
        }, 120);
      };

      const keydown = (event) => {
        const editable = getEditableElement(event.target);
        if (!isTextInput(editable)) return;

        const now = Date.now();
        const recentCompositionEnd = state.lastCompositionEndAt > 0 && now - state.lastCompositionEndAt < 120;
        const targetComposing = state.composingTargets.has(editable) || state.activeTarget === editable;
        const imeManagedKey = event.isComposing || event.keyCode === 229 || targetComposing || recentCompositionEnd;
        const enterLike = event.key === "Enter"
          || event.code === "Enter"
          || event.code === "NumpadEnter"
          || event.keyCode === 13
          || (event.keyCode === 229 && imeManagedKey);

        state.lastKeydownEvent = {
          time: now,
          key: event.key,
          code: event.code,
          keyCode: event.keyCode,
          isComposing: Boolean(event.isComposing),
          enterLike,
          imeManagedKey,
          recentCompositionEnd,
          targetComposing,
          blocked: false,
          target: describeImeTarget(editable)
        };

        if (!enterLike || !imeManagedKey) return;

        event.stopImmediatePropagation();
        state.lastKeydownEvent.blocked = true;
        state.lastBlockedEvent = state.lastKeydownEvent;
      };

      state.handlers = { compositionStart, compositionEnd, keydown };
      document.addEventListener("compositionstart", compositionStart, true);
      document.addEventListener("compositionend", compositionEnd, true);
      window.addEventListener("keydown", keydown, true);
      document.addEventListener("keydown", keydown, true);
      state.installed = true;
      return state;
    }

    function install() {
      cleanupLegacyWideLayout();
      upsertStyle();
      applyVariables();
      const fullscreen = applyFullscreenState();
      installResizeListener();
      const imeGuard = installImeEnterGuard();

      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => {
          cleanupLegacyWideLayout();
          upsertStyle();
          applyVariables();
          applyFullscreenState();
          installImeEnterGuard();
          installObserver();
        }, { once: true });
      } else {
        installObserver();
      }

      const computedTarget = document.body || document.documentElement;
      const main = document.querySelector("main.main-surface");
      return {
        tool: ${JSON.stringify(APP_NAME)},
        styleId: STYLE_ID,
        config: meta,
        detectedFullscreen: fullscreen,
        fullscreenAttribute: document.documentElement.dataset.codexAppExtensionFullscreen || "",
        bodyThreadContentMaxWidth: getComputedStyle(computedTarget).getPropertyValue("--thread-content-max-width").trim(),
        bodyComposerMaxWidth: getComputedStyle(computedTarget).getPropertyValue("--thread-composer-max-width").trim(),
        bodyMarkdownWideBlockMaxWidth: getComputedStyle(computedTarget).getPropertyValue("--markdown-wide-block-max-width").trim(),
        mainPaddingTop: main ? getComputedStyle(main).paddingTop : null,
        imeEnterGuardEnabled: Boolean(meta.imeEnterGuard),
        imeEnterGuardInstalled: Boolean(imeGuard?.installed)
      };
    }

    return install();
  })();`;
}

function buildMeta(options) {
  return {
    configPath: options.configPath,
    configCreated: options.configCreated,
    contentMaxWidth: options.contentMaxWidth,
    fullscreenHeaderOffset: options.fullscreenHeaderOffset,
    imeEnterGuard: options.imeEnterGuard,
    sidePadding: options.sidePadding,
  };
}

function buildCss(options) {
  const width = `min(${options.contentMaxWidth}, calc(100vw - ${options.sidePadding}))`;

  return `
body[data-codex-window-type="electron"],
.app-shell-main-content-viewport,
[data-app-shell-main-content-layout] {
  --thread-content-max-width: ${width} !important;
  --thread-composer-max-width: ${width} !important;
  --markdown-wide-block-max-width: ${width} !important;
  --codex-app-extension-fullscreen-header-offset: ${options.fullscreenHeaderOffset} !important;
}

.max-w-\\(--thread-content-max-width\\),
.max-w-\\[var\\(--thread-content-max-width\\)\\] {
  max-width: var(--thread-content-max-width) !important;
}

.max-w-\\[var\\(--thread-composer-max-width\\)\\] {
  max-width: var(--thread-composer-max-width) !important;
}

.max-w-\\[var\\(--markdown-wide-block-max-width\\)\\],
.max-w-\\[min\\(90vw\\,var\\(--markdown-wide-block-max-width\\)\\)\\] {
  max-width: var(--markdown-wide-block-max-width) !important;
}

.w-\\[min\\(100\\%\\,var\\(--thread-content-max-width\\)\\)\\] {
  width: min(100%, var(--thread-content-max-width)) !important;
}

html[data-codex-app-extension-fullscreen="true"] main.main-surface {
  box-sizing: border-box !important;
  padding-top: var(--codex-app-extension-fullscreen-header-offset) !important;
}
`.trim();
}

main().catch((error) => {
  console.error(`[${APP_NAME}] ${error.message}`);
  process.exit(1);
});
