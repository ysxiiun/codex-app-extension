# codex-app-extension

`codex-app-extension` 是一个面向 ChatGPT 中 Codex 工作区的本地增强扩展工具，同时兼容旧版独立 Codex App。

2026 年新版桌面端的应用名和安装路径已经变为 `ChatGPT.app`，但仍使用 Codex bundle id `com.openai.codex`。本工具会优先识别新版 ChatGPT Codex，再回退兼容 `/Applications/Codex.app`。它不会替代官方应用或修改应用包体，而是在确认当前页面是 Codex 工作区后，运行时补充宽屏空间利用、顶部标题避让、中文输入法回车防误发送、长文本发送和 Tab 制表符输入等能力。

## 为什么需要它

Codex App 在默认布局下更偏向居中窄内容区。对于大屏、外接显示器、长代码块、长 Markdown 回复和频繁审阅改动的场景，这会带来几个明显问题：

- 屏幕空间没有被充分利用，正文和输入框仍集中在中间一小段区域。
- 宽 Markdown、代码块、文件变更摘要容易被压窄，可读性下降。
- 顶部标题区域在某些窗口尺寸下可能覆盖对话内容。
- Plan 模式下，中文输入法在组合输入时按 Enter，可能被误识别为发送消息。

`codex-app-extension` 通过运行时注入的方式处理这些体验问题。它是可撤销的：正常方式重新打开 Codex App，就会回到官方默认行为。

## 当前版本支持的能力

- 扩展对话正文、输入框、宽 Markdown 和代码块的最大可用宽度。
- 支持通过配置调整内容最大宽度，默认最大宽度为 `1800px`。
- Codex App 右侧出现悬浮栏、主聊天区变窄或子 agent 右侧工作区时，会按每个可见工作区的实际可用区域独立收敛，并按 `horizontalGutter` 保留横向留白。
- 在窗口模式和全屏模式下为顶部标题区域预留空间，避免内容和对话标题重叠。
- 为 Plan 模式提供中文输入法 Enter 防护，避免组合输入中的回车误发送半截消息。
- 可选开启“长文本发送增强”：在 Codex 输入框和 Plan 回复框中统一使用 Enter 换行、Cmd+Enter 发送。
- 可选开启“Tab 制表符增强”：在 Codex 输入框和 Plan 回复框中按 Tab 写入制表符。
- 默认启用“布局焦点环修复”：隐藏主布局容器误触发的蓝色焦点框，但保留输入框、按钮等真实控件的焦点样式。
- 可选开启“Markdown 主题增强”：为标题、列表、行内代码、引用等 Markdown 元素补充结构色。
- 可选择跟随作者推荐配置，拉取最新代码后自动使用仓库中的作者偏好。
- 提供交互式配置脚本，可补齐旧配置文件中缺失的新增配置项。
- 自动发现 `ChatGPT.app` / `Codex.app`、兼容 Node.js 和对应的 ChatGPT/Codex 调试进程。
- 注入前校验 Codex 工作区 DOM 签名；切换到非 Codex 页面时，样式和输入接管自动失效。
- 兼容新版 request input 的 `data-codex-composer-request-navigation` / `data-request-input-*` 协议，同时保留旧类名回退。
- 提供诊断与自动验证脚本，便于确认注入、表面签名、配置和输入协议是否正确。

## 工作方式

本工具不会直接修改 ChatGPT/Codex 的安装文件、应用包体、账号数据或历史会话数据。

它的基本流程是：

1. 识别 `CODEX_APP` 指定路径，或自动发现 `ChatGPT.app` / `Codex.app`。
2. 使用仅监听 `127.0.0.1` 的远程调试端口启动应用。
3. 等待可附加页面，并确认页面包含 Codex 工作区表面签名。
4. 注入受 Codex 表面开关约束的样式和事件防护逻辑。
5. 根据配置文件、环境变量或 CLI 参数决定增强行为。

