#!/usr/bin/env node

import { existsSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

const APP_NAME = "codex-app-extension";
const STYLE_ID = "codex-app-extension-style";
const LEGACY_STYLE_ID = "codex-wide-layout-style";

const DEFAULT_PORT = 9229;
const DEFAULT_HORIZONTAL_GUTTER = "20px";
const DEFAULT_TARGET_TIMEOUT_MS = 30000;
const TARGET_POLL_INTERVAL_MS = 250;
const DEFAULT_THEME_ENHANCEMENT_COLORS = Object.freeze({
  orderedListMarker: "#fcfcfc",
  unorderedListMarker: "#fcfcfc",
  inlineCodeText: "#df3079",
  inlineCodeBackground: "rgba(223, 48, 121, 0.10)",
  inlineCodeBorder: "rgba(223, 48, 121, 0.18)",
  blockquoteBorder: "#00a67d",
  blockquoteText: "rgba(252, 252, 252, 0.78)",
  blockquoteBackground: "rgba(0, 166, 125, 0.06)",
  headingText: "#00a67d",
  strongText: "#00a67d",
});
const THEME_ENHANCEMENT_COLOR_KEYS = Object.freeze(Object.keys(DEFAULT_THEME_ENHANCEMENT_COLORS));
const DEFAULT_THEME_ENHANCEMENT_TYPOGRAPHY = Object.freeze({
  strongFontWeight: null,
  strongFontSize: null,
});
const THEME_ENHANCEMENT_TYPOGRAPHY_KEYS = Object.freeze(Object.keys(DEFAULT_THEME_ENHANCEMENT_TYPOGRAPHY));
const DEFAULT_CONFIG = Object.freeze({
  wideLayoutEnhancement: true,
  contentMaxWidth: "1800px",
  horizontalGutter: DEFAULT_HORIZONTAL_GUTTER,
  fullscreenHeaderOffset: "46px",
  imeEnterGuard: true,
  longTextSendEnhancement: false,
  tabIndentEnhancement: false,
  layoutFocusRingFix: true,
  themeEnhancement: false,
  themeEnhancementColors: DEFAULT_THEME_ENHANCEMENT_COLORS,
  themeEnhancementTypography: DEFAULT_THEME_ENHANCEMENT_TYPOGRAPHY,
});
const DEPRECATED_CONFIG_KEYS = new Set([
  "minimumSideGutter",
  "minimumTotalSidePadding",
  "minSideGutter",
  "minTotalSidePadding",
  "sidePadding",
]);

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
    } else if (arg === "--horizontal-gutter" && value) {
      cli.horizontalGutter = value;
      i += 1;
    } else if (["--thread-max", "--composer-max", "--markdown-max"].includes(arg) && value) {
      cli.contentMaxWidth = value;
      i += 1;
    } else if (arg === "--fullscreen-header-offset" && value) {
      cli.fullscreenHeaderOffset = value;
      i += 1;
    } else if (arg === "--target" && value) {
      cli.target = value;
      i += 1;
    } else if (arg === "--target-timeout-ms" && value) {
      cli.targetTimeoutMs = value;
      i += 1;
    } else if (arg === "--diagnose") {
      cli.diagnose = true;
    } else if (arg === "--configure") {
      cli.configure = true;
    } else if (arg === "--disable-wide-layout-enhancement") {
      cli.wideLayoutEnhancement = false;
    } else if (arg === "--enable-wide-layout-enhancement") {
      cli.wideLayoutEnhancement = true;
    } else if (arg === "--disable-ime-enter-guard") {
      cli.imeEnterGuard = false;
    } else if (arg === "--enable-ime-enter-guard") {
      cli.imeEnterGuard = true;
    } else if (arg === "--disable-long-text-send-enhancement") {
      cli.longTextSendEnhancement = false;
    } else if (arg === "--enable-long-text-send-enhancement") {
      cli.longTextSendEnhancement = true;
    } else if (arg === "--disable-tab-indent-enhancement") {
      cli.tabIndentEnhancement = false;
    } else if (arg === "--enable-tab-indent-enhancement") {
      cli.tabIndentEnhancement = true;
    } else if (arg === "--disable-layout-focus-ring-fix") {
      cli.layoutFocusRingFix = false;
    } else if (arg === "--enable-layout-focus-ring-fix") {
      cli.layoutFocusRingFix = true;
    } else if (arg === "--disable-theme-enhancement") {
      cli.themeEnhancement = false;
    } else if (arg === "--enable-theme-enhancement") {
      cli.themeEnhancement = true;
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
  --horizontal-gutter <css-size>      Horizontal gutter kept on both left and right when wide layout is enabled.
                                     Default: ${DEFAULT_CONFIG.horizontalGutter}
  --fullscreen-header-offset <size>   Top offset used to avoid the app header in windowed and fullscreen modes.
                                     Default: ${DEFAULT_CONFIG.fullscreenHeaderOffset}
  --target <text>                     Prefer a debugger target whose title/url includes this text.
  --target-timeout-ms <ms>            Wait for the Codex page target. Default: ${DEFAULT_TARGET_TIMEOUT_MS}
  --disable-wide-layout-enhancement   Disable content width, gutter, and right rail avoidance for this run.
  --enable-wide-layout-enhancement    Enable content width, gutter, and right rail avoidance for this run.
  --disable-ime-enter-guard           Disable IME Enter guard for this run.
  --enable-ime-enter-guard            Enable IME Enter guard for this run.
  --disable-long-text-send-enhancement
                                     Disable long text send enhancement for this run.
  --enable-long-text-send-enhancement
                                     Enable long text send enhancement for this run.
  --disable-tab-indent-enhancement   Disable Tab indentation enhancement for this run.
  --enable-tab-indent-enhancement    Enable Tab indentation enhancement for this run.
  --disable-layout-focus-ring-fix    Disable accidental layout focus ring fix for this run.
  --enable-layout-focus-ring-fix     Enable accidental layout focus ring fix for this run.
  --disable-theme-enhancement        Disable Markdown theme enhancement for this run.
  --enable-theme-enhancement         Enable Markdown theme enhancement for this run.
  --configure                        Review and complete ~/.codex-app-extension/config.json.
  --diagnose                          Print current Codex layout facts without changing CSS.

Config:
  ~/.codex-app-extension/config.json

Legacy aliases:
  --thread-max, --composer-max, --markdown-max all map to --content-max-width.
`);
}

async function main() {
  const cli = parseCliArgs(process.argv.slice(2));
  if (cli.help) {
    printHelp();
    process.exit(0);
  }
  if (cli.configure) {
    await configureConfig();
    return;
  }

  if (typeof WebSocket !== "function") {
    throw new Error("This Node.js runtime does not expose WebSocket. Try NODE_BIN=/Applications/Codex.app/Contents/Resources/node.");
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

function ensureConfig({ createIfMissing = false } = {}) {
  const configDir = join(homedir(), ".codex-app-extension");
  const configPath = join(configDir, "config.json");
  let created = false;
  let parsed;

  if (!existsSync(configPath) && !isSymlink(configPath)) {
    if (!createIfMissing) {
      throw new Error(`Missing config at ${configPath}. Run ./launch.sh for first-time setup, or run ./follow-author-config.sh / ./config.sh first.`);
    }
    mkdirSync(configDir, { recursive: true });
    created = true;
    parsed = {};
  }

  if (!created) {
    const raw = readFileSync(configPath, "utf8");
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      throw new Error(`Invalid config JSON at ${configPath}: ${error.message}`);
    }
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`Invalid config at ${configPath}: expected a JSON object`);
  }

  return {
    path: configPath,
    created,
    raw: parsed,
    values: {
      wideLayoutEnhancement: booleanOrUndefined(parsed.wideLayoutEnhancement, "wideLayoutEnhancement"),
      contentMaxWidth: stringOrUndefined(parsed.contentMaxWidth),
      horizontalGutter: stringOrUndefined(parsed.horizontalGutter),
      fullscreenHeaderOffset: stringOrUndefined(parsed.fullscreenHeaderOffset),
      imeEnterGuard: booleanOrUndefined(parsed.imeEnterGuard, "imeEnterGuard"),
      longTextSendEnhancement: booleanOrUndefined(parsed.longTextSendEnhancement, "longTextSendEnhancement"),
      tabIndentEnhancement: booleanOrUndefined(parsed.tabIndentEnhancement, "tabIndentEnhancement"),
      layoutFocusRingFix: booleanOrUndefined(parsed.layoutFocusRingFix, "layoutFocusRingFix"),
      themeEnhancement: booleanOrUndefined(parsed.themeEnhancement, "themeEnhancement"),
      themeEnhancementColors: themeColorsOrUndefined(parsed.themeEnhancementColors),
      themeEnhancementTypography: themeTypographyOrUndefined(parsed.themeEnhancementTypography),
    },
  };
}

async function configureConfig() {
  const configInfo = ensureConfig({ createIfMissing: true });
  const nextConfig = buildCompleteConfig(configInfo.values);
  const promptSession = await createPromptSession();

  try {
    console.log(`[${APP_NAME}] Config file: ${configInfo.path}`);
    if (configInfo.created) {
      console.log(`[${APP_NAME}] Config file was missing, using defaults as initial values.`);
    }
    console.log(`[${APP_NAME}] Press Enter to keep the current value shown in brackets.`);

    nextConfig.wideLayoutEnhancement = await askBoolean(promptSession, {
      label: "Enable wide layout enhancement",
      current: nextConfig.wideLayoutEnhancement,
    });
    nextConfig.contentMaxWidth = await askCssSize(promptSession, {
      key: "contentMaxWidth",
      label: "Content max width",
      current: nextConfig.contentMaxWidth,
    });
    nextConfig.horizontalGutter = await askCssSize(promptSession, {
      key: "horizontalGutter",
      label: "Horizontal gutter",
      current: nextConfig.horizontalGutter,
    });
    nextConfig.fullscreenHeaderOffset = await askCssSize(promptSession, {
      key: "fullscreenHeaderOffset",
      label: "Fullscreen header offset",
      current: nextConfig.fullscreenHeaderOffset,
    });
    nextConfig.imeEnterGuard = await askBoolean(promptSession, {
      label: "Enable IME Enter guard",
      current: nextConfig.imeEnterGuard,
    });
    nextConfig.longTextSendEnhancement = await askBoolean(promptSession, {
      label: "Enable long text send enhancement",
      current: nextConfig.longTextSendEnhancement,
    });
    nextConfig.tabIndentEnhancement = await askBoolean(promptSession, {
      label: "Enable Tab indentation enhancement",
      current: nextConfig.tabIndentEnhancement,
    });
    nextConfig.layoutFocusRingFix = await askBoolean(promptSession, {
      label: "Enable layout focus ring fix",
      current: nextConfig.layoutFocusRingFix,
    });
    nextConfig.themeEnhancement = await askBoolean(promptSession, {
      label: "Enable Markdown theme enhancement",
      current: nextConfig.themeEnhancement,
    });

    assertCompleteConfigValues(nextConfig);
    writeCompleteConfig(configInfo.path, configInfo.raw, nextConfig);

    console.log(`[${APP_NAME}] Config completed and saved.`);
    console.log(`[${APP_NAME}] Full config keys are now present in ${configInfo.path}.`);
    if (nextConfig.themeEnhancement) {
      console.log(`[${APP_NAME}] Markdown theme enhancement is enabled. Edit themeEnhancementColors and themeEnhancementTypography in the config file for colors and typography.`);
    } else {
      console.log(`[${APP_NAME}] Theme color and typography defaults were still written, so enabling themeEnhancement later has a complete config block ready.`);
    }
  } finally {
    promptSession.close();
  }
}

function buildCompleteConfig(values) {
  return {
    wideLayoutEnhancement: parseBooleanOption("wideLayoutEnhancement", firstValue(values.wideLayoutEnhancement, DEFAULT_CONFIG.wideLayoutEnhancement)),
    contentMaxWidth: firstValue(values.contentMaxWidth, DEFAULT_CONFIG.contentMaxWidth),
    horizontalGutter: firstValue(values.horizontalGutter, DEFAULT_CONFIG.horizontalGutter),
    fullscreenHeaderOffset: firstValue(values.fullscreenHeaderOffset, DEFAULT_CONFIG.fullscreenHeaderOffset),
    imeEnterGuard: parseBooleanOption("imeEnterGuard", firstValue(values.imeEnterGuard, DEFAULT_CONFIG.imeEnterGuard)),
    longTextSendEnhancement: parseBooleanOption("longTextSendEnhancement", firstValue(values.longTextSendEnhancement, DEFAULT_CONFIG.longTextSendEnhancement)),
    tabIndentEnhancement: parseBooleanOption("tabIndentEnhancement", firstValue(values.tabIndentEnhancement, DEFAULT_CONFIG.tabIndentEnhancement)),
    layoutFocusRingFix: parseBooleanOption("layoutFocusRingFix", firstValue(values.layoutFocusRingFix, DEFAULT_CONFIG.layoutFocusRingFix)),
    themeEnhancement: parseBooleanOption("themeEnhancement", firstValue(values.themeEnhancement, DEFAULT_CONFIG.themeEnhancement)),
    // Complex theme values are completed but not edited interactively; users need the JSON context to tune them safely.
    themeEnhancementColors: {
      ...DEFAULT_THEME_ENHANCEMENT_COLORS,
      ...(values.themeEnhancementColors || {}),
    },
    themeEnhancementTypography: {
      ...DEFAULT_THEME_ENHANCEMENT_TYPOGRAPHY,
      ...(values.themeEnhancementTypography || {}),
    },
  };
}

async function createPromptSession() {
  if (!process.stdin.isTTY) {
    const answers = await readStdinLines();
    return {
      close() {},
      async question(prompt) {
        process.stdout.write(prompt);
        return answers.length ? answers.shift() : "";
      },
    };
  }

  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return {
    close() {
      rl.close();
    },
    question(prompt) {
      return new Promise((resolve) => {
        rl.question(prompt, resolve);
      });
    },
  };
}

function readStdinLines() {
  return new Promise((resolve) => {
    let raw = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      raw += chunk;
    });
    process.stdin.on("end", () => {
      resolve(raw.split(/\r?\n/));
    });
    process.stdin.resume();
  });
}

async function askCssSize(promptSession, { key, label, current }) {
  while (true) {
    const answer = (await promptSession.question(`[${APP_NAME}] ${label} [${current}]: `)).trim();
    const value = answer || current;
    try {
      assertCssSize(key, value);
      return value;
    } catch (error) {
      console.log(`[${APP_NAME}] ${error.message}`);
    }
  }
}

async function askBoolean(promptSession, { label, current }) {
  const hint = current ? "Y/n" : "y/N";
  while (true) {
    const answer = (await promptSession.question(`[${APP_NAME}] ${label} [${hint}]: `)).trim();
    if (!answer) return current;
    try {
      return parseBooleanOption(label, answer);
    } catch {
      console.log(`[${APP_NAME}] Please answer y/n, true/false, on/off, or 1/0.`);
    }
  }
}

function writeCompleteConfig(configPath, rawConfig, knownConfig) {
  const outputConfig = { ...knownConfig };
  for (const [key, value] of Object.entries(rawConfig)) {
    if (DEPRECATED_CONFIG_KEYS.has(key)) continue;
    if (!Object.prototype.hasOwnProperty.call(DEFAULT_CONFIG, key)) {
      outputConfig[key] = value;
    }
  }
  if (isSymlink(configPath)) {
    rmSync(configPath);
  }
  writeFileSync(configPath, `${JSON.stringify(outputConfig, null, 2)}\n`, "utf8");
}

function isSymlink(path) {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch {
    return false;
  }
}

function assertCompleteConfigValues(config) {
  parseBooleanOption("wideLayoutEnhancement", config.wideLayoutEnhancement);
  assertCssSize("contentMaxWidth", config.contentMaxWidth);
  assertCssSize("horizontalGutter", config.horizontalGutter);
  assertCssSize("fullscreenHeaderOffset", config.fullscreenHeaderOffset);
  for (const [key, value] of Object.entries(config.themeEnhancementColors)) {
    assertCssColor(`themeEnhancementColors.${key}`, value);
  }
  for (const [key, value] of Object.entries(config.themeEnhancementTypography)) {
    if (value !== null) assertCssValue(`themeEnhancementTypography.${key}`, value);
  }
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
    wideLayoutEnhancement: parseBooleanOption("wideLayoutEnhancement", firstValue(
      cli.wideLayoutEnhancement,
      env.CODEX_APP_EXTENSION_WIDE_LAYOUT_ENHANCEMENT,
      configInfo.values.wideLayoutEnhancement,
      DEFAULT_CONFIG.wideLayoutEnhancement,
    )),
    contentMaxWidth: firstValue(
      cli.contentMaxWidth,
      env.CODEX_APP_EXTENSION_CONTENT_MAX_WIDTH,
      env.CODEX_WIDE_THREAD_MAX,
      env.CODEX_WIDE_COMPOSER_MAX,
      env.CODEX_WIDE_MARKDOWN_MAX,
      configInfo.values.contentMaxWidth,
      DEFAULT_CONFIG.contentMaxWidth,
    ),
    horizontalGutter: firstValue(
      cli.horizontalGutter,
      env.CODEX_APP_EXTENSION_HORIZONTAL_GUTTER,
      configInfo.values.horizontalGutter,
      DEFAULT_CONFIG.horizontalGutter,
    ),
    fullscreenHeaderOffset: firstValue(
      cli.fullscreenHeaderOffset,
      env.CODEX_APP_EXTENSION_FULLSCREEN_HEADER_OFFSET,
      configInfo.values.fullscreenHeaderOffset,
      DEFAULT_CONFIG.fullscreenHeaderOffset,
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
    tabIndentEnhancement: parseBooleanOption("tabIndentEnhancement", firstValue(
      cli.tabIndentEnhancement,
      env.CODEX_APP_EXTENSION_TAB_INDENT_ENHANCEMENT,
      configInfo.values.tabIndentEnhancement,
      DEFAULT_CONFIG.tabIndentEnhancement,
    )),
    layoutFocusRingFix: parseBooleanOption("layoutFocusRingFix", firstValue(
      cli.layoutFocusRingFix,
      env.CODEX_APP_EXTENSION_LAYOUT_FOCUS_RING_FIX,
      configInfo.values.layoutFocusRingFix,
      DEFAULT_CONFIG.layoutFocusRingFix,
    )),
    themeEnhancement: parseBooleanOption("themeEnhancement", firstValue(
      cli.themeEnhancement,
      env.CODEX_APP_EXTENSION_THEME_ENHANCEMENT,
      configInfo.values.themeEnhancement,
      DEFAULT_CONFIG.themeEnhancement,
    )),
    themeEnhancementColors: {
      ...DEFAULT_THEME_ENHANCEMENT_COLORS,
      ...(configInfo.values.themeEnhancementColors || {}),
    },
    themeEnhancementTypography: {
      ...DEFAULT_THEME_ENHANCEMENT_TYPOGRAPHY,
      ...(configInfo.values.themeEnhancementTypography || {}),
    },
    diagnose: Boolean(cli.diagnose),
    configPath: configInfo.path,
    configCreated: configInfo.created,
  };

  assertCssSize("contentMaxWidth", options.contentMaxWidth);
  assertCssSize("horizontalGutter", options.horizontalGutter);
  assertCssSize("fullscreenHeaderOffset", options.fullscreenHeaderOffset);
  for (const [key, value] of Object.entries(options.themeEnhancementColors)) {
    assertCssColor(`themeEnhancementColors.${key}`, value);
  }
  for (const [key, value] of Object.entries(options.themeEnhancementTypography)) {
    if (value !== null) assertCssValue(`themeEnhancementTypography.${key}`, value);
  }

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

function themeColorsOrUndefined(value) {
  if (value === undefined || value === null) return undefined;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid themeEnhancementColors: expected a JSON object");
  }

  const colors = {};
  for (const key of THEME_ENHANCEMENT_COLOR_KEYS) {
    const color = stringOrUndefined(value[key]);
    if (color) colors[key] = color;
  }
  return colors;
}

function themeTypographyOrUndefined(value) {
  if (value === undefined || value === null) return undefined;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid themeEnhancementTypography: expected a JSON object");
  }

  const typography = {};
  for (const key of THEME_ENHANCEMENT_TYPOGRAPHY_KEYS) {
    const setting = cssStringOrNullOrUndefined(value[key]);
    if (setting !== undefined) typography[key] = setting;
  }
  return typography;
}

function cssStringOrNullOrUndefined(value) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  return stringOrUndefined(value);
}

function parseBooleanOption(name, value) {
  if (typeof value === "boolean") return value;
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  throw new Error(`Invalid ${name}: expected true/false, y/n, on/off, or 1/0`);
}

function assertCssSize(name, value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Invalid ${name}: expected a non-empty CSS size`);
  }
}

