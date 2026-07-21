# codex-app-extension 架构摘要

> 最后更新：2026-07-20；由 ec-init 基于当前入口、配置、README 和验证脚本生成。

## 项目定位

`codex-app-extension` 是运行在 macOS 上的 ChatGPT Codex 本地增强工具，并兼容旧版独立 Codex App。它不修改官方应用包体，而是启动一个只监听回环地址的 Electron CDP 端口，在确认页面属于 Codex 工作区后注入 CSS 与事件处理逻辑。

项目无 `package.json`、第三方运行时依赖或构建产物；核心由一个 Node.js ESM 注入器、若干 Bash 入口、JSON 配置和零依赖验证脚本组成。

## 核心数据流

1. `launch.sh` 调用 `lib/runtime.sh` 解析应用、兼容 Node 和精确主进程名；优先复用通过 `/json/version` 验证的现有 CDP 端口，否则按主进程的运行、未运行或探测错误状态，分别确认强制重启、正常调试启动或失败安全退出。
2. `inject-wide-layout.mjs` 读取 `~/.codex-app-extension/config.json`，按“默认值 < 配置文件 < 环境变量 < CLI”合并最终选项。
3. 注入器轮询 `/json/list`，给 page/webview target 评分，再通过布局根、工作区和交互锚点校验 Codex surface。
4. CDP `Runtime.evaluate` 安装受 surface 属性约束的 CSS、布局 observer、IME guard、长文本发送与 Tab 事件逻辑。
5. `--diagnose` 只读返回 surface、宽度 scope、原生浮层、侧栏、输入协议和最近事件；`verify.sh` 在无在线端口时验证生成代码与当前 app 静态锚点。

## 模块：运行时发现（`lib/runtime.sh`）

- 读取 app `Info.plist` 并以 bundle id `com.openai.codex` 识别 ChatGPT/Codex 应用；显式路径与自动发现候选执行相同终检。
- 应用优先级：显式 `CODEX_APP`、系统/用户 `ChatGPT.app`、系统/用户 `Codex.app`；优先级不绕过 bundle id 校验。
- 从选中 app 的 `Info.plist` 读取 `CFBundleExecutable` 作为精确主进程名；以 `pgrep -x` 区分运行、未运行和探测错误三态。
- `Info.plist` 的 bundle id 与 `CFBundleExecutable` 原始输出先写入权限固定为 `0600` 的精确临时文件，在进入 Bash 变量前由 `od` 检测 NUL，再执行精确单行与控制字符校验，最后删除该临时文件。
- 用户明确确认后仅以 `pkill -KILL -x` 强制终止该精确主进程，并在有界轮询内确认进程已经退出。
- Node 优先级：显式 `NODE_BIN`、PATH、选中应用内置 `cua_node/bin/node`、旧 `Resources/node`；最终要求原生 `fetch` 与 `WebSocket`。
- 使用 `lsof` 同时发现 `ChatGPT` 与 `Codex` 进程的监听端口；所有候选端口仍须通过回环地址 HTTP `/json/version` 终检。

## 模块：启动与当前实例（`launch.sh`、`inject-current.sh`）

- `launch.sh` 负责首次配置分流、最长约 30 秒端口等待和首次注入，并按三条路径运行：发现可用 `/json/version` 端口时直接注入；主进程运行但无可用 CDP 时确认后强制重启；主进程未运行时正常启动调试实例。
- 配置的启动端口必须是 `1..65535` 的十进制 TCP 端口；无效值会在 CDP 发现、进程探测、交互确认、强制终止或打开/重启应用之前输出 stderr 并以非零状态退出，因此不能终止当前实例。
- 只有交互终端中明确输入 `Y` 或 `y` 才会立即强制终止精确主进程；取消、确认读取失败、非交互环境或主进程探测错误都失败安全，不执行终止或重启。
- `inject-current.sh` 不启动应用；它按 CLI、环境变量、进程发现、默认 `9229` 的顺序选择端口，用于重新注入或只读诊断。

## 模块：核心注入（`inject-wide-layout.mjs`）

