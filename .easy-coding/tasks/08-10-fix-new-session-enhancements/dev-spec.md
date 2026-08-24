## 技术方案：修复新建会话页增强功能整体失效

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：让新建会话空白页与已有会话页一样被 Codex App Extension 稳定捕获和持续处理，使宽屏、顶部避让、中文输入保护等已有能力按当前页面可用锚点正常工作，并在首条消息产生 thread/Markdown 后无缝恢复完整增强。
- **输入**：用户已启用扩展及相应功能；ChatGPT 主 target 为 exact `app://-/index.html`；新建会话页有唯一主布局与 composer，但没有 `.thread-scroll-container`，且当前宿主可能暂时缺少 `data-codex-composer="true"` 稳定标记。
- **输出**：改代码；统一 Swift target probe 与 PageRuntime 的两态 surface 身份，提供受限 composer 结构回退，修复 adapter 生命周期并提升 runtime revision，补齐自动化、文档与发布验证。
- **边界**：不读取欢迎文案、正文、草稿、Cookie 或完整 DOM；不以截图坐标或固定窗口尺寸识别页面；不把 layout-only 页面视为合格；不在空白页伪造不存在的 Markdown 正文主题效果；不修改 ChatGPT 包体、账号/会话数据、配置 schema 或产品开关。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`CDPPageRuntimeBridge.probe`、`TargetCoordinator` 的 `CodexSurfaceProbeResult.isCodexSurface`、`PageRuntime/bootstrap.js#surface`、`wide-layout.js#wideSurfaceState`、header/IME/Markdown adapters 及 PageRuntime fixtures。
- **当前实现方式**：Swift probe 已把 `layout=1, scroller=0, composer=1` 视为合法 target；wide-layout 另有空白页特例。但 PageRuntime 的 `surface.qualified` 仍只接受 `layout + thread scroller`，header 与 IME 因而统一等待；composer 在 Swift 与 JS 两侧都只通过带 `data-codex-composer="true"` 的 ProseMirror selector 识别。
- **现有问题 / 缺口**：同一个空白页在 target 层被定义为合法、在 runtime 层却被定义为不合格，导致 adapter 健康和重绑合同分裂；一旦空白页 composer 标记缺失或挂载时序变化，target probe、runtime editor 与 wide-layout 特例又会同时失去锚点，于是表现为所有增强整体失效。此前测试明确固化了“空白页只有 wide-layout 特例，其他 adapter 等待”的旧边界。
- **证据**：`CodexAppExtension/Core/CDP/TargetCoordinator.swift:36-47` 已接受唯一 composer 的空白形态；`CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift:147-171` 的 probe 只统计标记 composer；`CodexAppExtension/Resources/PageRuntime/bootstrap.js:54-100` 同样只认标记 editor，且第 88-90 行仍要求 thread scroller 才 qualified；`wide-layout.js:300-360` 把空白页放在 `surface.qualified == false` 特例中；`header-offset.js:72-80` 与 `ime-enter-guard.js:17-27` 都依赖 `surface.qualified`；`PageRuntimeTests/AdapterFixtureTests.swift:1690-1723` 规定空白页 adapter 等待，而 1726-1875 仅给 wide-layout 开例外。当前只读 live gate 证明已有会话为 exact target、revision 11、四 adapter healthy，但消息提交后页面已转为已有会话，不能用 live gate替代截图中的空白页证据。

### 冲突摘要
- 需求 vs RULES：无冲突；需要保持 exact target、唯一锚点、失败开放、隐私、完整卸载，并同步 README/ABSTRACT、全量 Core tests、Release 与只读 live gate。
- 需求 vs ABSTRACT：存在合同差异；ABSTRACT 当前明确规定 `runtime.surface().qualified` 只表示 layout + thread scroller，且除 wide-layout 外其他 adapter 在空白页等待，需要同步为两态 surface 与独立能力资格。
- 需求 vs 现有代码：存在已确认冲突；target identity、runtime surface identity 和 adapter capability 的定义不一致，空白页回退又依赖单一宿主标记。
- Dev-Spec vs 现有代码：无未解决冲突；方案在 exact URL、唯一 layout、无 scroller 的窄条件内引入唯一可见 ProseMirror fallback，并保留歧义/隐藏候选拒绝与 Markdown 无正文等待。

