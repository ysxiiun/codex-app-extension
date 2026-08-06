---
memory_schema: 2
id: SM-019fc76b-6b2c-745d-9c4b-d08639bd0a68
source_task: 08-03-rebuild-codex-menu-bar-runtime-v2
date: 2026-08-03
task_type: refactor
project_mode: iteration
workflow_mode: strict
domain:
  - codex-app-extension
  - macos-menu-bar
  - chatgpt-cdp-runtime
  - configuration-migration
tags:
  - SwiftUI
  - MenuBarExtra
  - ExtensionCore
  - PageRuntime-V2
  - dynamic-loopback-cdp
  - diagnostics-privacy
  - legacy-cutover
related_files:
  - CodexAppExtension.xcodeproj/project.pbxproj
  - CodexAppExtension/App/CodexAppExtensionApp.swift
  - CodexAppExtension/App/AppModel.swift
  - CodexAppExtension/Core/Runtime/RuntimeController.swift
  - CodexAppExtension/Core/Configuration/ConfigStore.swift
  - CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift
  - CodexAppExtension/Resources/PageRuntime/bootstrap.js
  - README.md
  - .easy-coding/ABSTRACT.md
  - .easy-coding/TEST_STRATEGY.md
commit: none
verification: passed
memory_value: technical
target_long: TECHNICAL
---

# Codex App Extension 原生菜单栏运行时 V2 重构

## Task Summary

- Goal: 对随 ChatGPT Codex 多次升级而失效、耦合和难以维护的 Shell/Node 页面注入工具做全局替换，交付常驻 macOS 菜单栏、可视化配置、可降级恢复的原生扩展工具。
- Scope: 新建 macOS 13+ SwiftUI/Xcode App 与 ExtensionCore；实现进程生命周期、动态回环 CDP、Browser target 协调、PageRuntime V2 与 adapters、schema-v2 配置迁移、菜单/五页设置、登录启动、诊断隐私和完整测试；绿色切换后删除旧 Shell/Node 产品链并重写文档。
- Result: 发布树只保留原生 `Codex App Extension` 和六个 JavaScript 页面资源。App 使用 `MenuBarExtra(.window)`、`LSUIElement=true`、bundle id `com.ysxiiun.codexappextension`；设置由可复用的显式 `NSWindow` coordinator 承载。运行时只接纳 exact ChatGPT 主进程与 exact Codex target，五个 adapter 可独立安装、诊断、降级和卸载。严格 REVIEW、自动化、Release 与当前 ChatGPT 只读 live gate 全绿。
- Key Constraints: 未经确认不能重启正在运行的 ChatGPT；CDP 只允许显式 `127.0.0.1`；live gate 不读取正文/草稿/Cookie/payload、不发送、不保存配置；诊断必须 typed allowlist；adapter 失败开放且单项隔离；任务不安装 App、不部署、不提交或推送 Git。

## Architecture and Migration Decisions

- Native shell: `MenuBarExtra(.window)` 展示绿/黄/红/灰四态，菜单和五页设置共用一个 `AppModel`/`RuntimeController`/`ConfigStore`。设置窗口使用显式 `SettingsWindowCoordinator` 创建和复用 `NSWindow`，支持启动早期请求排队；不依赖隐式 Settings scene/openSettings bridge。
- Process and CDP: 只识别 `/Applications/ChatGPT.app`、bundle id `com.openai.codex` 的主进程；已有端口仅在地址明确为 `127.0.0.1` 时复用。受管启动选择随机回环高位端口；正在运行但无 CDP 时进入等待确认态，确认前不调用 terminate、forceTerminate 或 open。
- Target boundary: Browser 级 WebSocket 订阅 `Target.*`；只接纳 exact `app://-/index.html`，并要求 `[data-app-shell-main-content-layout]`、`.thread-scroll-container`、唯一 ProseMirror editor 三锚点同时成立。连接代次、request id、超时、取消和迟到响应隔离，target reload/SPA 根替换会重新资格审查并重绑。
- Page runtime: `window.__codexAppExtensionV2` 是不可写的 runtimeVersion 2 API；bootstrap 与 adapter 源码分别加载，单 adapter 的 source/evaluate/execute 失败不阻塞其他项。发布 adapters 固定为 `wide-layout`、`header-offset`、`ime-enter-guard`、`focus-ring`、`markdown-semantic-theme`。`tab-indent` 因缺少稳定编辑器状态同步协议从 schema、注册表、资源和 UI 移除，保留系统原生 Tab 焦点导航。
- Configuration: schema-v2 是唯一配置源，使用同目录临时文件、同步、原子替换和 `last-known-good`；首次保存必须同时建立可恢复基线。V1 迁移保留备份、幂等执行，只映射有效字段，废弃/未知/无效字段进入报告。无合格 target 时页面配置仍可离线持久化，稍后连接再安装；在线更新失败则回滚页面和持久化状态。
- Health and privacy: 诊断事件只允许版本、状态、错误码、计数和耗时字段；日志按 `1 MiB × 5` 轮转并以 allowlist 导出。observer、事件和 target 状态容量有界；DOM burst 合并为一轮 RAF 加一轮 settle，adapter 连续超出 8 ms 预算三次后仅降级该项。
- Cutover: `inject-wide-layout.mjs`、`launch.sh`、`inject-current.sh`、`config.sh`、`follow-author-config.sh`、`lib/runtime.sh`、`verify.sh`、旧 author config 和预览页已从发布树删除；不能恢复双实现或 legacy fallback 来掩盖新运行时失败。

## Verification Evidence