因此，如果注入后想恢复默认体验，只需要退出当前 ChatGPT/Codex 实例，再用普通方式重新打开应用。

## 使用方式

建议先完全退出正在运行的 ChatGPT（或旧 Codex App），然后执行：

```bash
<repo>/launch.sh
```

其中 `<repo>` 是本项目所在目录。

脚本按“显式 `CODEX_APP` > `ChatGPT.app` > `Codex.app`”选择应用，并自动寻找同时提供原生 `fetch` 与 `WebSocket` 的 Node.js。如果应用打开后没有生效，通常是 Electron 将启动参数路由到了已有窗口。完全退出 ChatGPT/Codex 后，再重新运行上面的命令即可。

启动后，工具会默认等待最多 30 秒，直到 Codex 工作区可以被调试端口发现，再执行注入。这个等待时间可以通过 `CODEX_APP_EXTENSION_TARGET_TIMEOUT_MS` 或 `--target-timeout-ms` 临时调整。

## 配置修改后重新生效

如果当前 ChatGPT/Codex 已经通过本工具启动并暴露了远程调试端口，修改 `~/.codex-app-extension/config.json` 后，可以直接重新注入当前运行实例：

```bash
<repo>/inject-current.sh
```

这个脚本不会启动新的应用。它会优先使用 `--port`、`CODEX_APP_EXTENSION_PORT` 或 `CODEX_WIDE_PORT`，否则自动从当前正在监听的 ChatGPT/Codex 进程中发现调试端口，并调用 `inject-wide-layout.mjs` 让配置重新生效。

也可以直接用它查看当前实例诊断信息：

```bash
<repo>/inject-current.sh --diagnose
```

如果脚本提示没有找到运行中的调试端口，说明当前 ChatGPT/Codex 不是通过远程调试端口启动的。远程调试端口不能补加到已运行进程；请先完全退出应用，再用 `<repo>/launch.sh` 启动。

## 配置

配置文件位置：

```text
~/.codex-app-extension/config.json
```

首次运行 `<repo>/launch.sh` 且本地没有配置文件时，脚本会先进入初始化流程：

1. `follow author config`：使用仓库中的作者推荐配置。
2. `自定义配置`：逐项生成自己的本地配置。

如果希望直接跟随作者推荐配置，也可以手动运行：

```bash
<repo>/follow-author-config.sh
```

确认后脚本会把当前配置备份到 `~/.codex-app-extension/config.json.bak`，再把 `~/.codex-app-extension/config.json` 软链接到 `<repo>/data/author-config.json`。之后拉取项目最新代码时，作者配置也会随仓库更新。

可以运行配置脚本逐项确认常用开关和配置值：

```bash
<repo>/config.sh
```

脚本会读取当前配置文件，显示每一项当前值，直接按 Enter 会保留当前值；对布尔开关可以输入 `y` / `n`、`true` / `false`、`on` / `off` 或 `1` / `0` 切换。运行完成后，配置文件会补齐当前版本支持的全量配置项。如果当前配置是作者配置软链接，重新运行 `config.sh` 会解除软链接并写入普通本地配置文件，不会修改仓库中的 `data/author-config.json`。

主题增强、标题色增强和加粗可读性增强的配色属于复杂配置，`config.sh` 只会补齐 `themeEnhancementColors`、`headingTextEnhancementStyle` 与 `strongTextEnhancementStyle` 的完整结构，不会逐个颜色交互修改。开启对应增强后，如需调整行内代码、引用块、标题或加粗文字样式，请直接编辑配置文件中的对应对象。

配置脚本只更新本地 JSON 配置，不会启动 Codex App，也不会执行注入。若 Codex App 已经通过本工具启动，配置保存后可以运行：

```bash
<repo>/inject-current.sh
```

让新配置重新注入当前实例。

默认自定义配置内容如下：