function assertCssColor(name, value) {
  assertCssValue(name, value);
}

function assertCssValue(name, value) {
  if (typeof value !== "string" || !value.trim() || /[;{}<>]/.test(value)) {
    throw new Error(`Invalid ${name}: expected a safe CSS value`);
  }
}

function buildHorizontalPadding(horizontalGutter) {
  return `calc(${horizontalGutter} + ${horizontalGutter})`;
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
        right: Math.round(rect.right),
        maxWidth: style.maxWidth,
        translate: style.translate,
        paddingTop: style.paddingTop,
        marginLeft: style.marginLeft,
        marginRight: style.marginRight,
        threadContentMaxWidth: style.getPropertyValue("--thread-content-max-width").trim(),
        threadComposerMaxWidth: style.getPropertyValue("--thread-composer-max-width").trim(),
        markdownWideBlockMaxWidth: style.getPropertyValue("--markdown-wide-block-max-width").trim(),
        contentOffsetX: style.getPropertyValue("--codex-app-extension-content-offset-x").trim(),
        horizontalPadding: style.getPropertyValue("--codex-app-extension-horizontal-padding").trim(),
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
        right: Math.round(rect.right),
        maxWidth: style.maxWidth,
        translate: style.translate,
        marginLeft: style.marginLeft,
        marginRight: style.marginRight,
        contentOffsetX: style.getPropertyValue("--codex-app-extension-content-offset-x").trim(),
        horizontalPadding: style.getPropertyValue("--codex-app-extension-horizontal-padding").trim(),
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
      lastBlockedEvent: imeGuard.lastBlockedEvent || null,
      lastSkippedEvent: imeGuard.lastSkippedEvent || null
    } : null;

    const longText = window.__codexAppExtensionLongTextSendEnhancement || null;
    const longTextState = longText ? {
      installed: Boolean(longText.installed),
      enabled: Boolean(longText.enabled),
      lastSeenEnterEvent: longText.lastSeenEnterEvent || null,
      lastHandledEvent: longText.lastHandledEvent || null,
      lastIgnoredEvent: longText.lastIgnoredEvent || null
    } : null;

    const tabIndent = window.__codexAppExtensionTabIndentEnhancement || null;
    const tabIndentState = tabIndent ? {
      installed: Boolean(tabIndent.installed),
      enabled: Boolean(tabIndent.enabled),
      lastSeenTabEvent: tabIndent.lastSeenTabEvent || null,
      lastHandledEvent: tabIndent.lastHandledEvent || null,
      lastIgnoredEvent: tabIndent.lastIgnoredEvent || null
    } : null;

    const layoutWidthState = window.__codexAppExtensionLayoutWidth || null;
    const layoutWidthScopes = window.__codexAppExtensionLayoutWidthScopes || [];

    return {
      tool: ${JSON.stringify(APP_NAME)},
      config: meta,
      imeEnterGuardEnabled: Boolean(meta.imeEnterGuard),
      imeEnterGuardInstalled: Boolean(imeGuardState?.installed),
      imeEnterGuardState: imeGuardState,
      longTextSendEnhancementEnabled: Boolean(meta.longTextSendEnhancement),
      longTextSendEnhancementInstalled: Boolean(longTextState?.installed),
      longTextSendEnhancementState: longTextState,
      tabIndentEnhancementEnabled: Boolean(meta.tabIndentEnhancement),
      tabIndentEnhancementInstalled: Boolean(tabIndentState?.installed),
      tabIndentEnhancementState: tabIndentState,
      href: location.href,
      title: document.title,
      readyState: document.readyState,
      wideLayoutEnhancementEnabled: Boolean(meta.wideLayoutEnhancement),
      wideLayoutEnhancementDisabled: !meta.wideLayoutEnhancement,
      layoutWidthState,
      layoutWidthScopes,
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
      layoutFocusRingFixEnabled: Boolean(meta.layoutFocusRingFix),
      layoutFocusRingFixAttribute: document.documentElement.dataset.codexAppExtensionLayoutFocusRingFix || "",
      themeEnhancementEnabled: Boolean(meta.themeEnhancement),
      themeEnhancementAttribute: document.documentElement.dataset.codexAppExtensionThemeEnhancement || "",
      themeEnhancementColors: meta.themeEnhancementColors,
      themeEnhancementTypography: meta.themeEnhancementTypography,
      injectedStyleExists: Boolean(document.getElementById(${JSON.stringify(STYLE_ID)})),
      legacyStyleExists: Boolean(document.getElementById(${JSON.stringify(LEGACY_STYLE_ID)})),
      root: pick("html"),
      body: pick("body"),
      header: pick("header.app-header-tint"),
      main: pick(".main-surface"),
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
  const horizontalPadding = buildHorizontalPadding(options.horizontalGutter);
  const unifiedWidth = `min(${options.contentMaxWidth}, max(1px, calc(100vw - ${horizontalPadding})))`;
  const variables = {
    "--codex-app-extension-fullscreen-header-offset": options.fullscreenHeaderOffset,
    "--codex-app-extension-theme-ordered-list-marker": options.themeEnhancementColors.orderedListMarker,
    "--codex-app-extension-theme-unordered-list-marker": options.themeEnhancementColors.unorderedListMarker,
    "--codex-app-extension-theme-inline-code-text": options.themeEnhancementColors.inlineCodeText,
    "--codex-app-extension-theme-inline-code-background": options.themeEnhancementColors.inlineCodeBackground,
    "--codex-app-extension-theme-inline-code-border": options.themeEnhancementColors.inlineCodeBorder,
    "--codex-app-extension-theme-blockquote-border": options.themeEnhancementColors.blockquoteBorder,
    "--codex-app-extension-theme-blockquote-text": options.themeEnhancementColors.blockquoteText,
    "--codex-app-extension-theme-blockquote-background": options.themeEnhancementColors.blockquoteBackground,
    "--codex-app-extension-theme-heading-text": options.themeEnhancementColors.headingText,
    "--codex-app-extension-theme-strong-text": options.themeEnhancementColors.strongText,
  };
  if (options.wideLayoutEnhancement) {
    Object.assign(variables, {
      "--thread-content-max-width": unifiedWidth,
      "--thread-composer-max-width": unifiedWidth,
      "--markdown-wide-block-max-width": unifiedWidth,
      "--codex-app-extension-content-offset-x": "0px",
      "--codex-app-extension-horizontal-padding": horizontalPadding,
    });
  }

  return `(() => {
    const STYLE_ID = ${JSON.stringify(STYLE_ID)};
    const LEGACY_STYLE_ID = ${JSON.stringify(LEGACY_STYLE_ID)};
    const css = ${JSON.stringify(css)};
    const variables = ${JSON.stringify(variables)};
    const meta = ${JSON.stringify(meta)};
    const LAYOUT_SCOPE_SELECTORS = [
      "[data-app-shell-main-content-layout]",
      ".app-shell-main-content-viewport",
      "main.main-surface",
      ".main-surface",
      ".thread-scroll-container"
    ];
    const WIDTH_VARIABLE_CONSUMER_SELECTOR = [
      "[class*='thread-content-max-width']",
      "[class*='thread-composer-max-width']",
      "[class*='markdown-wide-block-max-width']"
    ].join(", ");
    const WIDE_LAYOUT_VARIABLE_NAMES = [
      "--thread-content-max-width",
      "--thread-composer-max-width",
      "--markdown-wide-block-max-width",
      "--codex-app-extension-content-offset-x",
      "--codex-app-extension-horizontal-padding",
      "--codex-app-extension-effective-side-padding"
    ];

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

    function uniqueElements(elements) {
      const seen = new Set();
      return elements.filter((element) => {
        if (!(element instanceof HTMLElement) || seen.has(element)) return false;
        seen.add(element);
        return true;
      });
    }

    function getRootVariableTargets() {
      return [document.documentElement, document.body].filter((target) => target instanceof HTMLElement);
    }

    function getLayoutScopeElements() {
      const elements = [];
      for (const selector of LAYOUT_SCOPE_SELECTORS) {
        elements.push(...document.querySelectorAll(selector));
      }
      return uniqueElements(elements);
    }

    function getWidthVariableConsumers() {
      return Array.from(document.querySelectorAll(WIDTH_VARIABLE_CONSUMER_SELECTOR))
        .filter((element) => element instanceof HTMLElement);
    }

    function getInlineWideLayoutVariableTargets() {
      return Array.from(document.querySelectorAll("[style]")).filter((element) => {
        if (!(element instanceof HTMLElement)) return false;
        return WIDE_LAYOUT_VARIABLE_NAMES.some((name) => element.style.getPropertyValue(name));
      });
    }

    function getVariableTargets() {
      return uniqueElements([
        ...getRootVariableTargets(),
        ...getLayoutScopeElements(),
        ...getWidthVariableConsumers(),
        ...getInlineWideLayoutVariableTargets()
      ]);
    }

    function clearWideLayoutVariables() {
      for (const target of getVariableTargets()) {
        for (const name of WIDE_LAYOUT_VARIABLE_NAMES) {
          target.style.removeProperty(name);
        }
      }
    }

    function applyStyleVariables(nextVariables, targets = getVariableTargets()) {
      for (const target of uniqueElements(targets)) {
        for (const [name, value] of Object.entries(nextVariables)) {
          if (target.style.getPropertyValue(name) !== value || target.style.getPropertyPriority(name) !== "important") {
            target.style.setProperty(name, value, "important");
          }
        }
      }
    }

    function describeLayoutElement(element, selector = "") {
      if (!(element instanceof HTMLElement)) return null;
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return {
        selector,
        tag: element.tagName.toLowerCase(),
        className: String(element.className || "").slice(0, 160),
        id: element.id || "",
        role: element.getAttribute("role") || "",
        dataTestid: element.getAttribute("data-testid") || "",
        ariaLabel: element.getAttribute("aria-label") || "",
        position: style.position,
        width: Math.round(rect.width),
        height: Math.round(rect.height),
        top: Math.round(rect.top),
        left: Math.round(rect.left),
        right: Math.round(rect.right),
        bottom: Math.round(rect.bottom)
      };
    }

    function buildLayoutReference(element, selector) {
      if (!(element instanceof HTMLElement) || !isVisibleElement(element)) return null;
      const rect = element.getBoundingClientRect();
      if (rect.width < 1) return null;
      return { element, selector, rect };
    }

    function findLayoutWidthReferences() {
      const references = [];

      for (const selector of LAYOUT_SCOPE_SELECTORS) {
        for (const element of document.querySelectorAll(selector)) {
          const reference = buildLayoutReference(element, selector);
          if (reference) references.push(reference);
        }
      }

      // 子 agent 右侧窗格可能表现为 Codex 的 absolute/floating rail，而不是常规 app-shell 容器。
      for (const reference of [...references]) {
        const rightFloatingRail = findRightFloatingRail(reference);
        if (rightFloatingRail?.element) {
          references.push({
            element: rightFloatingRail.element,
            selector: "right-floating-rail-scope",
            rect: rightFloatingRail.rect
          });
        }
      }

      const seen = new Set();
      const uniqueReferences = references.filter((reference) => {
        if (seen.has(reference.element)) return false;
        seen.add(reference.element);
        return true;
      });

      if (uniqueReferences.length) {
        return uniqueReferences.sort((a, b) => {
          if (Math.abs(a.rect.left - b.rect.left) > 2) return a.rect.left - b.rect.left;
          if (Math.abs(a.rect.top - b.rect.top) > 2) return a.rect.top - b.rect.top;
          return a.rect.width - b.rect.width;
        });
      }

      const fallback = document.body || document.documentElement;
      const reference = buildLayoutReference(fallback, fallback?.tagName?.toLowerCase?.() || "document");
      return reference ? [reference] : [];
    }

    function findRightFloatingRail(reference) {
      if (!reference?.element || !reference.rect || !document.body) return null;

      const viewportRight = window.innerWidth || reference.rect.right;
      const referenceRight = Math.min(reference.rect.right, viewportRight);
      // 右侧输出/来源面板有时是短 popover，不是整高侧栏；阈值过高会让宽 Markdown 继续压到它下面。
      const minimumFloatingPanelHeight = Math.min(160, Math.max(96, (window.innerHeight || 0) * 0.10));
      const candidates = [];

      for (const element of document.body.querySelectorAll("*")) {
        if (!(element instanceof HTMLElement)) continue;
        if (element === reference.element || element.contains(reference.element)) continue;

        const rect = element.getBoundingClientRect();
        if (rect.width < 80 || rect.height < minimumFloatingPanelHeight) continue;
        const style = getComputedStyle(element);
        if (!["absolute", "fixed", "sticky"].includes(style.position)) continue;
        if (style.display === "none" || style.visibility === "hidden") continue;
        // Codex 右侧状态面板的外壳可能禁用 pointer-events，真正可交互区域在子节点里。
        const hasInteractiveChild = style.pointerEvents === "none" && Array.from(element.querySelectorAll("*")).some((child) => {
          if (!(child instanceof HTMLElement)) return false;
          const childStyle = getComputedStyle(child);
          if (childStyle.pointerEvents === "none") return false;
          const childRect = child.getBoundingClientRect();
          return childRect.width >= 1 && childRect.height >= 1;
        });
        if (style.pointerEvents === "none" && !hasInteractiveChild) continue;

        const overlapsVertically = rect.bottom > reference.rect.top + 80
          && rect.top < reference.rect.bottom - 80;
        const startsInsideReference = rect.left > reference.rect.left + 120
          && rect.left < referenceRight - 40;
        const rightAnchored = rect.right >= referenceRight - 80
          || rect.right >= viewportRight - 80;
        const narrowEnough = rect.width <= Math.max(520, viewportRight * 0.45);

        if (!overlapsVertically || !startsInsideReference || !rightAnchored || !narrowEnough) continue;
        candidates.push({ element, rect, style });
      }

      candidates.sort((a, b) => a.rect.left - b.rect.left);
      const best = candidates[0];
      if (!best) return null;

      return {
        element: best.element,
        rect: best.rect,
        summary: describeLayoutElement(best.element, "right-floating-rail-candidate")
      };
    }

    function buildWidthExpression(availableWidth) {
      const roundedWidth = Math.max(1, Math.floor(availableWidth));
      return "min(" + meta.contentMaxWidth + ", max(1px, calc("
        + roundedWidth + "px - " + variables["--codex-app-extension-horizontal-padding"] + ")))";
    }

    function parsePixelValue(value) {
      const match = String(value || "").trim().match(/^(-?\\d+(?:\\.\\d+)?)px$/);
      if (!match) return null;
      const parsed = Number(match[1]);
      return Number.isFinite(parsed) ? parsed : null;
    }

    function resolveCssSizeToPixels(value) {
      const cssValue = String(value || "").trim();
      if (!cssValue) return null;
      const parsedPx = parsePixelValue(cssValue);
      if (parsedPx !== null) return parsedPx;

      const host = document.body || document.documentElement;
      if (!host) return null;
      const probe = document.createElement("div");
      probe.style.position = "absolute";
      probe.style.visibility = "hidden";
      probe.style.pointerEvents = "none";
      probe.style.height = "0";
      probe.style.width = cssValue;
      if (!probe.style.width) return null;

      try {
        host.appendChild(probe);
        const width = probe.getBoundingClientRect().width;
        return Number.isFinite(width) ? width : null;
      } finally {
        probe.remove();
      }
    }

    function getHorizontalPaddingPixels() {
      return resolveCssSizeToPixels(meta.horizontalPadding) ?? 0;
    }

    function computeContentOffsetState(referenceWidth, availableWidth, rightInset) {
      const horizontalPaddingPx = getHorizontalPaddingPixels();
      const horizontalGutterPx = resolveCssSizeToPixels(meta.horizontalGutter) ?? 0;
      const contentMaxWidthPx = resolveCssSizeToPixels(meta.contentMaxWidth);
      const availableContentWidthPx = Math.max(1, availableWidth - horizontalPaddingPx);
      const renderedContentWidthPx = contentMaxWidthPx == null
        ? availableContentWidthPx
        : Math.min(contentMaxWidthPx, availableContentWidthPx);
      const naturalLeftMarginPx = Math.max(0, (referenceWidth - renderedContentWidthPx) / 2);
      const requestedLeftShiftPx = rightInset > 0 ? Math.round(rightInset / 2) : 0;
      const maximumSafeLeftShiftPx = Math.max(0, Math.floor(naturalLeftMarginPx - horizontalGutterPx));
      const appliedLeftShiftPx = Math.min(requestedLeftShiftPx, maximumSafeLeftShiftPx);

      return {
        contentOffsetX: appliedLeftShiftPx > 0 ? "-" + appliedLeftShiftPx + "px" : "0px",
        requestedContentOffsetX: requestedLeftShiftPx > 0 ? "-" + requestedLeftShiftPx + "px" : "0px",
        maximumSafeContentOffsetX: maximumSafeLeftShiftPx > 0 ? "-" + maximumSafeLeftShiftPx + "px" : "0px",
        requestedLeftShiftPx,
        maximumSafeLeftShiftPx,
        appliedLeftShiftPx,
        horizontalPaddingPx,
        horizontalGutterPx,
        renderedContentWidthPx: Math.round(renderedContentWidthPx),
        naturalLeftMarginPx: Math.round(naturalLeftMarginPx)
      };
    }

    function parseTransformTranslateX(transform) {
      if (!transform || transform === "none") return 0;
      const matrix = transform.match(/^matrix\\(([^)]+)\\)$/);
      if (matrix) {
        const values = matrix[1].split(",").map((item) => Number(item.trim()));
        return Number.isFinite(values[4]) ? values[4] : 0;
      }
      const matrix3d = transform.match(/^matrix3d\\(([^)]+)\\)$/);
      if (matrix3d) {
        const values = matrix3d[1].split(",").map((item) => Number(item.trim()));
        return Number.isFinite(values[12]) ? values[12] : 0;
      }
      return 0;
    }

    function findNativeContentLayerShift(reference) {
      if (!reference?.element) return null;
      const containers = Array.from(reference.element.querySelectorAll("[class]")).filter((element) => {
        if (!(element instanceof HTMLElement) || !isVisibleElement(element)) return false;
        const className = String(element.className || "");
        return className.includes("max-w-(--thread-content-max-width)")
          || className.includes("max-w-[var(--thread-content-max-width)]")
          || className.includes("max-w-[var(--thread-composer-max-width)]");
      });

      for (const container of containers) {
        for (let element = container.parentElement; element && element !== reference.element; element = element.parentElement) {
          if (!(element instanceof HTMLElement)) continue;
          const transform = getComputedStyle(element).transform;
          const shiftPx = parseTransformTranslateX(transform);
          if (Math.abs(shiftPx) < 1) continue;
          return {
            shiftPx: Math.round(shiftPx),
            summary: describeLayoutElement(element, "native-content-layer-shift")
          };
        }
      }

      return null;
    }

    function compensateNativeContentShift(contentOffsetState, nativeContentShift) {
      const nativeLeftShiftPx = nativeContentShift?.shiftPx < 0 ? Math.abs(nativeContentShift.shiftPx) : 0;
      const adjustedLeftShiftPx = Math.max(0, contentOffsetState.appliedLeftShiftPx - nativeLeftShiftPx);
      return {
        ...contentOffsetState,
        contentOffsetX: adjustedLeftShiftPx > 0 ? "-" + adjustedLeftShiftPx + "px" : "0px",
        appliedLeftShiftPx: adjustedLeftShiftPx,
        nativeContentShiftPx: nativeContentShift?.shiftPx || 0,
        nativeContentShift: nativeContentShift?.summary || null
      };
    }

    function computeLayoutWidthScopeState(reference) {
      const fallbackWidth = variables["--thread-content-max-width"];
      const horizontalPadding = variables["--codex-app-extension-horizontal-padding"];
      if (!reference) {
        return {
          reason: "no-layout-reference",
          width: fallbackWidth,
          fallbackWidth,
          horizontalPadding,
          horizontalGutter: meta.horizontalGutter,
          contentOffsetX: "0px",
          reference: null,
          rightFloatingRail: null
        };
      }

      // Codex 新版右侧悬浮栏可能覆盖主区域；先按真实主聊天容器收敛，再避让右侧悬浮栏。
      const viewportRight = window.innerWidth || reference.rect.right;
      const referenceRight = Math.min(reference.rect.right, viewportRight);
      const rightFloatingRail = findRightFloatingRail(reference);
      // 部分滚动容器在左侧栏之后仍保留 viewport 宽度，右边界需先夹到可视区内。
      const rightBoundary = rightFloatingRail
        ? Math.min(referenceRight, rightFloatingRail.rect.left)
        : referenceRight;
      const availableWidth = Math.max(1, Math.floor(rightBoundary - reference.rect.left));
      const rightInset = Math.max(0, Math.floor(referenceRight - rightBoundary));
      const referenceWidth = Math.max(1, referenceRight - reference.rect.left);
      // 内容容器仍由 Codex 的 mx-auto 居中；左移时必须保留最小左侧 gutter，避免临界宽度下被父级裁剪。
      const contentOffsetState = compensateNativeContentShift(
        computeContentOffsetState(referenceWidth, availableWidth, rightInset),
        findNativeContentLayerShift(reference)
      );

      return {
        reason: rightFloatingRail ? "layout-reference-with-right-floating-rail" : "layout-reference",
        width: buildWidthExpression(availableWidth),
        fallbackWidth,
        availableWidth,
        rightInset,
        referenceWidth: Math.round(referenceWidth),
        ...contentOffsetState,
        horizontalPadding,
        horizontalGutter: meta.horizontalGutter,
        reference: describeLayoutElement(reference.element, reference.selector),
        rightFloatingRail: rightFloatingRail?.summary || null
      };
    }

    function computeLayoutWidthStates() {
      const references = findLayoutWidthReferences();
      const scopedStates = references.map((reference) => ({
        element: reference.element,
        state: computeLayoutWidthScopeState(reference)
      }));
      const scopes = scopedStates.map((scope) => scope.state);
      return {
        primary: scopes[0] || computeLayoutWidthScopeState(null),
        scopedStates,
        scopes
      };
    }

    function applyVariables() {
      if (!meta.wideLayoutEnhancement) {
        clearWideLayoutVariables();
        applyStyleVariables(variables, getRootVariableTargets());
        const disabledState = {
          reason: "wide-layout-enhancement-disabled",
          disabled: true,
          width: null,
          fallbackWidth: null,
          horizontalPadding: null,
          horizontalGutter: meta.horizontalGutter,
          contentOffsetX: "0px",
          reference: null,
          rightFloatingRail: null
        };
        window.__codexAppExtensionLayoutWidth = disabledState;
        window.__codexAppExtensionLayoutWidthScopes = [];
        return disabledState;
      }

      const layoutWidthStates = computeLayoutWidthStates();
      const rootState = layoutWidthStates.primary;
      const rootVariables = {
        ...variables,
        "--thread-content-max-width": rootState.width,
        "--thread-composer-max-width": rootState.width,
        "--markdown-wide-block-max-width": rootState.width,
        "--codex-app-extension-content-offset-x": rootState.contentOffsetX
      };
      clearWideLayoutVariables();
      // 底部输入框等固定层不一定在主内容 scope 内，根节点必须保留主区域避让状态；右侧子 agent 再用局部变量覆盖。
      applyStyleVariables(rootVariables, getRootVariableTargets());
      for (const scope of layoutWidthStates.scopedStates) {
        const scopeState = scope.state;
        if (!scope.element || !scopeState.reference) continue;
        applyStyleVariables({
          ...variables,
          "--thread-content-max-width": scopeState.width,
          "--thread-composer-max-width": scopeState.width,
          "--markdown-wide-block-max-width": scopeState.width,
          "--codex-app-extension-content-offset-x": scopeState.contentOffsetX
        }, [scope.element]);
      }
      window.__codexAppExtensionLayoutWidth = layoutWidthStates.primary;
      window.__codexAppExtensionLayoutWidthScopes = layoutWidthStates.scopes;
      return layoutWidthStates.primary;
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

    function applyThemeEnhancementState() {
      const enabled = Boolean(meta.themeEnhancement);
      document.documentElement.dataset.codexAppExtensionThemeEnhancement = enabled ? "true" : "false";
      return enabled;
    }

    function applyLayoutFocusRingFixState() {
      const enabled = Boolean(meta.layoutFocusRingFix);
      document.documentElement.dataset.codexAppExtensionLayoutFocusRingFix = enabled ? "true" : "false";
      return enabled;
    }

    function runLayoutRefresh() {
      upsertStyle();
      applyVariables();
      applyFullscreenState();
      applyLayoutFocusRingFixState();
      applyThemeEnhancementState();
    }

    function scheduleLayoutRefresh() {
      const previous = window.__codexAppExtensionLayoutRefresh;
      if (previous?.frame) cancelAnimationFrame(previous.frame);
      for (const timer of previous?.timers || []) clearTimeout(timer);

      const state = {
        frame: 0,
        timers: [],
        scheduledAt: Date.now(),
        lastRunAt: previous?.lastRunAt || 0,
        runCount: previous?.runCount || 0
      };

      const refresh = () => {
        runLayoutRefresh();
        state.lastRunAt = Date.now();
        state.runCount += 1;
      };

      state.frame = requestAnimationFrame(() => {
        state.frame = 0;
        refresh();
        for (const delay of [50, 150, 300, 600]) {
          state.timers.push(setTimeout(refresh, delay));
        }
      });
      window.__codexAppExtensionLayoutRefresh = state;
    }

    function installResizeListener() {
      window.__codexAppExtensionApplyFullscreenState = applyFullscreenState;
      const previousResizeHandler = window.__codexAppExtensionResizeHandler;
      if (previousResizeHandler) {
        window.removeEventListener("resize", previousResizeHandler);
        window.visualViewport?.removeEventListener("resize", previousResizeHandler);
      }

      window.__codexAppExtensionResizeHandler = () => scheduleLayoutRefresh();
      window.addEventListener("resize", window.__codexAppExtensionResizeHandler, { passive: true });
      window.visualViewport?.addEventListener("resize", window.__codexAppExtensionResizeHandler, { passive: true });
    }

    function installLayoutResizeObserver() {
      if (window.__codexAppExtensionResizeObserver) {
        try {
          window.__codexAppExtensionResizeObserver.observer.disconnect();
        } catch {
          // Ignore stale observer cleanup failures.
        }
      }
      if (typeof ResizeObserver !== "function") return;

      const observed = new WeakSet();
      const observer = new ResizeObserver(() => scheduleLayoutRefresh());
      const observeTargets = () => {
        const targets = [
          document.documentElement,
          document.body,
          ...document.querySelectorAll(".main-surface, .app-shell-main-content-viewport, [data-app-shell-main-content-layout], .thread-scroll-container")
        ].filter((target) => target instanceof Element);

        for (const target of targets) {
          if (observed.has(target)) continue;
          observed.add(target);
          observer.observe(target);
        }
      };

      observeTargets();
      window.__codexAppExtensionResizeObserver = { observer, observeTargets };
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
          window.__codexAppExtensionResizeObserver?.observeTargets?.();
          scheduleLayoutRefresh();
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

    function isTabKey(event) {
      return event.key === "Tab"
        || event.code === "Tab"
        || event.keyCode === 9;
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

    function isNativeRequestInputPanelEditable(editable) {
      return getLongTextManagedInput(editable)?.kind === "request-input-panel-textarea";
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

    function insertTextareaTab(textarea) {
      if (!(textarea instanceof HTMLTextAreaElement)) return false;
      textarea.focus();

      const start = Number.isInteger(textarea.selectionStart) ? textarea.selectionStart : textarea.value.length;
      const end = Number.isInteger(textarea.selectionEnd) ? textarea.selectionEnd : start;
      const nextValue = textarea.value.slice(0, start) + "\\t" + textarea.value.slice(end);
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
          inputType: "insertText",
          data: "\\t"
        })
        : new Event("input", { bubbles: true, cancelable: true });
      textarea.dispatchEvent(inputEvent);
      return true;
    }

    function insertContentEditableTab(editable) {
      if (!(editable instanceof HTMLElement)) return false;
      editable.focus();

      if (document.queryCommandSupported?.("insertText") && document.execCommand("insertText", false, "\\t")) {
        return true;
      }
      if (document.queryCommandSupported?.("insertHTML") && document.execCommand("insertHTML", false, "&#9;")) {
        return true;
      }
      return false;
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
        lastSkippedEvent: null,
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
        const activeCompositionEnter = Boolean(event.isComposing)
          || event.keyCode === 229
          || (targetComposing && !recentCompositionEnd);
        const graceCompositionEnter = !activeCompositionEnter && recentCompositionEnd;
        const imeManagedKey = activeCompositionEnter || graceCompositionEnter;
        const enterLike = event.key === "Enter"
          || event.code === "Enter"
          || event.code === "NumpadEnter"
          || event.keyCode === 13;

        state.lastKeydownEvent = {
          time: now,
          key: event.key,
          code: event.code,
          keyCode: event.keyCode,
          isComposing: Boolean(event.isComposing),
          enterLike,
          imeManagedKey,
          activeCompositionEnter,
          graceCompositionEnter,
          recentCompositionEnd,
          targetComposing,
          blocked: false,
          target: describeImeTarget(editable)
        };

        if (!enterLike || !imeManagedKey) return;

        if (isNativeRequestInputPanelEditable(editable) && graceCompositionEnter) {
          // 原生选择框在组合刚结束后的普通 Enter 仍应走 Codex 原生提交，避免 textarea 默认换行。
          state.lastKeydownEvent.skipped = true;
          state.lastKeydownEvent.skipReason = "native-request-input-panel-after-composition";
          state.lastSkippedEvent = state.lastKeydownEvent;
          return;
        }

        event.stopImmediatePropagation();
        state.lastKeydownEvent.blocked = true;
        state.lastKeydownEvent.blockReason = isNativeRequestInputPanelEditable(editable)
          ? "native-request-input-panel-active-composition"
          : (activeCompositionEnter ? "active-composition" : "recent-composition-end");
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

    function installTabIndentEnhancement() {
      const existing = window.__codexAppExtensionTabIndentEnhancement;
      if (existing?.handlers?.keydown) {
        window.removeEventListener("keydown", existing.handlers.keydown, true);
        document.removeEventListener("keydown", existing.handlers.keydown, true);
      }

      const state = {
        enabled: Boolean(meta.tabIndentEnhancement),
        installed: false,
        lastSeenTabEvent: null,
        lastHandledEvent: null,
        lastIgnoredEvent: null,
        handlers: null
      };
      window.__codexAppExtensionTabIndentEnhancement = state;

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
        action: "",
        handled: false,
        target: describeImeTarget(editable),
        inputKind: managedInput?.kind || null,
        managedRoot: describeImeTarget(managedInput?.root || null),
        ...extra
      });

      const ignoreTab = (event, editable, managedInput, reason) => {
        state.lastIgnoredEvent = buildEventInfo(event, editable, managedInput, {
          action: "ignore",
          reason
        });
      };

      const keydown = (event) => {
        if (!isTabKey(event)) return;

        const editable = getEditableElement(event.target);
        const managedInput = getLongTextManagedInput(editable);
        state.lastSeenTabEvent = buildEventInfo(event, editable, managedInput);
        if (!managedInput) {
          ignoreTab(event, editable, managedInput, "not-composer");
          return;
        }

        const plainTab = !event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey;
        if (!plainTab) {
          ignoreTab(event, editable, managedInput, "unsupported-modifier");
          return;
        }

        // Tab 是系统焦点导航键，只在已识别的 Codex 输入框内接管，避免破坏全局键盘导航。
        event.preventDefault();
        event.stopImmediatePropagation();

        const eventInfo = buildEventInfo(event, editable, managedInput);
        eventInfo.action = "insert-tab";
        eventInfo.insertedTab = managedInput.kind === "request-input-panel-textarea"
          ? insertTextareaTab(editable)
          : insertContentEditableTab(editable);
        eventInfo.handled = true;
        if (!eventInfo.insertedTab) {
          eventInfo.action = "insert-tab-failed";
          eventInfo.reason = "insert-command-failed";
        }
        state.lastHandledEvent = eventInfo;
      };

      state.handlers = { keydown };
      window.addEventListener("keydown", keydown, true);
      document.addEventListener("keydown", keydown, true);
      state.installed = true;
      return state;
    }

    function install() {
      cleanupLegacyWideLayout();
      upsertStyle();
      const layoutWidthState = applyVariables();
      const fullscreen = applyFullscreenState();
      const layoutFocusRingFix = applyLayoutFocusRingFixState();
      const themeEnhancement = applyThemeEnhancementState();
      installResizeListener();
      installLayoutResizeObserver();
      const imeGuard = installImeEnterGuard();
      const longTextSend = installLongTextSendEnhancement();
      const tabIndent = installTabIndentEnhancement();

      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => {
          cleanupLegacyWideLayout();
          upsertStyle();
          applyVariables();
          applyFullscreenState();
          applyLayoutFocusRingFixState();
          applyThemeEnhancementState();
          installLayoutResizeObserver();
          installImeEnterGuard();
          installLongTextSendEnhancement();
          installTabIndentEnhancement();
          installObserver();
        }, { once: true });
      } else {
        installObserver();
      }

      const computedTarget = document.body || document.documentElement;
      const main = document.querySelector(".main-surface");
      return {
        tool: ${JSON.stringify(APP_NAME)},
        styleId: STYLE_ID,
        config: meta,
        detectedFullscreen: fullscreen,
        fullscreenAttribute: document.documentElement.dataset.codexAppExtensionFullscreen || "",
        bodyThreadContentMaxWidth: getComputedStyle(computedTarget).getPropertyValue("--thread-content-max-width").trim(),
        bodyComposerMaxWidth: getComputedStyle(computedTarget).getPropertyValue("--thread-composer-max-width").trim(),
        bodyMarkdownWideBlockMaxWidth: getComputedStyle(computedTarget).getPropertyValue("--markdown-wide-block-max-width").trim(),
        layoutWidthState: window.__codexAppExtensionLayoutWidth || layoutWidthState,
        layoutWidthScopes: window.__codexAppExtensionLayoutWidthScopes || [],
        mainPaddingTop: main ? getComputedStyle(main).paddingTop : null,
        layoutFocusRingFixEnabled: Boolean(meta.layoutFocusRingFix),
        layoutFocusRingFixInstalled: layoutFocusRingFix,
        themeEnhancementEnabled: Boolean(meta.themeEnhancement),
        themeEnhancementInstalled: themeEnhancement,
        themeEnhancementColors: meta.themeEnhancementColors,
        themeEnhancementTypography: meta.themeEnhancementTypography,
        imeEnterGuardEnabled: Boolean(meta.imeEnterGuard),
        imeEnterGuardInstalled: Boolean(imeGuard?.installed),
        longTextSendEnhancementEnabled: Boolean(meta.longTextSendEnhancement),
        longTextSendEnhancementInstalled: Boolean(longTextSend?.installed),
        tabIndentEnhancementEnabled: Boolean(meta.tabIndentEnhancement),
        tabIndentEnhancementInstalled: Boolean(tabIndent?.installed)
      };
    }

    return install();
  })();`;
}

