---
memory_schema: 2
id: SM-019fcfe3-0cfa-7d6b-987c-0edda8fb811c
source_task: 08-03-fix-release-rpath-idempotent-installer
date: 2026-08-05
task_type: bugfix
project_mode: iteration
workflow_mode: strict
domain:
  - codex-app-extension
  - macos-release-installation
  - chatgpt-cdp-runtime
  - responsive-wide-layout
tags:
  - rpath
  - idempotent-installer
  - target-generation
  - PageRuntime-V2
  - rendered-right-rail
  - SwiftUI-menu-bar
related_files:
  - install.sh
  - CodexAppExtension.xcodeproj/project.pbxproj
  - CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift
  - CodexAppExtension/Core/CDP/TargetCoordinator.swift
  - CodexAppExtension/Core/Runtime/RuntimeController.swift
  - CodexAppExtension/Core/Health/HealthCenter.swift
  - CodexAppExtension/Resources/PageRuntime/bootstrap.js
  - CodexAppExtension/Resources/Adapters/wide-layout.js
  - CodexAppExtension/App/StatusMenuView.swift
  - PageRuntimeTests/AdapterFixtureTests.swift
  - CodexAppExtensionUITests/MenuBarUITests.swift
  - README.md
commit: none
verification: passed
memory_value: technical
target_long: TECHNICAL
---

# Release 幂等安装与动态宽屏布局稳定修复

## Task Summary

- Goal: 修复原生菜单栏 App 的 Release 动态链接、构建签名安装、CDP target/runtime 健康闪烁，以及宽屏增强在 Codex 原生响应式侧栏切换中的重复横移、边距失效和流式布局抖动。
- Scope: 交付八步幂等安装脚本；修正 ExtensionCore `@rpath`；加固 `Runtime.evaluate`、稳定 target 身份、revision/generation 健康顺序；重构 wide-layout 的 rendered-rail、per-owner residual 与 motion lifecycle；对齐菜单快速开关并同步测试和文档。
- Result: `/Applications/Codex App Extension.app` 可由 `./install.sh` 自动构建、ad-hoc 签名、审计、原子替换、启动与存活检查；相同包重复执行会跳过 swap。宽屏只按当前实际渲染的右侧实体计算边界，抵扣 Codex 原生 transform 后再施加每个 owner 的剩余偏移，窗口/侧栏动画过程中不会重复横移或固定预留隐藏栏宽度。用户完成真实视觉验收并明确回复“验证通过”。
- Key Constraints: 不安装 framework 到 `/Library/Frameworks`；不强杀运行中的 App；不重启 ChatGPT；不读取页面正文、输入、Cookie 或 payload；不使用复制的 Codex 响应式断点；不接管 composer、Markdown leaf、选区 overlay、menu/listbox/dialog 或浮动右栏宽度；不提交或推送 Git。

## Architecture and Compatibility Decisions

- Release packaging: ExtensionCore install name 与 App runpath 统一使用 `@rpath`。安装器按 preflight、增量 Release build、本地签名、built audit、同级 staging/swap、installed audit、launch、survival 八步执行；目标包相同时安全跳过替换，替换路径保留可回滚语义。
- Runtime evaluation: 副作用脚本允许 CDP 返回合法 `undefined`；查询表达式仍要求 value；`exceptionDetails` 始终作为真实失败，不能全局映射为 null。
- Target identity: 稳定身份由唯一 layout 与其包含的 thread scroller 决定；composer 是可选输入能力，不得因编辑器瞬态挂载、floating editor 或歧义而撤销布局 target。
- Health ordering: target lifecycle generation、bridge revision 与 tombstone 的比较和写删在 `HealthCenter` actor 内原子完成。旧 update/remove、同代删除后的迟到 update、旧 target cleanup 都不能覆盖或复活新 target 状态。
- Wide layout boundary: 右边界来自当前真实渲染、与聊天区域相交且非瞬态的 panel body；结构 shell、隐藏/离屏实体、menu/listbox/dialog 不保留宽度。无 rendered rail 时扩展剩余横移必须为 `0px`。
- Per-owner compensation: 最外层原生内容 owner 与 composer owner 分别沿自己的 ancestor chain 读取纯水平 native transform，再应用 `requestedShift - nativeShift`。`matrix()`、纯平移 `matrix3d()` 与 individual translate 可解析；包含 scale/rotate/perspective 的矩阵保守忽略，避免误读 m41。
- Motion convergence: 只监听实际几何节点的 transition/animation 生命周期。持久 rail shell 只代理当前非瞬态 panel body 的冒泡事件；观察集合 churn 保留仍存在目标的 active motion。动画期间维持单一 RAF reconcile，end/cancel 后最终收敛并清理。
- Ownership and cleanup: outer native content/composer owner 才持有增强宽度与私有 offset；Markdown、selected overlay、streaming leaf 只间接受益，保持零 owner/零 translate。owner 替换和 uninstall 必须恢复原内联值及 priority，移除 listener、observer、active motion 与 RAF。
- Menu UI: 四个快速开关使用满宽双列布局，标题左对齐、switch 右对齐；原 action、disabled 和 accessibility identifier 不变。