| Type | Content |
|---|---|
| Final Fingerprints | implementation `2364765ecf074d96fb4a407c9c919729be3df1dca3bcfff16c5f21df0422fb97`；config `8205665aca967d342d277a1aae9f4a2377068ce6a3026c0c80adfa5eb5d046a1` |
| Review | `correctness-contracts` 与 `compliance-tests-security` 均对最终实现指纹 `passed=true`、`findings=[]` |
| Core/PageRuntime | `xcodebuild ... test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO`：91 tests、0 failures、0 skipped；结果包 `/tmp/codex-final-core-2364/Logs/Test/Test-CodexAppExtension-2026.08.03_19-23-13-+0800.xcresult` |
| UI | 最终完整 XCUITest：9 tests、0 failures；结果包 `/private/tmp/codex-final-ui-2364-all.xcresult` |
| Release | `xcodebuild ... -configuration Release ... build CODE_SIGNING_ALLOWED=NO` 成功；临时 ad-hoc 签名后 `codesign --verify --deep --strict` 通过；built Info 为 `LSUIElement=true`、macOS 13、正确 bundle id；资源严格为 bootstrap + 5 adapters；Release symbols/strings 无 Debug UI-test marker |
| Static | 六个 JavaScript `node --check`、源/built plist、project.pbxproj、`git diff --check`、legacy entry/body wildcard/Release resource scans 全绿 |
| Live | ChatGPT `26.727.51351` build `6119`；exact target 1；layout/thread/editor `1/1/1`；五 adapter install/diagnose/uninstall `5/5/5`；宿主 DOM/CSS 与主世界恢复；observer/RAF/timer `0/0/0`；source fingerprint `33e69e5a483a3ff0d357c5c5697a0f8ee90ae2e2e9b2048b94c03f75a2f05cad` |
| Manual Acceptance | 用户确认最终绿色验证后进入 MEMORY；未执行真实 ChatGPT 重启、安装、登录项系统批准、真实 IME 或多显示器状态项点击验收 |
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

- Architecture / Interface Decisions: 原生菜单栏 App 是唯一宿主；Swift 负责生命周期、配置、CDP、健康和 UI，页面 JavaScript 只负责通过资格审查的五个可卸载 adapter。UI 不直接操作 CDP/文件系统，所有动作通过公共 `RuntimeController`。
- Engineering Rules / Workflows: ChatGPT 兼容性不能由产品版本号或窗口标题推断；必须通过 exact 主进程、显式回环 CDP、exact target URL 和三个唯一 surface anchors 分层 preflight。build 或 surface 变化要失效能力缓存并重新探测，不能盲注入。
- Implementation Patterns / Reusable Approaches: 对非公开 DOM 使用小型独立 adapter、唯一 native anchors、幂等 install/update/diagnose/uninstall、宿主属性/CSS 快照恢复、observer 合并与单项性能熔断。配置使用“本地先校验、在线预应用、原子持久化、失败回滚”，同时允许离线保存后延迟安装。
- Pitfalls / Fix Strategies: 同 target SPA 根替换会让签名相同的幂等短路错误复用旧节点，必须把 surface revision 与 observer qualification 纳入判定。adapter 聚合不能把单项失败升级为整 target 丢失。首次配置保存若 current 成功而 LKG 失败会留下不可恢复状态，必须把两者作为一次原子基线建立。
- UI Testing Boundary: Xcode 26.6 在当前多显示器坐标空间会把 `MenuBarExtra` 状态项点击错投到屏幕底部。自动化只对真实状态项 `menuBar.status` 做标识冒烟，内容/动作由 Debug-only、复用同一 `StatusMenuView` 的 `NSHostingController` 窗口执行；该宿主不得进入 Release，也不能冒充真实状态项点击和定位验收。
- Verification Experience: 严格交付必须组合 Core/PageRuntime fixtures、完整 XCUITest、Release resource/symbol/privacy/legacy scan 与 current ChatGPT `Page.createIsolatedWorld` live gate。live gate 只能输出 count/boolean，必须在 `finally` 卸载并证明 DOM/CSS、main world、observer、RAF 和 timer 恢复。

## Remaining Manual Acceptance

- 使用真实中文输入法确认组合输入期间 Enter 保护和组合结束后的普通 Enter。
- 在当前 ChatGPT 窗口人工确认宽屏、顶部避让、Markdown 色彩和 focus ring 的视觉可读性。
- 人工点击真实菜单栏状态项，确认多显示器下弹层位置与交互；自动 Debug 宿主不覆盖该项。
- 用户明确批准后验证运行中无 CDP 的真实重启路径、未发送内容处理和 `SMAppService.requiresApproval` 系统 UI。
- 安装/卸载到 `/Applications` 后验证登录项注销与正常重开 ChatGPT 无页面残留。

## Non-Distillation Content

> Content that should NOT enter long-term memory, with reasons — prevents accidental absorption of noise.

- `/private/tmp` 派生目录、xcresult 路径、target id、一次性的 selector 数量、实现/配置/source 指纹、ChatGPT 当前 build 和 Xcode TestingInterop 临时 runner 修复属于本次验收证据。长期只保留架构边界、动态回环/资格审查合同、配置事务、诊断隐私、adapter 隔离/清理、UI 测试边界与验证方法。

## Related Memories

- Predecessor: `SM-20260710-004`（ChatGPT Codex 兼容适配，建立旧 Shell/Node 时代的 app target 与 surface probe 基础；本任务已完成原生 V2 替换）。
- Related: `SM-019fc5a8-f783-78a3-880a-ca2a2ac96bbe`（当前 ChatGPT Markdown 根兼容取证；V2 将其收敛为独立语义主题 adapter）。
- Related: `SM-019fc5c8-55c1-72a5-b45b-37d2af6f3470`（当前 ChatGPT 唯一布局根取证；V2 将其收敛为 `header-offset` adapter）。
- Successor: none.