```json
{
  "wideLayoutEnhancement": true,
  "contentMaxWidth": "1800px",
  "horizontalGutter": "20px",
  "fullscreenHeaderOffset": "46px",
  "imeEnterGuard": true,
  "longTextSendEnhancement": false,
  "tabIndentEnhancement": false,
  "layoutFocusRingFix": true,
  "headingTextEnhancement": false,
  "headingTextEnhancementStyle": {
    "color": "#F2C94C"
  },
  "strongTextEnhancement": false,
  "strongTextEnhancementStyle": {
    "color": "#F2C94C",
    "fontWeight": "800"
  },
  "themeEnhancement": false,
  "themeEnhancementColors": {
    "inlineCodeText": "#df3079",
    "inlineCodeBackground": "rgba(223, 48, 121, 0.10)",
    "inlineCodeBorder": "rgba(223, 48, 121, 0.18)",
    "blockquoteBorder": "#df3079",
    "blockquoteText": "inherit",
    "blockquoteBackground": "rgba(223, 48, 121, 0.06)"
  }
}
```

字段说明：

- `wideLayoutEnhancement`：是否启用“宽屏增强”，默认开启；关闭后不再增强会话宽度，也不再做横向留白控制和右侧浮层避让。
- `contentMaxWidth`：正文、输入框、宽 Markdown、代码块的最大宽度；同一工作区内保持统一，不同工作区会按自身可用区域独立收敛；仅在 `wideLayoutEnhancement=true` 时生效。
- `horizontalGutter`：横向留白，默认 `20px`；仅在 `wideLayoutEnhancement=true` 时生效，表示内容区域左右两边各自至少保留这个宽度。
- `fullscreenHeaderOffset`：给顶部标题区域预留的高度，窗口模式和全屏模式都会生效。
- `imeEnterGuard`：是否启用中文输入法 Enter 防误发送。
- `longTextSendEnhancement`：是否启用“长文本发送增强”，默认关闭；开启后 Codex 输入框和 Plan 回复框中 Enter 换行、Cmd+Enter 发送。
- `tabIndentEnhancement`：是否启用“Tab 制表符增强”，默认关闭；开启后 Codex 输入框和 Plan 回复框中按 Tab 写入制表符。
- `layoutFocusRingFix`：是否启用“布局焦点环修复”，默认开启；开启后仅隐藏主布局容器误触发的焦点框，不影响输入框、按钮、菜单和链接的焦点提示。
- `headingTextEnhancement`：是否启用“Markdown 标题颜色增强”，默认关闭；开启后只增强 Markdown 标题 `h1` 到 `h6`，不影响应用标题或按钮。
- `headingTextEnhancementStyle`：标题颜色增强样式，默认将 Markdown 标题设为 `#F2C94C`。
- `strongTextEnhancement`：是否启用“Markdown 加粗可读性增强”，默认关闭；开启后只增强正文、列表、表格和引用块里的 `strong`，不影响标题或按钮。
- `strongTextEnhancementStyle`：加粗可读性增强样式，默认将加粗文字设为 `#F2C94C` 和 `800` 字重。
- `themeEnhancement`：是否启用“Markdown 主题增强”，默认关闭；开启后为行内代码和引用块补充结构色。
- `themeEnhancementColors`：主题增强色板。其中引用块正文颜色默认 `inherit`，会继承当前主题的原生正文色，浅色/深色主题都能自动适配、无需按主题单独调整；其余色板颜色仍以 Codex App 的 `codex` dark 主题为基准，如果使用其他主题，需要根据实际背景色和代码主题自行调整。

`headingTextEnhancementStyle` 字段说明：

| 字段 | 影响内容 |
|---|---|
| `color` | Markdown 标题文字颜色，例如 `#` / `##` / `###` |

`strongTextEnhancementStyle` 字段说明：

| 字段 | 影响内容 |
|---|---|
| `color` | Markdown 正文区域里的加粗文字颜色，例如 `**重点**` |
| `fontWeight` | Markdown 正文区域里的加粗文字字重，例如 `"800"` |