### Canonical Spec 来源
- **来源**：无。
- **选择任务 / 仓库**：无。
- **消费闭包**：无。
- **基线与冲突**：无。
- **待闭合 integration**：无。

### 影响面分析
- **涉及模块**：ExtensionCore CDP probe、PageRuntime surface/observer、wide-layout adapter、header/IME/Markdown 资格联动、Core/PageRuntime tests、README 与架构摘要。
- **核心类 / 页面 / 接口**：`CDPPageRuntimeBridge.probe`、`CodexSurfaceProbeResult.isCodexSurface`、`window.__codexAppExtensionV2.surface()`、`wideSurfaceState`、`header-offset#reconcile`、`ime-enter-guard#reconcile`、`markdown-semantic-theme#reconcile`。
- **数据库变更**：无。
- **接口变更**：内部 PageRuntime surface 合同变化；新增 `thread` / `empty-composer` 结构分类语义，配置 schema、公开 UI 和 envelope 字段不变。
- **关联历史任务**：`SM-019fda0c-9017-72d5-a414-01a80b272a95`（新建任务宽屏、owner 竞态与动态右栏连续收敛）；`SM-019fda3e-d44a-78cc-8ef4-a3d545953de9`（revision 11 Markdown 表格组件滚动）；`SM-019fc76b-6b2c-745d-9c4b-d08639bd0a68`（原生 PageRuntime V2）。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift` | 修改 | 保持原编码 UTF-8 | probe 优先稳定标记 composer，并仅在无 scroller 的唯一 layout 内提供安全 ProseMirror fallback；同步 runtime revision。 |
| `CodexAppExtension/Core/Runtime/RuntimeController.swift` | 修改 | 保持原编码 UTF-8 | 同一 target 导航后仅以专用 runtime-missing 信号触发 revision-safe 的重新 probe/install；普通轮询错误失败开放。 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js` | 修改 | 保持原编码 US-ASCII | 统一两态 surface 资格、结构分类、fallback editor 与 observer 属性；同步 runtime revision。 |
| `CodexAppExtension/Resources/Adapters/wide-layout.js` | 修改 | 保持原编码 UTF-8 | 按 threadScroller 是否存在选择会话/空白分支，并兼容空白页 composer/content 两类受限祖先 width owner。 |
| `CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | 修改 | 保持原编码 UTF-8 | 覆盖 selector 优先级、安全 fallback、count-only 隐私表达式与 revision。 |
| `CodexAppExtensionTests/PerformanceBudgetTests.swift` | 修改 | 保持原编码 UTF-8 | 同步 performance polling 的类型安全 envelope，并维持 observer 性能预算覆盖。 |
| `CodexAppExtensionTests/RuntimeReliabilityTests.swift` | 修改 | 保持原编码 UTF-8 | 覆盖 runtime-missing 恢复、普通错误零 probe/apply，以及 refresh/reconnect 迟到结果隔离。 |
| `PageRuntimeTests/PageRuntimeTests.swift` | 修改 | 保持原编码 UTF-8 | 覆盖两态 surface、无标记空白 fallback、session editor 可选兼容和 runtime 热升级。 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持原编码 US-ASCII | 覆盖空白页 wide/header/IME 生效、Markdown 等待、双向 SPA 切换、歧义与卸载恢复。 |
| `README.md` | 修改 | 保持原编码 UTF-8 | 更新 target/surface、adapter 能力、fallback、revision、测试与人工验收说明。 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8 | 按项目规则同步两态 surface、adapter 独立资格、observer 与 revision 架构合同；该文件是项目架构知识，不作为任务交付物计数。 |

### 修改方案
- **总体改法**：将页面身份统一为 `thread` 与 `empty-composer` 两种合格 surface：稳定 composer 标记优先；只有 exact target 的唯一 layout 内无 scroller 时，才允许唯一、非隐藏 ProseMirror editable 作为 fallback；各 adapter 再按自身能力决定 healthy 或 recoverable waiting。
- **后端改动**：`CDPPageRuntimeBridge.probe` 使用与 PageRuntime 等价的 count-only 候选算法，把最终有效 editor count 作为 `.composer` 计数交给现有 `CodexSurfaceProbeResult`。同 ID 页面导航若在 `targetInfoChanged` 的早期探测时 DOM 尚未就绪，bridge 的只读 performance envelope 会以专用 `runtimeUnavailable` 信号报告运行时/API 缺失，pipeline 才重新 probe/install；畸形快照、transport、protocol 与 stale 错误不得触发恢复。恢复前后校验 lifecycle generation、active target 与 per-target revision，迟到失败不得覆盖更新的 target 刷新。
- **前端改动**：`bootstrap.surface()` 返回两态资格与 editor 来源，空白页也 qualified；observer 绑定唯一 layout/editor 并监听最小资格属性。wide-layout 改为显式优先 thread 分支；空白页只在唯一 editor 到 layout 的祖先路径上选择 composer/content width token，CSS 只认 adapter 写给当前 editor 的 `data-cae-wide-layout-editor` 专用 marker；owner token 原地增删由 editor 到当前 scope 的有限 class 观察自动收敛；header 与 IME 通过统一 surface 自动恢复；Markdown 在无 scroller/candidate 时保持 waiting，出现正文后自动生效。
- **兼容处理**：已有会话仍以唯一 scroller 为身份，未标记 editor 继续只是 session 的可选能力，不启用 fallback；标记 composer 始终优先于结构 fallback；重复/隐藏 fallback 拒绝；revision 13 热升级先卸载 revision 12 或更旧实现的四 adapter 再补水；配置/envelope/UI 不变。
- **风险点**：fallback 过宽可能误认非 composer ProseMirror；扩大 `surface.qualified` 会改变 wide/header/IME/Markdown 的分支；SPA 复用节点和热升级可能留下状态；必须以结构反例、双向切换、卸载快照、性能预算和 Release 资源审计封锁。

### 实施拆解

| 单元 | 说明 | 类型 | 仓库 / 来源任务 / 步骤 | 涉及文件 / 符号 | 依赖 | 验收条件 | 测试点 / 命令 | 跨单元契约 |
|------|------|------|----------------------|-----------------|------|---------|---------------|-----------|
| U1 | 统一新建会话 surface 资格并恢复增强生命周期 | runtime + test + docs | 当前仓库 / 无 / 无 | bridge `probe`；pipeline `pollHealth`；bootstrap `surface/bindMutationObserver`；wide `wideSurfaceState`；相关 Core/PageRuntime tests；README/ABSTRACT | — | marked/fallback 空白页被捕获；早到 target 事件漏过 DOM 时由健康轮询恢复注入；wide/header/IME 生效；Markdown 无正文等待并在 thread 出现后恢复；歧义失败开放；迟到轮询不覆盖新 revision；双向 SPA 与卸载无残留；revision 一致 | 定向五组 XCTest；全量 `ExtensionCoreTests`；Release build；`install.sh --audit-only`；`git diff --check`；只读 live gate | exact target + 唯一 layout；`thread` 为唯一 scroller，`empty-composer` 为无 scroller且唯一安全 editor；runtime 缺失触发 revision-safe 恢复；adapter 独立资格与恢复 |

**执行策略**：single
- 主 Agent 直接完成 U1；不派发子 Agent，避免同一 surface 合同在 Swift/JS/tests/docs 间产生并行漂移。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| Target probe 接受 marked/fallback 空白 composer，拒绝 layout-only、重复/隐藏候选与错误 URL | 必测 | U1 | Core XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/TargetCoordinatorTests -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests CODE_SIGNING_ALLOWED=NO` |
| 空白页 composer/content 两类祖先 width owner 均实际命中宽屏 CSS，布局外或不含已确认 editor 的 owner 不命中 | 必测 | U1 | PageRuntime fixture XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/AdapterFixtureTests CODE_SIGNING_ALLOWED=NO` |
| PageRuntime 两态 surface、空白页 wide/header/IME、Markdown waiting、SPA 双向切换与卸载恢复 | 必测 | U1 | PageRuntime fixture XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/PageRuntimeTests -only-testing:ExtensionCoreTests/AdapterFixtureTests CODE_SIGNING_ALLOWED=NO` |
| 同 ID 导航的早到事件漏过 DOM 后，仅专用 runtime-missing 信号恢复 runtime；畸形/transport/stale 不恢复；迟到 poll 不覆盖更新 revision 或 reconnect | 必测 | U1 | Bridge + runtime reliability XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests -only-testing:ExtensionCoreTests/RuntimeReliabilityTests CODE_SIGNING_ALLOWED=NO` |
| 全量 Core、隐私、性能、生命周期与恢复回归 | 必测 | U1 | XCTest 回归 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-new-session test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO` |
| Release 构建、资源/签名审计、plist 与差异检查 | 必测 | U1 | 发布门禁 | Release `xcodebuild`；`./install.sh --audit-only <built-app>`；`plutil -lint`；`git diff --check` |
| 当前 exact target/runtime 未受回归 | 应测 | U1 | 非破坏只读 live gate | 仅读取 target/selector counts、revision/hydration、surface 分类与既有 performance snapshot |

