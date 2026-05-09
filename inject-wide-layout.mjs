#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const APP_NAME = "codex-app-extension";
const STYLE_ID = "codex-app-extension-style";
const LEGACY_STYLE_ID = "codex-wide-layout-style";

const DEFAULT_PORT = 9229;
const DEFAULT_SIDE_PADDING = "32px";
const DEFAULT_TARGET_TIMEOUT_MS = 30000;
const TARGET_POLL_INTERVAL_MS = 250;
const DEFAULT_CONFIG = Object.freeze({
  contentMaxWidth: "1800px",
  fullscreenHeaderOffset: "46px",
  imeEnterGuard: true,
  longTextSendEnhancement: false,
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
    } else if (arg === "--target-timeout-ms" && value) {
      cli.targetTimeoutMs = value;
      i += 1;
    } else if (arg === "--diagnose") {
      cli.diagnose = true;
    } else if (arg === "--disable-ime-enter-guard") {
      cli.imeEnterGuard = false;
    } else if (arg === "--enable-ime-enter-guard") {
      cli.imeEnterGuard = true;
    } else if (arg === "--disable-long-text-send-enhancement") {
      cli.longTextSendEnhancement = false;
    } else if (arg === "--enable-long-text-send-enhancement") {
      cli.longTextSendEnhancement = true;
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
  --target-timeout-ms <ms>            Wait for the Codex page target. Default: ${DEFAULT_TARGET_TIMEOUT_MS}
  --disable-ime-enter-guard           Disable IME Enter guard for this run.
  --enable-ime-enter-guard            Enable IME Enter guard for this run.
  --disable-long-text-send-enhancement
                                     Disable long text send enhancement for this run.
  --enable-long-text-send-enhancement
                                     Enable long text send enhancement for this run.
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
  const { target, targets } = await waitForTarget(options);

  if (!target) {
    const known = targets.map((item) => `${item.type || "unknown"} ${item.title || ""} ${item.url || ""}`).join("\n");
    throw new Error(`No attachable Codex page target found on port ${options.port} after ${options.targetTimeoutMs}ms.\nKnown targets:\n${known || "(none)"}`);
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
      longTextSendEnhancement: booleanOrUndefined(parsed.longTextSendEnhancement, "longTextSendEnhancement"),
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
    targetTimeoutMs: parsePositiveInteger("targetTimeoutMs", firstValue(
      cli.targetTimeoutMs,
      env.CODEX_APP_EXTENSION_TARGET_TIMEOUT_MS,
      DEFAULT_TARGET_TIMEOUT_MS,
    )),
    imeEnterGuard: parseBooleanOption("imeEnterGuard", firstValue(
      cli.imeEnterGuard,
      env.CODEX_APP_EXTENSION_IME_ENTER_GUARD,
      configInfo.values.imeEnterGuard,
      DEFAULT_CONFIG.imeEnterGuard,
    )),
    longTextSendEnhancement: parseBooleanOption("longTextSendEnhancement", firstValue(
      cli.longTextSendEnhancement,
      env.CODEX_APP_EXTENSION_LONG_TEXT_SEND_ENHANCEMENT,
      configInfo.values.longTextSendEnhancement,
      DEFAULT_CONFIG.longTextSendEnhancement,
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

function parsePositiveInteger(name, value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Invalid ${name}: expected a positive integer`);
  }
  return parsed;
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

async function waitForTarget(options) {
  const url = `http://127.0.0.1:${options.port}/json/list`;
  const deadline = Date.now() + options.targetTimeoutMs;
  let lastTargets = [];
  let lastError = null;

  while (Date.now() <= deadline) {
    try {
      const targets = await getJson(url);
      lastTargets = Array.isArray(targets) ? targets : [];
      const target = selectTarget(lastTargets, options.target);
      if (target) {
        return { target, targets: lastTargets };
      }
    } catch (error) {
      lastError = error;
    }

    await sleep(TARGET_POLL_INTERVAL_MS);
  }

  if (lastError && lastTargets.length === 0) {
    throw lastError;
  }

  return { target: null, targets: lastTargets };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

    const longText = window.__codexAppExtensionLongTextSendEnhancement || null;
    const longTextState = longText ? {
      installed: Boolean(longText.installed),
      enabled: Boolean(longText.enabled),
      lastSeenEnterEvent: longText.lastSeenEnterEvent || null,
      lastHandledEvent: longText.lastHandledEvent || null,
      lastIgnoredEvent: longText.lastIgnoredEvent || null
    } : null;

    return {
      tool: ${JSON.stringify(APP_NAME)},
      config: meta,
      imeEnterGuardEnabled: Boolean(meta.imeEnterGuard),
      imeEnterGuardInstalled: Boolean(imeGuardState?.installed),
      imeEnterGuardState: imeGuardState,
      longTextSendEnhancementEnabled: Boolean(meta.longTextSendEnhancement),
      longTextSendEnhancementInstalled: Boolean(longTextState?.installed),
      longTextSendEnhancementState: longTextState,
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

    function describeButton(element) {
      if (!element) return null;
      return {
        tag: element.tagName.toLowerCase(),
        className: String(element.className || "").slice(0, 160),
        text: (element.innerText || "").trim().slice(0, 80),
        ariaLabel: element.getAttribute("aria-label") || "",
        title: element.getAttribute("title") || "",
        disabled: Boolean(element.disabled),
        ariaDisabled: element.getAttribute("aria-disabled") || ""
      };
    }

    function isEnterKey(event) {
      return event.key === "Enter"
        || event.code === "Enter"
        || event.code === "NumpadEnter"
        || event.keyCode === 13;
    }

    function isVisibleElement(element) {
      if (!(element instanceof HTMLElement)) return false;
      const rect = element.getBoundingClientRect();
      if (rect.width < 1 || rect.height < 1) return false;
      const style = getComputedStyle(element);
      return style.display !== "none" && style.visibility !== "hidden";
    }

    function getButtonSignal(button) {
      const className = String(button.className || "");
      const label = [
        button.getAttribute("aria-label") || "",
        button.getAttribute("title") || "",
        button.innerText || ""
      ].join(" ");
      return { className, label };
    }

    function isComposerLikeButton(button) {
      if (!isVisibleElement(button)) return false;
      const { className, label } = getButtonSignal(button);
      return /composer|token-button-composer|h-token-button-composer|size-token-button-composer/i.test(className)
        || /听写|发送|提交|模型|自定义|添加文件|Send|Submit|Dictate|Model|Custom|Attach/i.test(label);
    }

    function getComposerRoot(editable) {
      let element = editable;
      for (let depth = 0; element && depth < 14; depth += 1, element = element.parentElement) {
        if (!(element instanceof HTMLElement)) continue;
        const hasComposerEditor = Boolean(element.querySelector(".ProseMirror[contenteditable]"));
        if (!hasComposerEditor) continue;

        const rect = element.getBoundingClientRect();
        if (rect.width < 220 || rect.height < 24) continue;

        const classText = [
          String(element.className || ""),
          element.getAttribute("data-testid") || "",
          element.getAttribute("aria-label") || ""
        ].join(" ");
        const hasComposerSurface = /composer|prompt|input|textarea|ProseMirror|bg-token-input|token-button-composer/i.test(classText)
          || Boolean(element.querySelector("[class*='composer'], [class*='token-button-composer']"));
        const buttons = Array.from(element.querySelectorAll("button"));
        const hasComposerButton = buttons.some(isComposerLikeButton);

        if (hasComposerButton && (hasComposerSurface || depth <= 6)) return element;
      }
      return null;
    }

    function isMainComposerEditable(editable) {
      if (!(editable instanceof HTMLElement)) return false;
      if (!editable.isContentEditable) return false;
      if (!editable.classList.contains("ProseMirror")) return false;
      if (editable.closest("[role='dialog'], [data-radix-popper-content-wrapper], nav, aside, header")) return false;
      if (!isVisibleElement(editable)) return false;
      const rect = editable.getBoundingClientRect();
      if (rect.width < 180 || rect.height < 12) return false;
      if (rect.bottom < 0 || rect.top > window.innerHeight) return false;
      return Boolean(getComposerRoot(editable));
    }

    function getRequestInputPanelRoot(editable) {
      if (!(editable instanceof HTMLTextAreaElement)) return null;
      if (!isVisibleElement(editable)) return null;
      if (editable.closest("[role='dialog'], [data-radix-popper-content-wrapper], nav, aside, header")) return null;
      const editableClassName = String(editable.className || "");
      if (!/request-input-panel|inline-freeform/i.test(editableClassName)) return null;

      let fallback = editable.parentElement || editable;
      for (let depth = 0, element = editable; element && depth < 12; depth += 1, element = element.parentElement) {
        if (!(element instanceof HTMLElement)) continue;
        const rect = element.getBoundingClientRect();
        const classText = [
          String(element.className || ""),
          element.getAttribute("data-testid") || "",
          element.getAttribute("aria-label") || ""
        ].join(" ");
        const hasPanelClass = /request-input-panel|inline-freeform/i.test(classText);
        const containsPanelTextarea = Boolean(element.querySelector("textarea.request-input-panel__inline-freeform"));
        const hasActionButton = Array.from(element.querySelectorAll("button")).some(isVisibleElement);

        if ((hasPanelClass || containsPanelTextarea) && rect.width >= 220 && rect.height >= 20) {
          fallback = element;
          if (hasActionButton || depth >= 2) return element;
        }
      }
      return fallback;
    }

    function getLongTextManagedInput(editable) {
      if (isMainComposerEditable(editable)) {
        return {
          kind: "prosemirror-composer",
          element: editable,
          root: getComposerRoot(editable)
        };
      }

      const requestInputPanelRoot = getRequestInputPanelRoot(editable);
      if (requestInputPanelRoot) {
        return {
          kind: "request-input-panel-textarea",
          element: editable,
          root: requestInputPanelRoot
        };
      }

      return null;
    }

    function isImeManagedEnter(event, editable) {
      if (!isEnterKey(event)) return false;
      const imeGuard = window.__codexAppExtensionImeGuard;
      const recentCompositionEnd = imeGuard?.lastCompositionEndAt > 0
        && Date.now() - imeGuard.lastCompositionEndAt < 120;
      const targetComposing = Boolean(imeGuard?.activeTarget === editable)
        || Boolean(imeGuard?.composingTargets?.has?.(editable));
      return Boolean(event.isComposing)
        || event.keyCode === 229
        || recentCompositionEnd
        || targetComposing;
    }

    function findSendButton(editable) {
      const root = getComposerRoot(editable);
      if (!root) return null;
      const buttons = Array.from(root.querySelectorAll("button")).filter((button) => {
        if (button.disabled) return false;
        if (button.getAttribute("aria-disabled") === "true") return false;
        if (button.offsetParent === null && getComputedStyle(button).position !== "fixed") return false;
        const label = [
          button.getAttribute("aria-label") || "",
          button.getAttribute("title") || "",
          button.innerText || ""
        ].join(" ");
        if (/停止|Stop|Cancel|中断|interrupt/i.test(label)) return false;
        if (/听写|添加文件|设置|模型|自定义|本地模式|分支|滚动/i.test(label)) return false;
        return true;
      });

      const explicit = buttons.find((button) => {
        const label = [
          button.getAttribute("aria-label") || "",
          button.getAttribute("title") || "",
          button.innerText || ""
        ].join(" ");
        return /发送|Send|Submit|提交/i.test(label);
      });
      if (explicit) return explicit;

      return buttons.reverse().find((button) => {
        const className = String(button.className || "");
        return className.includes("size-token-button-composer");
      }) || null;
    }

    function findRequestPanelSendButton(managedInput) {
      const root = managedInput?.root;
      if (!root) return null;
      const buttons = Array.from(root.querySelectorAll("button")).filter((button) => {
        if (button.disabled) return false;
        if (button.getAttribute("aria-disabled") === "true") return false;
        if (!isVisibleElement(button)) return false;
        const { label } = getButtonSignal(button);
        if (/取消|关闭|返回|Cancel|Close|Back/i.test(label)) return false;
        if (/添加文件|听写|模型|自定义|Attach|Dictate|Model|Custom/i.test(label)) return false;
        return true;
      });

      const explicit = buttons.find((button) => {
        const { label } = getButtonSignal(button);
        return /发送|提交|确认|继续|回复|Send|Submit|Confirm|Continue|Reply/i.test(label);
      });
      if (explicit) return explicit;

      return buttons.reverse().find((button) => {
        const { className, label } = getButtonSignal(button);
        return /primary|submit|send|accent|solid|button/i.test(className) || label.trim();
      }) || null;
    }

    function insertComposerLineBreak(editable, state) {
      editable.focus();

      state.syntheticDepth += 1;
      try {
        const shiftEnter = new KeyboardEvent("keydown", {
          key: "Enter",
          code: "Enter",
          keyCode: 13,
          which: 13,
          bubbles: true,
          cancelable: true,
          shiftKey: true
        });
        editable.dispatchEvent(shiftEnter);
        if (shiftEnter.defaultPrevented) return true;
      } finally {
        state.syntheticDepth -= 1;
      }

      if (document.queryCommandSupported?.("insertLineBreak") && document.execCommand("insertLineBreak")) {
        return true;
      }
      if (document.queryCommandSupported?.("insertText") && document.execCommand("insertText", false, "\\n")) {
        return true;
      }
      return false;
    }

    function insertTextareaLineBreak(textarea) {
      if (!(textarea instanceof HTMLTextAreaElement)) return false;
      textarea.focus();

      const start = Number.isInteger(textarea.selectionStart) ? textarea.selectionStart : textarea.value.length;
      const end = Number.isInteger(textarea.selectionEnd) ? textarea.selectionEnd : start;
      const nextValue = textarea.value.slice(0, start) + "\\n" + textarea.value.slice(end);
      const valueSetter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set;
      if (valueSetter) {
        valueSetter.call(textarea, nextValue);
      } else {
        textarea.value = nextValue;
      }
      textarea.selectionStart = start + 1;
      textarea.selectionEnd = start + 1;

      const inputEvent = typeof InputEvent === "function"
        ? new InputEvent("input", {
          bubbles: true,
          cancelable: true,
          inputType: "insertLineBreak",
          data: null
        })
        : new Event("input", { bubbles: true, cancelable: true });
      textarea.dispatchEvent(inputEvent);
      return true;
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

    function installLongTextSendEnhancement() {
      const existing = window.__codexAppExtensionLongTextSendEnhancement;
      if (existing?.handlers) {
        if (existing.handlers.keydown) {
          window.removeEventListener("keydown", existing.handlers.keydown, true);
          document.removeEventListener("keydown", existing.handlers.keydown, true);
        }
        if (existing.handlers.suppressFollowup) {
          window.removeEventListener("keypress", existing.handlers.suppressFollowup, true);
          document.removeEventListener("keypress", existing.handlers.suppressFollowup, true);
          window.removeEventListener("keyup", existing.handlers.suppressFollowup, true);
          document.removeEventListener("keyup", existing.handlers.suppressFollowup, true);
        }
      }

      const state = {
        enabled: Boolean(meta.longTextSendEnhancement),
        installed: false,
        lastSeenEnterEvent: null,
        lastHandledEvent: null,
        lastIgnoredEvent: null,
        handlers: null,
        syntheticDepth: 0,
        suppressEnterUntil: 0,
        suppressEditable: null,
        suppressAction: ""
      };
      window.__codexAppExtensionLongTextSendEnhancement = state;

      if (!state.enabled) return state;

      const buildEventInfo = (event, editable, managedInput, extra = {}) => ({
        time: Date.now(),
        type: event.type,
        key: event.key,
        code: event.code,
        keyCode: event.keyCode,
        metaKey: Boolean(event.metaKey),
        ctrlKey: Boolean(event.ctrlKey),
        altKey: Boolean(event.altKey),
        shiftKey: Boolean(event.shiftKey),
        isComposing: Boolean(event.isComposing),
        action: "",
        handled: false,
        target: describeImeTarget(editable),
        inputKind: managedInput?.kind || null,
        managedRoot: describeImeTarget(managedInput?.root || null),
        composerRoot: describeImeTarget(managedInput?.kind === "prosemirror-composer" ? managedInput.root : null),
        ...extra
      });

      const ignoreEnter = (event, editable, managedInput, reason, extra = {}) => {
        state.lastIgnoredEvent = buildEventInfo(event, editable, managedInput, {
          action: "ignore",
          reason,
          ...extra
        });
      };

      const suppressNextEnterEvents = (editable, action) => {
        state.suppressEnterUntil = Date.now() + 800;
        state.suppressEditable = editable;
        state.suppressAction = action;
      };

      const matchesSuppressedEditable = (editable) => {
        if (!state.suppressEditable) return true;
        if (!editable) return false;
        return editable === state.suppressEditable
          || Boolean(state.suppressEditable.contains?.(editable))
          || Boolean(editable.contains?.(state.suppressEditable));
      };

      const suppressFollowup = (event) => {
        if (state.syntheticDepth > 0) return;
        if (!isEnterKey(event)) return;

        const editable = getEditableElement(event.target);
        const managedInput = getLongTextManagedInput(editable);
        state.lastSeenEnterEvent = buildEventInfo(event, editable, managedInput);

        if (Date.now() > state.suppressEnterUntil) return;
        if (!matchesSuppressedEditable(editable)) return;
        if (!managedInput) return;

        event.preventDefault();
        event.stopImmediatePropagation();
        state.lastHandledEvent = buildEventInfo(event, editable, managedInput, {
          action: "suppress-" + event.type,
          handled: true,
          suppressedAction: state.suppressAction
        });
      };

      const keydown = (event) => {
        if (state.syntheticDepth > 0) return;
        if (!isEnterKey(event)) return;

        const editable = getEditableElement(event.target);
        const managedInput = getLongTextManagedInput(editable);
        state.lastSeenEnterEvent = buildEventInfo(event, editable, managedInput);
        if (!managedInput) {
          ignoreEnter(event, editable, managedInput, "not-composer");
          return;
        }
        if (isImeManagedEnter(event, editable)) {
          ignoreEnter(event, editable, managedInput, "ime-composing");
          return;
        }

        const cmdEnter = event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
        const plainEnter = !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
        if (!cmdEnter && !plainEnter) {
          ignoreEnter(event, editable, managedInput, "unsupported-modifier");
          return;
        }

        const eventInfo = buildEventInfo(event, editable, managedInput, {
          sendButton: null,
          insertedLineBreak: false
        });

        if (cmdEnter) {
          const sendButton = managedInput.kind === "request-input-panel-textarea"
            ? findRequestPanelSendButton(managedInput)
            : findSendButton(editable);
          eventInfo.sendButton = describeButton(sendButton);
          if (!sendButton) {
            state.lastIgnoredEvent = {
              ...eventInfo,
              action: "native-send-fallback",
              reason: "no-send-button"
            };
            return;
          }

          event.preventDefault();
          event.stopImmediatePropagation();
          suppressNextEnterEvents(editable, "send");
          sendButton.click();
          eventInfo.action = "send";
          eventInfo.handled = true;
          state.lastHandledEvent = eventInfo;
          return;
        }

        event.preventDefault();
        event.stopImmediatePropagation();
        suppressNextEnterEvents(editable, "newline");
        eventInfo.action = "newline";
        eventInfo.insertedLineBreak = managedInput.kind === "request-input-panel-textarea"
          ? insertTextareaLineBreak(editable)
          : insertComposerLineBreak(editable, state);
        eventInfo.handled = true;
        state.lastHandledEvent = eventInfo;
      };

      state.handlers = { keydown, suppressFollowup };
      window.addEventListener("keydown", keydown, true);
      document.addEventListener("keydown", keydown, true);
      window.addEventListener("keypress", suppressFollowup, true);
      document.addEventListener("keypress", suppressFollowup, true);
      window.addEventListener("keyup", suppressFollowup, true);
      document.addEventListener("keyup", suppressFollowup, true);
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
      const longTextSend = installLongTextSendEnhancement();

      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => {
          cleanupLegacyWideLayout();
          upsertStyle();
          applyVariables();
          applyFullscreenState();
          installImeEnterGuard();
          installLongTextSendEnhancement();
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
        imeEnterGuardInstalled: Boolean(imeGuard?.installed),
        longTextSendEnhancementEnabled: Boolean(meta.longTextSendEnhancement),
        longTextSendEnhancementInstalled: Boolean(longTextSend?.installed)
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
    longTextSendEnhancement: options.longTextSendEnhancement,
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
