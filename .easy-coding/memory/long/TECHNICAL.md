---
memory_schema: 2
memory_file: TECHNICAL
last_updated: 2026-08-03
---

# 长期技术记忆

## 有效记忆

### 运行时注入架构

- 使用运行时注入而非修改 Codex App 包体，保持本地增强可撤销，降低升级和数据风险。
- 技术栈以 Node.js ESM + Chrome DevTools Protocol 为核心，适合在不改应用包体的前提下向 Electron 页面注入运行时增强。
- Bash 启动脚本负责本机启动、端口探测和注入脚本编排，保持依赖轻量。

### 配置化增强链路

- 配置读取优先级固定为：内置默认值 < 配置文件 < 环境变量 < CLI 参数。
- 新增影响阅读、输入或页面布局的能力时，内置默认值应保守，并接入配置文件、环境变量、CLI 参数和诊断输出。
- 新增运行时增强能力应尽量暴露到 `--diagnose`，便于确认配置是否启用、运行时是否安装、最近事件状态是否符合预期。

### 当前实例重注入流程

- `inject-current.sh` 用于配置修改后快速生效，不启动新的 Codex App，只对当前运行实例执行重注入。
- 端口选择顺序为：`--port`、`CODEX_APP_EXTENSION_PORT` / `CODEX_WIDE_PORT`、`lsof` 发现的 Codex 监听端口、默认 `9229`。
- 端口发现只作为候选来源，最终以 `http://127.0.0.1:{port}/json/version` 校验远程调试端口是否可用。
- 配置或注入脚本变更后，常用验证链路是 `node --check inject-wide-layout.mjs`、相关 Bash `bash -n`、`git diff --check`，再按条件执行 `./inject-current.sh` 和 `./inject-current.sh --diagnose`。
- `./inject-current.sh --diagnose` 是只读诊断，不会安装最新脚本；验证注入改动必须先运行 `./inject-current.sh`，再执行 diagnose 或 CDP computed-style 探针。

### ChatGPT Codex 运行时兼容

- 应用显示名、安装路径、可执行进程名、Node 内置路径、CDP target 和页面 DOM 协议是相互独立的兼容边界，升级时必须分别验证，不能只替换应用路径字符串。
- 应用发现优先显式 `CODEX_APP`、`ChatGPT.app`、`Codex.app`，候选最终都必须通过 bundle id `com.openai.codex` 校验；Node 最终要求同时支持原生 `fetch` 和 `WebSocket`。
- debugger target 只能做候选评分，写入页面前仍须用布局根、工作区锚点和交互锚点组成 Codex surface 签名；运行时 CSS、布局变量和输入事件统一受 `data-codex-app-extension-surface="true"` 约束。
- 新版 request input 以 `data-codex-composer-request-navigation` 为容器，dismiss/skip 不是提交动作；无法唯一识别提交按钮时必须失败开放给原生页面。

### 布局刷新与原生区域隔离

- `window.resize` 可即时刷新；ResizeObserver/MutationObserver 触发的布局变化应合并为短延迟刷新，并设置收尾刷新覆盖动画结束状态。不要在每轮刷新时先全量清空再写回宽屏变量，只清理已经失效的目标，避免 style mutation 反馈和侧栏动画抖动。
- `thread-floating-content` 等持久右侧面板既是主内容避让的测量输入，又不应成为独立宽屏 scope；原生浮层子树需要局部重置宽度和横向偏移，避免 Git/Diff 或环境组件被继承变量压窄、错位。
- 左侧栏不是主会话内容区，应隔离 thread/composer/Markdown 宽度、内容横向偏移和 padding 变量。项目行若使用 `overflow-x:hidden`，需显式控制 `overflow-y`，并警惕透明的静态尾部操作区提前占用标题宽度。
- 排查视觉错位时先区分持久 rail、composer 附着组件、瞬态 menu/listbox 和普通侧栏内容，再用 diagnose/computed style 验证真实 DOM；不要用通用 absolute/fixed/sticky 启发式把所有浮层写成同一种 scope。

### Markdown 主题兼容

- 引用块正文默认用 CSS `inherit` 跟随原生主题正文色，避免为浅色/深色维护平行主题识别；用户配置仍可覆盖固定色。
- 嵌套 blockquote 只复位背景、左边框、圆角、横向间距和 padding，不重写正文色，让颜色继续继承；顶层引用块的背景和边框合同保持独立。
- 生成 CSS 回归应验证最终 selector、特异性与完整声明块；只检查源码字符串或配置值不足以证明页面元素实际命中规则。

### 运行实例安全启动

- `launch.sh` 的状态机固定为：优先复用通过回环 `/json/version` 终检的现有 CDP；应用运行但无 CDP 时进入显式交互确认；主进程未运行时正常调试启动。
- 强制重启只接受原始输入恰为 `Y/y`，并仅对 Info.plist 的 `CFBundleExecutable` 做精确进程操作；取消、非交互、端口/身份/进程探测异常必须在 `pkill` 或 `open` 前失败安全。
- 安全敏感的 plist 标量不能直接依赖 Shell 命令替换读取：先写入权限受控的临时文件，检查原始 NUL、单行控制字符、选项形名称和 macOS 短进程名边界，再用于 `pgrep -x` / `pkill -KILL -x`。
- 破坏性启动链应通过替换 TTY、输入和底层系统命令进行无真实副作用的函数级/启动级回归；失败用例同时断言未调用进程终止、应用启动或注入器。

### 输入与布局增强边界

- `layoutFocusRingFix` 用运行时 CSS 修复顶层布局容器误触焦点框，不应影响输入框、按钮、菜单、链接等真实控件的焦点样式。
- IME guard 的 Enter 判断应收紧为真实 Enter 信号，避免把 `keyCode=229` 普通组合键单独当作 Enter。
- `tabIndentEnhancement` 内置默认关闭；本机可通过配置文件开启。只在识别到 Codex 主输入框或 Plan 回复框时接管普通 Tab，保留 `Shift+Tab`、带修饰键 Tab 与非输入区 Tab 的原生行为。
- 新增输入行为应复用现有输入框识别和事件增强框架，避免创建平行注入路径。

### 配置脚本维护模式

- `inject-wide-layout.mjs --configure` 负责交互式配置流程，复用现有 `DEFAULT_CONFIG`、校验函数和 JSON 写入路径，避免默认配置重复维护。
- `config.sh` 只做入口包装，不复制配置逻辑。
- 配置模式应补齐旧配置缺少的新字段并保留未知字段；非 TTY 输入需能兼容管道测试。
- 复杂主题配置只补齐结构并提示用户编辑 JSON，避免在交互脚本中维护大量颜色和排版细节。

## 已淘汰记录

| 淘汰日期 | 原内容摘要 | 淘汰原因 | 替代内容或来源 |
|---|---|---|---|
| 暂无 | 暂无 | 暂无 | 暂无 |