function buildMeta(options) {
  const horizontalPadding = buildHorizontalPadding(options.horizontalGutter);
  return {
    configPath: options.configPath,
    configCreated: options.configCreated,
    wideLayoutEnhancement: options.wideLayoutEnhancement,
    contentMaxWidth: options.contentMaxWidth,
    horizontalGutter: options.horizontalGutter,
    horizontalPadding,
    fullscreenHeaderOffset: options.fullscreenHeaderOffset,
    imeEnterGuard: options.imeEnterGuard,
    longTextSendEnhancement: options.longTextSendEnhancement,
    tabIndentEnhancement: options.tabIndentEnhancement,
    layoutFocusRingFix: options.layoutFocusRingFix,
    themeEnhancement: options.themeEnhancement,
    themeEnhancementColors: options.themeEnhancementColors,
    themeEnhancementTypography: options.themeEnhancementTypography,
  };
}

function buildCss(options) {
  const horizontalPadding = buildHorizontalPadding(options.horizontalGutter);
  const width = `min(${options.contentMaxWidth}, max(1px, calc(100vw - ${horizontalPadding})))`;
  const wideLayoutRootVariables = options.wideLayoutEnhancement ? `
  --thread-content-max-width: ${width} !important;
  --thread-composer-max-width: ${width} !important;
  --markdown-wide-block-max-width: ${width} !important;
  --codex-app-extension-content-offset-x: 0px !important;
  --codex-app-extension-horizontal-padding: ${horizontalPadding} !important;` : "";
  const wideLayoutCss = options.wideLayoutEnhancement ? `

.max-w-\\(--thread-content-max-width\\),
.max-w-\\[var\\(--thread-content-max-width\\)\\] {
  max-width: var(--thread-content-max-width) !important;
  translate: var(--codex-app-extension-content-offset-x) 0 !important;
}

.max-w-\\[var\\(--thread-composer-max-width\\)\\] {
  max-width: var(--thread-composer-max-width) !important;
  translate: var(--codex-app-extension-content-offset-x) 0 !important;
}

.max-w-\\[var\\(--markdown-wide-block-max-width\\)\\],
.max-w-\\[min\\(90vw\\,var\\(--markdown-wide-block-max-width\\)\\)\\] {
  max-width: var(--markdown-wide-block-max-width) !important;
}

.w-\\[min\\(100\\%\\,var\\(--thread-content-max-width\\)\\)\\] {
  width: min(100%, var(--thread-content-max-width)) !important;
}
` : "";
  const strongTypographyCss = [
    options.themeEnhancementTypography.strongFontWeight
      ? `  font-weight: ${options.themeEnhancementTypography.strongFontWeight} !important;`
      : "",
    options.themeEnhancementTypography.strongFontSize
      ? `  font-size: ${options.themeEnhancementTypography.strongFontSize} !important;`
      : "",
  ].filter(Boolean).join("\n");

  return `
body[data-codex-window-type="electron"],
.main-surface,
.app-shell-main-content-viewport,
[data-app-shell-main-content-layout] {
${wideLayoutRootVariables}
  --codex-app-extension-fullscreen-header-offset: ${options.fullscreenHeaderOffset} !important;
  --codex-app-extension-theme-ordered-list-marker: ${options.themeEnhancementColors.orderedListMarker} !important;
  --codex-app-extension-theme-unordered-list-marker: ${options.themeEnhancementColors.unorderedListMarker} !important;
  --codex-app-extension-theme-inline-code-text: ${options.themeEnhancementColors.inlineCodeText} !important;
  --codex-app-extension-theme-inline-code-background: ${options.themeEnhancementColors.inlineCodeBackground} !important;
  --codex-app-extension-theme-inline-code-border: ${options.themeEnhancementColors.inlineCodeBorder} !important;
  --codex-app-extension-theme-blockquote-border: ${options.themeEnhancementColors.blockquoteBorder} !important;
  --codex-app-extension-theme-blockquote-text: ${options.themeEnhancementColors.blockquoteText} !important;
  --codex-app-extension-theme-blockquote-background: ${options.themeEnhancementColors.blockquoteBackground} !important;
  --codex-app-extension-theme-heading-text: ${options.themeEnhancementColors.headingText} !important;
  --codex-app-extension-theme-strong-text: ${options.themeEnhancementColors.strongText} !important;
}
${wideLayoutCss}

:where(main.main-surface, .main-surface) {
  box-sizing: border-box !important;
  padding-top: var(--codex-app-extension-fullscreen-header-offset) !important;
}

/* Only suppress accidental focus chrome on top-level layout shells; real controls keep their focus styles. */
html[data-codex-app-extension-layout-focus-ring-fix="true"] :where(
  main.main-surface,
  .main-surface,
  .app-shell-main-content-viewport,
  [data-app-shell-main-content-layout],
  .thread-scroll-container
):is(:focus, :focus-visible) {
  outline: none !important;
  box-shadow: none !important;
}

html[data-codex-app-extension-layout-focus-ring-fix="true"] :where(
  main.main-surface,
  .main-surface,
  .app-shell-main-content-viewport,
  [data-app-shell-main-content-layout],
  .thread-scroll-container
):focus-within {
  outline: none !important;
}

/* Theme enhancement is intentionally scoped to Markdown-like tags in the main surface. */
html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(ol) > li::marker {
  color: var(--codex-app-extension-theme-ordered-list-marker) !important;
  font-weight: 700 !important;
}

html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(ul) > li::marker {
  color: var(--codex-app-extension-theme-unordered-list-marker) !important;
  font-weight: 700 !important;
}

html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(.inline-markdown),
html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(p, li, blockquote, td, th, h1, h2, h3, h4, h5, h6) > code {
  color: var(--codex-app-extension-theme-inline-code-text) !important;
  background: var(--codex-app-extension-theme-inline-code-background) !important;
  border: 1px solid var(--codex-app-extension-theme-inline-code-border) !important;
  border-radius: 6px !important;
  padding: 0.08em 0.36em !important;
}

html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(pre, pre *) code {
  color: inherit !important;
  background: transparent !important;
  border: 0 !important;
  padding: 0 !important;
}

html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(blockquote) {
  color: var(--codex-app-extension-theme-blockquote-text) !important;
  background: var(--codex-app-extension-theme-blockquote-background) !important;
  border-left: 3px solid var(--codex-app-extension-theme-blockquote-border) !important;
  border-radius: 0 6px 6px 0 !important;
  margin-inline: 0 !important;
  padding: 0.65em 0.9em !important;
}

html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(h1, h2, h3, h4, h5, h6) {
  color: var(--codex-app-extension-theme-heading-text) !important;
}

html[data-codex-app-extension-theme-enhancement="true"] main.main-surface :where(strong) {
  color: var(--codex-app-extension-theme-strong-text) !important;
${strongTypographyCss ? `${strongTypographyCss}\n` : ""}
}

`.trim();
}

main().catch((error) => {
  console.error(`[${APP_NAME}] ${error.message}`);
  process.exit(1);
});
