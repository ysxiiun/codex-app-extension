---
memory_schema: 2
id: SM-019fa354-fcbc-73c8-bb85-fb7317c4f4e7
source_task: 07-27-align-git-plan-composer
date: 2026-07-27
task_type: bugfix
project_mode: iteration
workflow_mode: standard
domain:
  - codex-app-extension
  - runtime-layout
  - composer-attached-overlay
tags:
  - git-diff
  - plan
  - composer
  - dynamic-alignment
  - diagnose
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

# Git Diff 与 Plan 顶部组件动态中心对齐修复

## Task Summary

- Goal: 让运行任务时位于 composer 上方的 Git Diff / Plan 组件与增强后的输入框共用中心线，消除新版 Codex DOM 下重复应用宽屏横向偏移造成的左偏。
- Scope: `inject-wide-layout.mjs` 的新旧附着组件分类、目标级几何偏移、生命周期与诊断；`verify.sh` 的可执行分类/清理回归；`README.md` 与 `.easy-coding/ABSTRACT.md` 的行为契约。
- Result: 已兼容旧版 `bottom-full + composer-home-top-menu` wrapper 和新版 composer 同宿主顶部 slot；专用对齐变量改为目标相对自然位置的绝对 translate。独立 REVIEW 通过，最终静态与在线验证全绿。
- Key Constraints: 不改 Git Diff / Plan 的内容、宽度、交互和纵向位置；不误标普通正文、瞬态菜单或持久 right rail；已有原生 transform 时失败开放；目标退出、增强关闭或离开 surface 时清理属性与行内变量。

## Execution Evidence

| Type | Content |
|---|---|
| Key Files | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md` |
| Verification Commands | `node --check inject-wide-layout.mjs`、`bash -n verify.sh`、`./verify.sh`、`git diff --check` 均退出 0；`./verify.sh` 执行生产分类器、共同宿主/定位祖先遍历、原生 transform 排除、重复刷新、目标退出与增强关闭清理回归 |
| Live Evidence | `./inject-current.sh && ./inject-current.sh --diagnose` 退出 0；新版目标被分类为 `composer-top-slot`，`composerCenterX=922`、`naturalTargetCenterX=922`、`centerDeltaX=0`、`resolvedOffsetX=0px`；右侧 rail 宽 `316px` 且主内容 `contentOffsetX=-158px` 保持 |
| Review | Standard 独立 reviewer 初审发现测试合同偏静态；两轮修复后重审 `accept`、`findings=[]`，最终实现指纹 `6fa556004cd3b3fc8d9c1ad378ec69bf0c20dcd8a11cff49bf1b84fb8c23f498` |
| Manual Acceptance | 用户已确认进入 MEMORY；Plan 未在最终窗口单独出现，但它与 Git Diff 共用的新版顶部 slot 已由结构与几何回归覆盖 |
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

- Architecture / Interface Decisions: composer 附着组件必须同时兼容旧版类名信号与新版几何结构。新版候选要求消费 thread/composer 宽度变量、与主 composer 共享非 layout-shell 宿主、位于其上方并具有定位祖先，同时排除 `menu/listbox` 和 `thread-floating-content`。
- Engineering Rules / Workflows: `--codex-app-extension-aligned-overlay-offset-x` 表示目标相对未应用 CSS translate 时的绝对横向位移，不等同于根 `contentOffsetX`。诊断应暴露 `overlayKind`、当前 translate、自然中心、composer 中心、中心差和最终偏移。
- Implementation Patterns / Reusable Approaches: 用 `naturalTargetCenterX = currentTargetCenterX - currentTranslateX` 恢复自然中心，再以 `composerCenterX - naturalTargetCenterX` 计算目标级绝对 translate；宽度变量稳定后再测量和标记，使新版自然居中的 slot 得到 `0px`，旧版仍保留所需左移。
- Pitfalls / Fix Strategies: 只识别 `bottom-full` 会在官方 DOM 演进后完全漏判；把专用偏移固定继承根 `contentOffsetX` 会让本已自然居中的新版 slot 重复左移。按当前已偏移矩形直接计算增量还会造成刷新累计，必须先扣除 computed translate。
- Verification Experience: 不应只检查生成源码包含函数名或 `setProperty/removeProperty` 字符串。应提取并执行生产分类器、共同宿主/定位祖先函数、目标收集与生命周期函数，用真实 `parentElement` 链和样式桩覆盖同宿主正例、普通 flow/menu/rail/独立宿主负例、原生 transform 失败开放、重复刷新幂等和关闭清理。

## Non-Distillation Content

> Content that should NOT enter long-term memory, with reasons — prevents accidental absorption of noise.

- 本次在线窗口的具体像素坐标、右侧 rail 宽度、任务时间戳、实现指纹和 reviewer 交互过程属于一次性验证证据；长期只保留新版 DOM 识别条件、绝对位移语义、自然中心算法、清理合同与可执行回归方法。

## Related Memories

- Predecessor: `SM-019f8ec0-b3d2-7bb3-8327-54be49bbebf7`（模型菜单与旧版 composer 顶部组件对齐；本任务修正其固定 `bottom-full` 与根偏移假设）。
- Related: `SM-019f9237-1a27-7dff-a9b8-557d911db38d`（瞬态菜单定位 wrapper 对称分类与 rail 排除）。
- Successor: none.