`themeEnhancementColors` 字段说明：

| 字段 | 影响内容 |
|---|---|
| `inlineCodeText` | 行内代码文字颜色，例如 `` `appName` `` |
| `inlineCodeBackground` | 行内代码背景色，不影响代码块 |
| `inlineCodeBorder` | 行内代码边框色，不影响代码块 |
| `blockquoteBorder` | 引用块左侧边框，例如 `> 引用内容` |
| `blockquoteText` | 引用块内部正文颜色，默认 `inherit`（继承当前主题的正文色，浅/深色自动适配）|
| `blockquoteBackground` | 引用块整块背景色 |

配置读取优先级：

```text
内置默认值 < 配置文件 < 环境变量 < CLI 参数
```

## 临时覆盖配置

通过环境变量临时调整宽度、横向留白和顶部预留：

```bash
CODEX_APP_EXTENSION_CONTENT_MAX_WIDTH=1600px \
CODEX_APP_EXTENSION_HORIZONTAL_GUTTER=20px \
CODEX_APP_EXTENSION_FULLSCREEN_HEADER_OFFSET=50px \
<repo>/launch.sh
```

宽度增强会优先按 Codex 主聊天区域的实际宽度计算；如果配置的最大宽度超过当前可用区域，会自动收敛，并在左右两侧分别保留 `horizontalGutter` 指定的横向留白。

临时关闭“宽屏增强”：

```bash
CODEX_APP_EXTENSION_WIDE_LAYOUT_ENHANCEMENT=false \
<repo>/launch.sh
```

临时关闭中文输入法 Enter 防护：

```bash
CODEX_APP_EXTENSION_IME_ENTER_GUARD=false \
<repo>/launch.sh
```

临时开启“长文本发送增强”：

```bash
CODEX_APP_EXTENSION_LONG_TEXT_SEND_ENHANCEMENT=true \
<repo>/launch.sh
```

临时开启“Tab 制表符增强”：

```bash
CODEX_APP_EXTENSION_TAB_INDENT_ENHANCEMENT=true \
<repo>/launch.sh
```

临时关闭“布局焦点环修复”：

```bash
CODEX_APP_EXTENSION_LAYOUT_FOCUS_RING_FIX=false \
<repo>/launch.sh
```

临时开启“Markdown 主题增强”：

```bash
CODEX_APP_EXTENSION_THEME_ENHANCEMENT=true \
<repo>/launch.sh
```

也可以直接调用注入脚本：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --content-max-width 1600px \
  --horizontal-gutter 20px \
  --fullscreen-header-offset 50px
```

也可以用 CLI 临时开启或关闭“宽屏增强”：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --enable-wide-layout-enhancement

node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-wide-layout-enhancement
```

如果 Codex App 启动较慢，可以加长等待主页面的时间：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --target-timeout-ms 60000
```

或用 CLI 临时关闭 IME 防护：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-ime-enter-guard
```

也可以用 CLI 临时开启或关闭“布局焦点环修复”：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --enable-layout-focus-ring-fix

node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-layout-focus-ring-fix
```

也可以用 CLI 临时开启或关闭“长文本发送增强”：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --enable-long-text-send-enhancement

node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-long-text-send-enhancement
```

也可以用 CLI 临时开启或关闭“Tab 制表符增强”：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --enable-tab-indent-enhancement

node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-tab-indent-enhancement
```

也可以用 CLI 临时开启或关闭“Markdown 主题增强”：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --enable-theme-enhancement

node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-theme-enhancement
```

## 自动验证

修改代码或桌面应用升级后，可以先运行不改动 ChatGPT/Codex 状态的验证：

```bash
<repo>/verify.sh
```

它会检查 Shell 与 Node.js 语法、应用 bundle id、Node 运行时能力、生成后的注入代码、target 防误选、Codex 表面保护、新版 request input 锚点和 Git 空白错误。默认不会重启应用，也不会连接当前页面。

