---
memory_schema: 2
id: SM-20260710-004
date: 2026-07-10
task_type: refactor
project_mode: iteration
domain:
  - codex-app-extension
  - runtime-compatibility
  - input-protocol
tags:
  - ChatGPT-Codex
  - app-discovery
  - surface-guard
  - request-input
  - CDP
related_files:
  - lib/runtime.sh
  - launch.sh
  - config.sh
  - inject-current.sh
  - inject-wide-layout.mjs
  - verify.sh
  - README.md
  - .easy-coding/ABSTRACT.md
commit: none
verification: partial
memory_value: technical
target_long: TECHNICAL
---

# ChatGPT Codex 兼容适配

## 任务摘要

- 目标：将项目从旧版独立 `Codex.app` 运行时假设适配到当前 `ChatGPT.app` 承载的 Codex 工作区，并保留旧版入口。
- 范围：应用、Node 与调试端口发现链，CDP target 选择与 Codex 表面门禁，新版 request input 协议，自动验证脚本、README 和架构摘要。
- 结果：已完成静态与生成代码验证。项目可优先发现 `/Applications/ChatGPT.app`，识别 bundle id `com.openai.codex`，使用 PATH 或应用内置兼容 Node；注入逻辑仅在 Codex 表面激活，并兼容新版数据属性 request input 与旧类名回退。
- 关键约束：不修改 ChatGPT/Codex 应用包体、账号数据或历史会话；不重启当前承载任务且未开放 CDP 端口的进程；保留旧环境变量、CLI、`Codex.app` 路径与输入选择器兼容。

## 执行证据

| 类型 | 内容 |
|---|---|
| 关键文件 | `lib/runtime.sh`、`launch.sh`、`config.sh`、`inject-current.sh`、`inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md` |
| 验证命令 | `./verify.sh` 通过；`bash -n lib/runtime.sh launch.sh config.sh inject-current.sh verify.sh` 通过；`node --check inject-wide-layout.mjs` 通过；`git diff --check` 通过；生成后的诊断/安装源、宽屏开启/关闭分支、target 防误选和表面探针断言通过 |
| 人工验收 | 当前 `/Applications/ChatGPT.app` 版本 `26.707.31428`、bundle id `com.openai.codex`；PATH Node `v22.16.0` 与内置 `cua_node` `v24.14.0` 能力检查通过；当前进程无调试端口，未执行在线 CDP 注入验收 |
| 提交信息 | none |

## 业务记忆候选

> 只记录未来可能复用的业务事实。无则写“无”。

- 业务概念 / 字段语义：桌面应用显示名和安装路径已变为 `ChatGPT.app`，当前 Codex 桌面 bundle id 仍为 `com.openai.codex`。
- 业务流程 / 状态流转：工具启动前先解析应用与 Node，再开放回环调试端口、选择候选 target、校验 Codex DOM 表面，最后才执行增强注入。
- 业务规则 / 兼容背景：本项目只增强 ChatGPT 中的 Codex 工作区；同一 target 若切换到非 Codex 页面，增强必须失活并把输入行为交回原生页面。
- 上下游契约：新版 request input 的稳定契约是外层 `data-codex-composer-request-navigation`，`data-request-input-dismiss` / `data-request-input-skip` 表示不可作为提交按钮的动作。
- 业务排障经验：应用更名、可执行进程名、Node 内置路径、CDP target 和页面 DOM 协议是五个独立兼容边界，不能只替换 `/Applications/Codex.app` 字符串。

## 技术记忆候选

> 只记录未来可能复用的工程事实。无则写“无”。

- 架构 / 接口决策：统一由 `lib/runtime.sh` 处理应用、Node 和调试端口发现；应用优先级为显式 `CODEX_APP`、`ChatGPT.app`、`Codex.app`，Node 必须同时提供原生 `fetch` 与 `WebSocket`。
- 工程规则 / 工作流：新版应用内置 Node 路径为 `Contents/Resources/cua_node/bin/node`；远程调试显式绑定 `127.0.0.1`；升级后先运行 `./verify.sh`，有 CDP 端口时再用 `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` 做只读在线诊断。
- 实现模式 / 复用写法：target 只做信号评分，不回退任意首个页面；注入前用布局根、工作区锚点和交互锚点组成 Codex 表面签名，运行时以 `data-codex-app-extension-surface="true"` 同时约束 CSS、布局变量与输入事件。
- 易错点 / 修复策略：新版 request input textarea 已无旧 `request-input-panel__inline-freeform` 类名，应通过外层数据属性识别；Cmd+Enter 提交按钮必须排除 dismiss/skip，无法唯一判断时失败开放给 Codex 原生行为。
- 验证经验：仅检查源文件语法不足以覆盖模板字符串注入代码；验证脚本应动态暴露 builder、编译生成后的 diagnose/installer 源，并对 target 选择、表面支持/拒绝和 CSS 作用域执行断言。

## 不沉淀内容

> 记录不进入长期记忆的内容与原因，避免沉淀时误吸收流水账。

- 当前版本号、`app.asar` 锚点出现次数和无调试端口的进程快照属于本次环境证据，未来版本可能变化，不直接沉淀为长期不变量。

## 关联记忆

- 前置：`SM-20260528-001`、`SM-20260708-002`、`SM-20260708-003`；长期主题“运行时注入架构”“配置化增强链路”“输入与布局增强边界”。
- 后续：退出当前 ChatGPT 后使用 `./launch.sh` 启动，并执行一次在线注入与 `--diagnose` 验收。