- **人工验收**：正式安装后依次验证已有会话→新建会话→真实中文输入→发送首条消息→返回新建会话；确认宽屏/顶部/IME 在空白页工作，Markdown 在内容出现时工作，状态不再整体失效且无跳宽、重复偏移或误发送。
- **无法验证项**：当前任务提交后已不再停留在截图中的空白页；按隐私合同不能用 CDP 导航、发送或读取草稿，因此真实空白页视觉和中文输入手感需正式安装后由用户验收。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：strict
- **推荐并选择**：strict
- **选择原因**：状态 API 判定 `broad-change-scope` 与 `high-risk-contract-or-domain`；本修复跨 Swift target identity、PageRuntime surface、多个 adapter、热升级 revision、隐私和完整恢复边界，错误会造成误接管或整页增强再次失效。
- **状态内执行差异**：IMPLEMENT 按单一合同同步修改 Swift/JS/tests/docs并先跑定向测试；REVIEW 对 selector 误选、adapter 分支、SPA/卸载、隐私与性能作严格审查；VERIFICATION 运行全量 Core、Release/资源审计、静态门禁与只读 live gate；MEMORY 记录两态 surface 与 fallback 边界。

### 风险与注意事项
- composer fallback 必须限制为 exact target、唯一 layout、无 scroller、唯一且非隐藏 ProseMirror editable；不能退化为任意 contenteditable 或文案匹配。
- `surface.qualified` 扩展后 wide-layout 不能继续用其真假区分 thread/empty，否则会把空白页传入 null scroller 路径；必须显式按 `threadScrollerCount/threadScroller` 分支。
- 同 ID 页面导航会保留 active target，但重建 JavaScript 上下文；若唯一一次 `targetInfoChanged` 早于 DOM 就绪，不能永久信任旧 active 状态。只有 bridge 明确返回的 `runtimeUnavailable` 能触发重新 probe/install，并用捕获的 generation/revision 阻止迟到失败发起重复恢复；其他 poll 错误继续失败开放且不得写页面。
- Markdown 空白页没有可增强正文，正确状态是 recoverable waiting，而不是伪造 healthy；首条消息产生 scroller/candidate 后必须由 observer 自动恢复。
- implementation revision 必须在 bridge/bootstrap/tests/README/ABSTRACT 同步为 13，否则已打开页面可能继续复用 revision 12，出现“adapter 已改但页面仍执行旧注册对象”。