如果 ChatGPT/Codex 已通过 `<repo>/launch.sh` 暴露调试端口，还可以追加只读的在线诊断：

```bash
CODEX_APP_EXTENSION_VERIFY_LIVE=1 <repo>/verify.sh
```

## 诊断

如果想确认当前注入状态，可以运行：

```bash
node <repo>/inject-wide-layout.mjs --port 9229 --diagnose
```

重点关注：

- `surfaceSupported` / `surfaceProfile`：当前 target 是否被识别为受支持的 Codex 工作区。
- `surfaceCompatibility`：表面签名的缺失项、各类稳定锚点数量、页面状态和 request input 协议。
- `requestInputProtocol`：当前检测到的是新版 `chatgpt-codex-data-attributes`、旧版 `legacy-classes`，还是暂未出现动态 request input。
- `requestInputCandidates`：当前可见 request input 的位置和实际识别协议。
- `layoutVariableConsumerCount`：当前页面中消费 Codex 宽度变量的节点数量。
- `config.wideLayoutEnhancement`：宽屏增强是否启用。
- `config.contentMaxWidth`：当前生效的内容最大宽度。
- `config.horizontalGutter` / `config.horizontalPadding`：动态宽度适配时保留的单侧横向留白 / 左右合计留白。
- `wideLayoutEnhancementEnabled` / `wideLayoutEnhancementDisabled`：当前运行实例中的宽屏增强状态。
- `layoutWidthState`：当前主宽屏变量的计算来源，用于兼容旧诊断阅读习惯。
- `layoutWidthScopes`：各可见工作区的独立宽度计算结果，包括参考容器、可用宽度、有效留白、最终宽度表达式和右侧悬浮栏候选。
- `nativeFloatingCandidates`：当前页面中疑似 Codex 原生浮层的候选元素，例如 composer 上方浮层、右侧环境/来源面板、git/diff 摘要；用于排查升级后原生浮层被宽屏增强压窄或错位的问题。
- `nativeFloatingResetTargets`：当前已被宽屏增强隔离的 Codex 原生浮层；这些目标会在自身子树内重置宽屏变量和横向偏移，避免原生组件被增强样式裁剪。
- `leftSidebar`：当前左侧栏容器的布局、overflow 和宽屏变量继承状态，用于确认主内容宽屏变量是否泄漏到侧栏。
- `sidebarProjectRows`：左侧栏项目行的行容器、标题元素和尾部操作区尺寸，用于排查项目名过早截断或每行出现浅灰滚动条的问题。
- `threadMaxWidth.width`：实际正文容器宽度。
- `detectedFullscreen`：当前是否识别为全屏。
- `main.paddingTop`：顶部避让是否生效。
- `imeEnterGuardEnabled` / `imeEnterGuardInstalled`：中文输入法 Enter 防护是否启用并安装。
- `imeEnterGuardState.lastBlockedEvent`：最近一次被防护逻辑拦截的 IME Enter 事件，`blockReason` 会区分原生选择框组合态与普通组合态。
- `imeEnterGuardState.lastSkippedEvent`：最近一次被防护逻辑识别但主动让给 Codex 原生处理的 IME Enter 事件，例如原生选择框组合结束后的普通提交。
- `longTextSendEnhancementEnabled` / `longTextSendEnhancementInstalled`：长文本发送增强是否启用并安装。
- `longTextSendEnhancementState.lastSeenEnterEvent`：最近一次被增强逻辑看到的 Enter 事件。
- `longTextSendEnhancementState.lastHandledEvent`：最近一次被增强逻辑处理的 Enter 事件。
- `longTextSendEnhancementState.lastIgnoredEvent`：最近一次未接管的 Enter 事件，`reason` 会说明原因。
- `longTextSendEnhancementState.*.inputKind` / `inputProtocol`：最近一次 Enter 命中的输入类型及适配协议，例如 `prosemirror-composer` 或采用新版数据属性协议的 `request-input-panel-textarea`。
- `tabIndentEnhancementEnabled` / `tabIndentEnhancementInstalled`：Tab 制表符增强是否启用并安装。
- `tabIndentEnhancementState.lastSeenTabEvent`：最近一次被增强逻辑看到的 Tab 事件。
- `tabIndentEnhancementState.lastHandledEvent`：最近一次被增强逻辑处理的 Tab 事件。
- `tabIndentEnhancementState.lastIgnoredEvent`：最近一次未接管的 Tab 事件，`reason` 会说明原因。
- `layoutFocusRingFixEnabled` / `layoutFocusRingFixAttribute`：布局焦点环修复是否启用，以及页面根节点上的启用状态。
- `headingTextEnhancementEnabled` / `headingTextEnhancementAttribute`：Markdown 标题颜色增强是否启用，以及页面根节点上的启用状态。
- `headingTextEnhancementStyle`：当前生效的标题颜色增强样式。
- `strongTextEnhancementEnabled` / `strongTextEnhancementAttribute`：Markdown 加粗可读性增强是否启用，以及页面根节点上的启用状态。
- `strongTextEnhancementStyle`：当前生效的加粗可读性增强样式。
- `themeEnhancementEnabled` / `themeEnhancementAttribute`：Markdown 主题增强是否启用，以及页面根节点上的启用状态。
- `themeEnhancementColors`：当前生效的主题增强色板。

