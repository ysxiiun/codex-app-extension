# codex-app-extension 编码规则

> 由 ec-init 根据 `inject-wide-layout.mjs`、Shell 入口、配置和验证脚本提取；规则必须可机械检查。

## General

- 项目无 `package.json`、构建系统、依赖管理器、formatter 或 linter；不得为单个增强引入这些设施，除非用户明确确认架构变更。
- 修改前用 `file -I` 核对编码并保持原编码：当前 `inject-wide-layout.mjs`、`launch.sh`、`lib/runtime.sh`、Markdown 和 HTML 为 UTF-8；`config.sh`、`inject-current.sh`、`follow-author-config.sh`、`verify.sh` 为 US-ASCII。
- 现有源码注释超过 70% 为中文；新增注释使用简体中文，只解释兼容原因、协议边界、失败策略或非直观风险，不逐行解释语法。
- 用户可见配置、环境变量、CLI 参数、诊断字段、启动方式或兼容策略变化必须同步 `README.md`；模块或数据流变化同时同步 `.easy-coding/ABSTRACT.md`。
- `.easy-coding/config.yaml` 和平台 hook 配置由 CLI 管理，代码任务不得编辑；ec-init 只维护白名单结构的 `.easy-coding/project.yaml`。
- 不写入令牌、Cookie、账号数据、应用包体或调试响应快照；临时探针数据不得加入仓库。
- 提交前至少执行 `./verify.sh`；有调试端口时再执行 `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh`。

## JavaScript ESM — `inject-wide-layout.mjs`

- 使用 Node.js ESM、`node:` 内置模块导入、双引号、分号和 2 空格缩进；多行对象与数组保持尾逗号。
- 运行时不固定单一 Node 版本，但必须通过 `typeof fetch === "function"` 与 `typeof WebSocket === "function"` 能力检查；初始化时已验证 Node `v22.16.0` 和应用内置 Node `v24.14.0`。
- 顶层常量使用 `UPPER_SNAKE_CASE`，函数和变量使用 `lowerCamelCase`，布尔配置使用正向语义名称。
- CLI 配置链保持职责分离：`parseCliArgs` 解析参数，`ensureConfig` 读取配置，`buildOptions` 合并并校验，`buildMeta` 生成诊断元信息，`buildCss` 生成 CSS。
- 配置优先级固定为“内置默认值 < 配置文件 < 环境变量 < CLI”；新增配置必须接入该链，旧 alias 不得静默删除。
- 参数、JSON、布尔值、正整数、CSS size/color 校验失败必须抛出含字段名的 `Error`；主入口统一输出 `[codex-app-extension]` 前缀并返回非零状态。
- 页面注入源码不得调用 Node.js API；Node 与页面上下文之间只通过生成字符串、CDP 和 JSON 可序列化值传递。
- debugger target 不得回退任意页面；写入页面前必须通过 Codex surface 探针。CSS 选择器必须受 `data-codex-app-extension-surface="true"` 约束，离开表面时清理扩展写入的宽屏变量。
- 输入增强只接管已识别的 ProseMirror composer 或 request input；dismiss/skip 不能作为提交按钮，无法唯一识别提交动作时让 Codex 原生处理。
- 清理旧 observer、handler、样式或可选 CDP 能力时允许容错；catch 若忽略错误，必须用注释说明该路径为何非关键。
- 新增运行时行为必须在 `buildDiagnoseSource` 或安装结果中暴露足够状态，以便 `--diagnose` 定位配置、选择器和最近事件。

## Bash — `*.sh` 与 `lib/runtime.sh`

- 所有可执行 Shell 脚本使用 `#!/usr/bin/env bash` 和 `set -euo pipefail`，并保持 macOS Bash `3.2` 可运行；不得使用关联数组、`mapfile` 等新版本专属语法。
- 仓库内路径从 `BASH_SOURCE[0]` 计算；路径、变量展开和命令参数必须加双引号。
- 应用、Node 和端口发现复用 `lib/runtime.sh`，不得在各入口复制 `/Applications/ChatGPT.app`、Node 能力检查或 `lsof` 解析逻辑。
- 显式环境变量优先于自动发现；候选发现可以失败开放，但最终 app bundle、Node 能力和 `/json/version` 校验必须决定是否继续。
- 远程调试地址固定为 `127.0.0.1`；不得改为对外网卡监听。
- 错误写入 stderr 并返回非零；帮助与成功信息写入 stdout。新增环境变量或优先级变化同步 README。
- 修改 Shell 后运行 `bash -n`；统一验证由 `./verify.sh` 执行。

## JSON、Markdown 与预览 HTML

- `data/author-config.json` 保持合法 JSON、双引号和 2 空格缩进；字段必须与 `DEFAULT_CONFIG` 的已支持配置对应。
- README 命令必须真实存在；当前正式入口为 `./launch.sh`、`./config.sh`、`./inject-current.sh` 和 `./verify.sh`，不得记录猜测的 build/lint/test 命令。
- `strong-text-color-preview.html` 仅用于人工配色预览，不得作为生产注入实现或自动验证替代品。
