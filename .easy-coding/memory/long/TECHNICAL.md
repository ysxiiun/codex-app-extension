---
memory_schema: 2
memory_file: TECHNICAL
last_updated: 2026-05-28
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