## 兼容说明

本项目是 ChatGPT Codex 的本地增强工具，不是官方功能的一部分。桌面应用自身升级后，页面结构可能变化；如果增强能力失效，可以先运行 `<repo>/verify.sh`，再使用诊断命令确认当前表面签名和输入协议。

新版应用兼容策略：

- 应用路径优先识别 `/Applications/ChatGPT.app`，同时继续兼容 `/Applications/Codex.app`；两者通过 bundle id `com.openai.codex` 确认身份。
- `CODEX_APP` 仍可显式覆盖应用路径；`NODE_BIN` 仍可显式覆盖 Node.js，但运行时必须同时提供 `fetch` 和 `WebSocket`。
- 调试端口只绑定到 `127.0.0.1`，`inject-current.sh` 同时发现 `ChatGPT` 与 `Codex` 进程名。
- debugger target 只做候选评分，最终必须通过 Codex DOM 表面签名；不再向任意首个页面注入。
- 所有增强 CSS 与输入事件接管都受 `data-codex-app-extension-surface="true"` 约束，离开 Codex 工作区后会清理已写入的宽度变量并让原生页面接管。
- 新版 request input 以 `data-codex-composer-request-navigation` 为容器，以 `data-request-input-dismiss` / `data-request-input-skip` 排除非提交按钮；旧 `request-input-panel` / `inline-freeform` 类名继续作为回退。

Codex 新版本可能会把环境信息、来源、git/diff 摘要等原生组件放入 `thread-floating-content` 或 composer 上方的浮层。宽屏增强会继续用这些浮层测量主区域需要避让的右侧空间，但不会把它们作为独立宽屏 scope 写入 `--thread-content-max-width` / `--thread-composer-max-width`；同时会在这些原生浮层子树内重置宽屏变量和横向偏移，避免原生 git/diff 组件在输入框上方被压窄、错位或残留。

左侧栏不属于主会话内容区。宽屏增强会在 `app-shell-left-panel` 内隔离主内容宽度变量和横向偏移，并修正项目行的纵向 overflow 与尾部操作区占位，避免项目名称被提前压缩或每行出现浅灰滚动条。

保留的旧兼容入口包括：

- `CODEX_WIDE_PORT`
- `CODEX_WIDE_THREAD_MAX`
- `CODEX_WIDE_COMPOSER_MAX`
- `CODEX_WIDE_MARKDOWN_MAX`
- `--thread-max`
- `--composer-max`
- `--markdown-max`

旧的三个宽度入口现在都会映射到统一的 `contentMaxWidth`。
