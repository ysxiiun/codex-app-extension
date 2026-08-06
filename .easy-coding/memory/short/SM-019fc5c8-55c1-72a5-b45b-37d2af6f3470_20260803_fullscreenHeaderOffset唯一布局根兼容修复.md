---
memory_schema: 2
id: SM-019fc5c8-55c1-72a5-b45b-37d2af6f3470
source_task: 08-03-restore-fullscreen-header-offset
date: 2026-08-03
task_type: bugfix
project_mode: iteration
workflow_mode: standard
domain:
  - codex-app-extension
  - runtime-layout
  - header-offset
tags:
  - fullscreenHeaderOffset
  - app-shell-layout
  - compatibility-root
  - unique-marker
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

# fullscreenHeaderOffset 唯一布局根兼容修复

## Task Summary

- Goal: 恢复 ChatGPT 升级后 `fullscreenHeaderOffset` 对固定顶部 header 的避让，消除全屏窗口中标题栏与 Git Diff、Plan 或对话内容重叠。
- Scope: `inject-wide-layout.mjs` 的顶部避让目标选择与 CSS、`verify.sh` 的生成 CSS/生命周期回归，以及 `README.md`、`.easy-coding/ABSTRACT.md` 的兼容合同。
- Result: 运行时按 `[data-app-shell-main-content-layout]`、`.app-shell-main-content-viewport`、`main.main-surface/.main-surface` 的优先级只标记一个实际布局根，再由 surface-guarded CSS 应用 `border-box + fullscreenHeaderOffset`。独立 REVIEW 接受，离线、live diagnose、重注入和真实几何验证全绿。
- Key Constraints: 不改变 `fullscreenHeaderOffset` 字段、默认值、CLI 或窗口/全屏语义；不把扩展偏移叠加到 `.thread-scroll-container` 的原生顶部 inset；新旧根嵌套共存时不能累计 padding；离开 Codex surface 或根切换时清理旧 marker。

## Execution Evidence

| Type | Content |
|---|---|
| Key Files | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md` |
| Verification Commands | `node --check inject-wide-layout.mjs`、`bash -n verify.sh`、`git diff --check`、`./verify.sh`、`CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` 均退出 0 |
| Live Evidence | 最终配置 `46px`；唯一 marker 位于 `[data-app-shell-main-content-layout]`；layout `padding-top=46px` 且 `box-sizing=border-box`；`header.bottom=46` 等于 frame/thread `top=46`；thread 原生 `padding-top=78px` 保持；右侧 rail `top=104`，composer 仍在可视区内 |
| Review | Standard 独立 reviewer 初审发现 grouped `:where(...)` 在新旧根嵌套时可能累计 padding；改为唯一优先 marker 并增加执行生产 lifecycle 的混合根回归后，复审 `accept`、`findings=[]` |
| Manual Acceptance | 用户已确认当前全屏顶部重叠消失并同意进入 MEMORY |
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

- Architecture / Interface Decisions: 顶部避让不是对所有兼容 selector 同时加 padding，而是运行时按新版 data layout、旧 app-shell viewport、旧 main surface 的顺序只选择并标记一个根；CSS 只匹配 `data-codex-app-extension-header-offset-target="true"`。
- Engineering Rules / Workflows: `fullscreenHeaderOffset` 独立于 `wideLayoutEnhancement`，因此唯一目标选择必须位于宽屏开关分支之前。surface 不支持时以及 DOM 根切换时必须清理旧 marker；marker 属性不加入 MutationObserver 的 attributeFilter，避免自激刷新。
- Implementation Patterns / Reusable Approaches: 当跨版本兼容根可能祖先/后代嵌套时，grouped `:is/:where` 只能合并 selector，不能保证单点生效。对会累积的 padding/transform/margin 应采用“有序候选选择 + 唯一运行时 marker + 生命周期清理”。
- Pitfalls / Fix Strategies: 给 `[data-app-shell-main-content-layout]` 与旧 main surface 同时声明 `46px` 会在混合 DOM 中产生约 `92px` 留白；直接给 `.thread-scroll-container` 加偏移又会叠加其原生 `--thread-content-top-inset`。正确层是包住主 frame、thread 和 rail 的唯一主布局根，并使用 `border-box` 保持总高度。
- Verification Experience: 仅统计一条 grouped CSS rule 无法证明只命中一个元素。回归应提取并执行生产 marker lifecycle 函数，构造所有兼容根同时存在的混合 stub，验证唯一优先目标、逐级回退、旧 marker 清理、thread 排除及宽屏开/关两种变体；在线再验证 marker 数量和 header/frame 几何相等。

## Non-Distillation Content

> Content that should NOT enter long-term memory, with reasons — prevents accidental absorption of noise.

- 当前窗口尺寸、具体 rail/composer 坐标、应用 build、实现/配置指纹和 reviewer 往返过程属于一次性证据；长期只保留唯一优先根合同、累积型 CSS 不能使用 grouped roots 的原则、生命周期清理和验证方法。

## Related Memories

- Predecessor: `SM-20260710-004`（ChatGPT Codex 兼容适配，建立 app-shell surface 与运行时注入链）。
- Related: `SM-019fc5a8-f783-78a3-880a-ca2a2ac96bbe`（同版 ChatGPT 移除 main surface 后的 Markdown 内容根兼容；本任务处理的是布局根，不能把两类根混用）。
- Successor: none.
