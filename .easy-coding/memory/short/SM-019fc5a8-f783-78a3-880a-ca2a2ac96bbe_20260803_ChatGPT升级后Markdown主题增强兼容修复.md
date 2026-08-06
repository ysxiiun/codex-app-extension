---
memory_schema: 2
id: SM-019fc5a8-f783-78a3-880a-ca2a2ac96bbe
source_task: 08-03-restore-theme-enhancement-after-chatgpt-upgrade
date: 2026-08-03
task_type: bugfix
project_mode: iteration
workflow_mode: standard
domain:
  - codex-app-extension
  - runtime-theme
  - chatgpt-dom-compatibility
tags:
  - markdown
  - theme-enhancement
  - thread-scroll-container
  - selector-contract
  - cdp
  - regression-test
related_files:
  - inject-wide-layout.mjs
  - verify.sh
  - README.md
  - .easy-coding/ABSTRACT.md
commit: none
verification: passed
memory_value: technical
target_long: TECHNICAL
---

# ChatGPT 升级后 Markdown 主题增强兼容修复

## Task Summary

- Goal: 恢复 ChatGPT `26.727.51351` 升级后 Codex 主工作区的 Markdown 标题、strong、行内代码和引用块主题增强，并保留旧版 DOM 兼容。
- Scope: `inject-wide-layout.mjs` 的六组 Markdown CSS 根选择器、`verify.sh` 的生成 CSS 合同与负向回归，以及 `README.md`、`.easy-coding/ABSTRACT.md` 的兼容说明。
- Result: Markdown 增强统一使用受 surface 门禁约束的 `:is(main.main-surface, .main-surface, .thread-scroll-container)` 内容根；旧根继续兼容，新版 `.thread-scroll-container` 恢复命中。独立 REVIEW 接受，离线与当前真实页面验证全绿。
- Key Constraints: 不改变色板、字重、边框、间距、配置 schema、CLI 或诊断 JSON；继续使用 Markdown-like 子选择器和代码块排除；不覆盖任务开始前已有的 Harness 与作者配置改动。

## Execution Evidence

| Type | Content |
|---|---|
| Key Files | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md` |
| Verification Commands | `node --check inject-wide-layout.mjs`、`bash -n verify.sh`、`git diff --check`、`./verify.sh`、`CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` 均退出 0 |
| Live Evidence | `./inject-current.sh` 重注入成功；真实页面 `mainSurfaceCount=0`、`threadScrollCount=1`。blockquote 背景为 `rgba(223,48,121,.06)` 且左边框为 `3px solid rgb(223,48,121)`；strong 为 `rgb(242,201,76)`/`800`；行内代码为 `rgb(223,48,121)`，三类样本各命中一条扩展规则 |
| Review | Standard 独立 reviewer 首轮指出旧根负向检查可能漏掉 `.main-surface` 或换行格式；改为解析完整 selector prelude、按括号深度拆分顶层 selector list，并与精确 7 项允许集合比对后，复审 `accept`、`findings=[]` |
| Manual Acceptance | 用户已确认当前视觉效果验收通过并同意进入 MEMORY |
| Commit Info | none |

## Business Memory Candidates

> Only record business facts with future reuse value. Write "none" if none.

- Concepts / Field Semantics: none.
- Workflows / State Transitions: none.
- Business Rules / Compatibility: none.
- Upstream/Downstream Contracts: none.
- Business Troubleshooting: none.

## Technical Memory Candidates

> Only record engineering facts with future reuse value. Write "none" if none.

- Architecture / Interface Decisions: Markdown 主题增强的内容根合同是 `:is(main.main-surface, .main-surface, .thread-scroll-container)`；它必须位于根级 `data-codex-app-extension-surface="true"` 和对应增强开关属性之下。旧版 main surface 与新版 thread scroll 都是兼容分支，不能将其中之一再次固化为唯一根。
- Engineering Rules / Workflows: 当诊断显示样式节点已安装、开关属性为 `true`，但真实元素没有匹配扩展规则时，应同时核对当前 DOM 根节点数量和生成 CSS 的作用域；这类现象优先判断为选择器静默失配，而不是配置或注入失败。
- Implementation Patterns / Reusable Approaches: 将共享 DOM 兼容根提取为单一常量，并由 heading、strong、inline-code、pre-code reset、顶层 blockquote、嵌套 blockquote 全部复用；这样生产规则与回归合同可围绕一个明确根集合演进。
- Pitfalls / Fix Strategies: 仅用邻接单行正则禁止 `main.main-surface` 会漏掉 `.main-surface` 和换行格式，造成测试假通过。验证应去除注释后解析完整 CSS selector prelude，跟踪括号深度拆分顶层逗号，并将主题相关选择器与精确允许集合及数量同时比对。
- Verification Experience: 升级兼容修复应组合生成 CSS 回归、legacy-only 负向样例、live target/surface 诊断、当前页面重注入和真实元素 computed-style/匹配规则探针；仅看到 `installed=true` 不足以证明样式生效。

## Non-Distillation Content

> Content that should NOT enter long-term memory, with reasons — prevents accidental absorption of noise.

- 当前窗口的具体颜色计算值、应用 build、实现/配置指纹、任务时间戳和 reviewer 往返过程属于一次性验收证据；长期只保留三根兼容合同、静默失配诊断路径、精确 selector 集合验证方法和在线验证组合。

## Related Memories

- Predecessor: `SM-20260710-004`（ChatGPT Codex 兼容适配，建立当前 app target、surface probe 与运行时兼容基础）。
- Related: `SM-20260713-005`（浅色主题引用块正文 inherit 与嵌套扁平化，本任务保持其引用块行为不变量）。
- Successor: none.
