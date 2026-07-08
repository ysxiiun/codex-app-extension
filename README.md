# codex-app-extension

`codex-app-extension` 是一个面向 Codex App 的本地增强扩展工具。

它的目标不是替代 Codex App，也不是修改应用包体，而是在运行时为 Codex App 补充一些更贴近实际工作流的体验增强。当前版本主要解决宽屏空间利用、顶部标题遮挡、中文输入法回车误发送、长文本发送体验、Tab 制表符输入等问题；后续也可以继续承载更多 Codex App 的增强注入能力。

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
- 提供诊断输出，便于确认注入是否生效、配置是否读取正确、IME 防护是否安装。

## 工作方式

本工具不会直接修改 Codex App 的安装文件、应用包体、账号数据或历史会话数据。

它的基本流程是：

1. 使用带远程调试端口的方式启动 Codex App。
2. 等待正在运行的 Codex App 页面完成注册。
3. 注入运行时样式和事件防护逻辑。
4. 根据配置文件、环境变量或 CLI 参数决定增强行为。

因此，如果注入后想恢复默认体验，只需要退出当前 Codex App 实例，再用普通方式重新打开 Codex App。

## 使用方式

建议先完全退出正在运行的 Codex App，然后执行：

```bash
<repo>/launch.sh
```

其中 `<repo>` 是本项目所在目录。

如果 Codex App 打开后没有生效，通常是 Electron 将启动参数路由到了已有窗口。完全退出 Codex App 后，再重新运行上面的命令即可。

启动后，工具会默认等待最多 30 秒，直到 Codex App 主页面可以被调试端口发现，再执行注入。这个等待时间可以通过 `CODEX_APP_EXTENSION_TARGET_TIMEOUT_MS` 或 `--target-timeout-ms` 临时调整。

## 配置修改后重新生效

如果当前 Codex App 已经通过本工具启动并暴露了远程调试端口，修改 `~/.codex-app-extension/config.json` 后，可以直接重新注入当前运行实例：

```bash
<repo>/inject-current.sh
```

这个脚本不会启动新的 Codex App。它会优先使用 `--port`、`CODEX_APP_EXTENSION_PORT` 或 `CODEX_WIDE_PORT`，否则自动从当前正在监听的 Codex 进程中发现调试端口，并调用 `inject-wide-layout.mjs` 让配置重新生效。

也可以直接用它查看当前实例诊断信息：

```bash
<repo>/inject-current.sh --diagnose
```

如果脚本提示没有找到运行中的调试端口，说明当前 Codex App 不是通过远程调试端口启动的；请先完全退出 Codex App，再用 `<repo>/launch.sh` 启动。

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
    "blockquoteText": "rgba(252, 252, 252, 0.78)",
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
- `themeEnhancementColors`：主题增强色板。当前默认值适配 Codex App 的 `codex` dark 主题；如果使用其他主题，需要根据实际背景色、正文色和代码主题自行调整这些颜色。

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
| `blockquoteText` | 引用块内部正文颜色 |
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

## 诊断

如果想确认当前注入状态，可以运行：

```bash
node <repo>/inject-wide-layout.mjs --port 9229 --diagnose
```

重点关注：

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
- `longTextSendEnhancementState.*.inputKind`：最近一次 Enter 命中的输入类型，例如 `prosemirror-composer` 或 `request-input-panel-textarea`。
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

本项目是 Codex App 的本地增强工具，不是 Codex App 官方功能的一部分。Codex App 自身升级后，页面结构可能变化；如果增强能力失效，可以先使用诊断命令确认注入状态，再根据新的页面结构适配注入逻辑。

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
