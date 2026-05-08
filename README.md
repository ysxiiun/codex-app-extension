# codex-app-extension

`codex-app-extension` 是一个可撤销的本地小工具，用运行时 CSS 扩展 Codex App 的对话宽度，修复 macOS 全屏时顶部标题栏覆盖内容的问题，并规避 Plan 模式下中文输入法 Enter 误发送。

它不会修改 `/Applications/Codex.app`、`app.asar`、账号数据或会话数据。

## 使用

如果 Codex 已经打开，建议先完全退出 Codex，然后运行：

```bash
/Users/ysxiiun/Documents/ysx/myProject/codex-app-extension/launch.sh
```

如果 Codex 打开后没有生效，通常是 Electron 把启动参数路由到了已有窗口。完全退出 Codex 后重新执行上面的命令即可。

## 配置

配置文件固定为：

```text
~/.codex-app-extension/config.json
```

第一次运行注入脚本时，如果文件不存在，会自动生成：

```json
{
  "contentMaxWidth": "1800px",
  "fullscreenHeaderOffset": "46px",
  "imeEnterGuard": true
}
```

字段含义：

- `contentMaxWidth`：正文、输入框、宽 Markdown/代码块的统一最大宽度。
- `fullscreenHeaderOffset`：macOS 全屏时给顶部标题栏预留的高度，避免对话内容和对话名重叠。
- `imeEnterGuard`：是否拦截中文输入法组合态里的 Enter，避免 Plan 模式误发送半截消息。

读取优先级：

```text
内置默认值 < ~/.codex-app-extension/config.json < 环境变量 < CLI 参数
```

## 临时覆盖

推荐的新参数：

```bash
CODEX_APP_EXTENSION_CONTENT_MAX_WIDTH=1600px \
CODEX_APP_EXTENSION_FULLSCREEN_HEADER_OFFSET=50px \
/Users/ysxiiun/Documents/ysx/myProject/codex-app-extension/launch.sh
```

临时关闭中文输入法 Enter 防护：

```bash
CODEX_APP_EXTENSION_IME_ENTER_GUARD=false \
/Users/ysxiiun/Documents/ysx/myProject/codex-app-extension/launch.sh
```

也可以直接调用注入脚本：

```bash
node /Users/ysxiiun/Documents/ysx/myProject/codex-app-extension/inject-wide-layout.mjs \
  --port 9229 \
  --content-max-width 1600px \
  --fullscreen-header-offset 50px
```

或用 CLI 关闭 IME 防护：

```bash
node /Users/ysxiiun/Documents/ysx/myProject/codex-app-extension/inject-wide-layout.mjs \
  --port 9229 \
  --disable-ime-enter-guard
```

保留的旧兼容入口：

- `CODEX_WIDE_PORT`
- `CODEX_WIDE_THREAD_MAX`
- `CODEX_WIDE_COMPOSER_MAX`
- `CODEX_WIDE_MARKDOWN_MAX`
- `CODEX_WIDE_SIDE_PADDING`
- `--thread-max`
- `--composer-max`
- `--markdown-max`

旧的三个宽度入口现在都会映射到统一的 `contentMaxWidth`。

## 诊断

```bash
node /Users/ysxiiun/Documents/ysx/myProject/codex-app-extension/inject-wide-layout.mjs --port 9229 --diagnose
```

重点看：

- `config.contentMaxWidth`：当前读取到的配置宽度。
- `threadMaxWidth.width`：实际正文容器宽度，默认不应超过约 `1800px`。
- `detectedFullscreen`：当前窗口是否被识别为全屏。
- `main.paddingTop`：全屏时应接近 `fullscreenHeaderOffset`，普通窗口应为 `0px`。
- `imeEnterGuardEnabled` / `imeEnterGuardInstalled`：IME Enter 防护是否启用并安装。
- `imeEnterGuardState.lastBlockedEvent`：最近一次被拦截的 IME Enter 事件。

## 恢复默认布局

退出这个 Codex 实例，然后从 Dock、Spotlight 或 Finder 正常打开 Codex。因为本工具只做运行时注入，普通启动会恢复官方默认布局。