## Verification Evidence

| Type | Result |
|---|---|
| Final Fingerprints | implementation `199b0c95acb8ff5610e55afbd5b5764811c9e65a588c05c3bab1186ba62bcb41`；config `8205665aca967d342d277a1aae9f4a2377068ce6a3026c0c80adfa5eb5d046a1` |
| Review | `correctness-contracts` 与 `compliance-tests-security` 对最终实现指纹均 `passed=true`、`findings=[]` |
| Static/Typecheck | Shell、plist、JavaScript、diff lint 全绿；Debug build `BUILD SUCCEEDED` |
| Core/Runtime | ExtensionCoreTests `123/123`；受影响 AdapterFixtureTests + PageRuntimeTests `28/28` |
| Menu UI | MenuBarUITests 在释放同 bundle-id 旧进程后以同一命令真实重跑，`5/5` 通过；历史 bootstrap 环境失败保留在追加式账本，同名通过记录将其取代为当前证据 |
| Release Install | Release build、built/installed codesign strict audit、重复 `./install.sh`、启动及 3 秒存活均通过；重复安装识别相同 bundle 并跳过 swap |
| Resource Integrity | 仓库与 `/Applications/Codex App Extension.app` 中 `wide-layout.js` SHA-256 均为 `96a2d8c8218f5c63c60792e2dbd29dc874019e927feef0c11be506038c41cb8f` |
| Live CDP | 清除热加载后由正式安装包重新注入；真实窗口从 1920px 收缩到约 844px 时，内容宽度从 1300px 收敛到 531px、扩展 offset 从 -150px 归零，owner 左边界始终留在 scroller 左边界内；selected/Markdown 误修改为 0；最终宽屏状态 `200/200` 样本一致 |
| Manual Acceptance | 用户在正式安装版本上验证通过 |
| Commit Info | none |

## Reusable Technical Memory

- Codex 响应式布局不能用固定阈值或“看到结构 shell 就预留 316px”模拟。必须在每次 reconcile 读取当前实际 painted/rendered entity，并允许 Codex 自身根据窗口空间显示、隐藏或移动右栏。
- 当宿主自己用 transform 完成栏位居中时，扩展只能补齐剩余偏移；直接再应用目标偏移会形成 double shift。内容区和 composer 可能拥有不同 native ancestor chain，补偿必须 per owner。
- `ResizeObserver` 不应观察流式正文或 native shift ancestor，否则流式高度变化会反馈到布局循环。正文 mutation 和临时浮层 animation 也不能启动几何 RAF。
- 对 CSS motion 的一次 mutation/一次 RAF 不足以保证终态；应以 transition/animation lifecycle 驱动一个有界 RAF loop，并在 end/cancel 做最终 reconcile。
- PageRuntime adapter 对宿主内联属性必须保存 value 与 priority；DOM owner replacement 时立即恢复离开的 owner，再快照新 owner。卸载验证必须覆盖所有 listener、observer、RAF 和属性恢复。
- 追加式验证账本以 `check` 名称选择最新记录。环境失败被真实同命令重跑修复后，应追加同名 passed 记录，保留失败历史而让门禁读取最新证据；不能删除失败或改写成伪绿。
- 一键安装器的幂等性不是只重复 build：需要审计 built bundle、比较 installed bundle、只对明确同级路径进行 stage/swap、审计 installed bundle、重启并验证存活。

## Business Memory Candidates

- Concepts / Field Semantics: none.
- Workflows / State Transitions: none.
- Business Rules / Compatibility: none.
- Upstream/Downstream Contracts: none.
- Business Troubleshooting: none.

## Non-Distillation Content

- 一次性的 PID、CDP target id、WebSocket URL、窗口像素样本和 `/private/tmp` DerivedData/xcresult 路径仅属于本次证据。
- 当前实现/配置/resource 指纹用于绑定本次验证，不应作为永久兼容性常量。

## Related Memories

- Predecessor: `SM-019fc76b-6b2c-745d-9c4b-d08639bd0a68`（原生菜单栏运行时 V2 重构）。
- Related: `SM-019fc5a8-f783-78a3-880a-ca2a2ac96bbe`（Markdown 主题根兼容）。
- Related: `SM-019fc5c8-55c1-72a5-b45b-37d2af6f3470`（唯一布局根与 fullscreen header offset）。
- Successor: none.
