# codex-app-extension

`codex-app-extension` 是一个面向 Codex App 的本地增强扩展工具。

它的目标不是替代 Codex App，也不是修改应用包体，而是在运行时为 Codex App 补充一些更贴近实际工作流的体验增强。当前版本主要解决宽屏空间利用、macOS 全屏遮挡、中文输入法回车误发送、长文本发送体验等问题；后续也可以继续承载更多 Codex App 的增强注入能力。

## 为什么需要它

Codex App 在默认布局下更偏向居中窄内容区。对于大屏、外接显示器、长代码块、长 Markdown 回复和频繁审阅改动的场景，这会带来几个明显问题：

- 屏幕空间没有被充分利用，正文和输入框仍集中在中间一小段区域。
- 宽 Markdown、代码块、文件变更摘要容易被压窄，可读性下降。
- macOS 全屏时，顶部标题区域在某些窗口尺寸下可能覆盖对话内容。
- Plan 模式下，中文输入法在组合输入时按 Enter，可能被误识别为发送消息。

`codex-app-extension` 通过运行时注入的方式处理这些体验问题。它是可撤销的：正常方式重新打开 Codex App，就会回到官方默认行为。

## 当前版本支持的能力

- 扩展对话正文、输入框、宽 Markdown 和代码块的最大可用宽度。
- 支持通过配置调整内容最大宽度，默认最大宽度为 `1800px`。
- 在 macOS 全屏场景下为顶部标题区域预留空间，避免内容和对话标题重叠。
- 为 Plan 模式提供中文输入法 Enter 防护，避免组合输入中的回车误发送半截消息。
- 可选开启“长文本发送增强”：在 Codex 输入框和 Plan 回复框中统一使用 Enter 换行、Cmd+Enter 发送。
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

## 配置

配置文件位置：

```text
~/.codex-app-extension/config.json
```

第一次运行注入脚本时，如果配置文件不存在，会自动生成默认配置：

```json
{
  "contentMaxWidth": "1800px",
  "fullscreenHeaderOffset": "46px",
  "imeEnterGuard": true,
  "longTextSendEnhancement": false
}
```

字段说明：

- `contentMaxWidth`：正文、输入框、宽 Markdown、代码块的统一最大宽度。
- `fullscreenHeaderOffset`：macOS 全屏时给顶部标题区域预留的高度。
- `imeEnterGuard`：是否启用中文输入法 Enter 防误发送。
- `longTextSendEnhancement`：是否启用“长文本发送增强”，默认关闭；开启后 Codex 输入框和 Plan 回复框中 Enter 换行、Cmd+Enter 发送。

配置读取优先级：

```text
内置默认值 < 配置文件 < 环境变量 < CLI 参数
```

## 临时覆盖配置

通过环境变量临时调整宽度和全屏顶部预留：

```bash
CODEX_APP_EXTENSION_CONTENT_MAX_WIDTH=1600px \
CODEX_APP_EXTENSION_FULLSCREEN_HEADER_OFFSET=50px \
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

也可以直接调用注入脚本：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --content-max-width 1600px \
  --fullscreen-header-offset 50px
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

也可以用 CLI 临时开启或关闭“长文本发送增强”：

```bash
node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --enable-long-text-send-enhancement

node <repo>/inject-wide-layout.mjs \
  --port 9229 \
  --disable-long-text-send-enhancement
```

## 诊断

如果想确认当前注入状态，可以运行：

```bash
node <repo>/inject-wide-layout.mjs --port 9229 --diagnose
```

重点关注：

- `config.contentMaxWidth`：当前生效的内容最大宽度。
- `threadMaxWidth.width`：实际正文容器宽度。
- `detectedFullscreen`：当前是否识别为全屏。
- `main.paddingTop`：全屏顶部避让是否生效。
- `imeEnterGuardEnabled` / `imeEnterGuardInstalled`：中文输入法 Enter 防护是否启用并安装。
- `imeEnterGuardState.lastBlockedEvent`：最近一次被防护逻辑拦截的 IME Enter 事件。
- `longTextSendEnhancementEnabled` / `longTextSendEnhancementInstalled`：长文本发送增强是否启用并安装。
- `longTextSendEnhancementState.lastSeenEnterEvent`：最近一次被增强逻辑看到的 Enter 事件。
- `longTextSendEnhancementState.lastHandledEvent`：最近一次被增强逻辑处理的 Enter 事件。
- `longTextSendEnhancementState.lastIgnoredEvent`：最近一次未接管的 Enter 事件，`reason` 会说明原因。
- `longTextSendEnhancementState.*.inputKind`：最近一次 Enter 命中的输入类型，例如 `prosemirror-composer` 或 `request-input-panel-textarea`。

## 兼容说明

本项目是 Codex App 的本地增强工具，不是 Codex App 官方功能的一部分。Codex App 自身升级后，页面结构可能变化；如果增强能力失效，可以先使用诊断命令确认注入状态，再根据新的页面结构适配注入逻辑。

保留的旧兼容入口包括：

- `CODEX_WIDE_PORT`
- `CODEX_WIDE_THREAD_MAX`
- `CODEX_WIDE_COMPOSER_MAX`
- `CODEX_WIDE_MARKDOWN_MAX`
- `CODEX_WIDE_SIDE_PADDING`
- `--thread-max`
- `--composer-max`
- `--markdown-max`

旧的三个宽度入口现在都会映射到统一的 `contentMaxWidth`。