- Node 侧负责 CLI、配置校验、CDP target 发现、WebSocket 请求响应和页面源码生成。
- 页面侧负责样式注入、宽度 scope 计算、右侧 floating rail 避让、原生 git/diff 浮层隔离、左侧栏隔离和全屏状态。
- surface 双门禁先阻止选错 target，再用 `data-codex-app-extension-surface="true"` 约束 CSS 与输入事件；路由离开 Codex 时清理扩展写入的宽屏变量。
- 输入适配识别 ProseMirror composer，以及新版 `data-codex-composer-request-navigation` / 旧类名 request input；提交按钮歧义时让原生行为继续。
- 配置、安装结果和 `--diagnose` 使用 JSON 可序列化数据跨越 Node/CDP 页面边界。

## 模块：配置（`config.sh`、`follow-author-config.sh`、`data/author-config.json`）

- 本地配置位于 `~/.codex-app-extension/config.json`；`config.sh` 调用注入器的 `--configure`，不复制配置 schema。
- `follow-author-config.sh` 备份现有配置后，把本地配置软链接到仓库作者配置；用户可随 git 更新同步作者偏好。
- `DEFAULT_CONFIG` 是支持字段与默认值的代码来源；作者配置只保存具体偏好，未知本地字段在配置补齐时保留。

## 模块：验证（`verify.sh`）

- 作为项目唯一可执行测试基线，运行 Bash/Node 语法检查、生成后 diagnose/installer 源编译和 CSS surface 作用域断言。
- 以隔离的启动状态机回归覆盖可用 CDP 直注入、运行中确认重启、未运行正常启动、取消与非交互失败安全，并校验 `Y`/`y` 解析、精确 `pgrep -x`/`pkill -KILL -x` 参数和进程探测错误路径。
- 覆盖 target 不误选、surface 支持与拒绝、新 request input 锚点、当前 app bundle/Node 能力和 `app.asar` 稳定锚点。
- 默认不重启或连接当前页面；设置 `CODEX_APP_EXTENSION_VERIFY_LIVE=1` 后追加 `inject-current.sh --diagnose`。

## 模块：文档与预览（`README.md`、`strong-text-color-preview.html`）

- README 是安装、启动、配置、环境变量、CLI、验证和诊断字段的用户契约。
- `strong-text-color-preview.html` 是独立人工配色预览，不参与注入器运行时或自动验证。

## 技术栈与版本证据

- JavaScript：Node.js ESM；初始化环境验证 PATH Node `v22.16.0` 与 ChatGPT 内置 Node `v24.14.0`。
- Shell：macOS GNU Bash `3.2.57` 兼容语法。
- 协议：Chrome DevTools Protocol HTTP discovery + WebSocket RPC。
- 页面技术：运行时 CSS、DOM API、MutationObserver、ResizeObserver、composition/keyboard events。
- 数据：JSON 配置、YAML harness profile、Markdown 项目知识。

## 外部依赖与服务

- 运行目标：`ChatGPT.app` / `Codex.app`，显式路径与自动发现候选都要求 bundle id `com.openai.codex`。
- 本机命令：`open`、`curl`、`lsof`、`pgrep`、`pkill`、`mktemp`、`od`、`/bin/cat`、`rm`、`/usr/libexec/PlistBuddy`、`sed`、`awk`；`rg` 仅为验证锚点的优先实现，缺失时回退 `grep`。
- 本地服务：`http://127.0.0.1:{port}/json/version`、`/json/list` 与对应 debugger WebSocket；不监听外部网卡。
- 无 npm 依赖、数据库、后端 API 或部署服务。

## 构建、运行与验证命令

- 构建：无。
- 首次/重启注入：`./launch.sh`。
- 配置：`./config.sh` 或 `./follow-author-config.sh`。
- 当前实例重注入：`./inject-current.sh`。
- 当前实例诊断：`./inject-current.sh --diagnose`。
- 自动验证：`./verify.sh`。
- 在线只读验证：`CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh`。

## 架构约束

- 运行时增强必须可关闭、可诊断、可撤销，不修改应用包体和用户数据。
- 破坏性重启必须经过显式交互确认，只能精确匹配 app 声明的主进程；确认取消、非交互环境和进程探测异常均须失败安全。
- 保留旧应用路径、环境变量、CLI alias 和输入选择器，除非用户明确授权破坏性清理。
- 没有 CDP 端口时只能完成静态/生成代码验证，不得把它表述为在线注入验收。
