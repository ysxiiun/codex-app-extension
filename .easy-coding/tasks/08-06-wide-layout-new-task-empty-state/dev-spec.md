## 技术方案：让宽屏布局在新建任务空白页持续生效

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：宽屏布局启用后，无论当前页面是已有会话、同窗口切换出的新建任务空白页，还是直接打开在新建任务空白页的新窗口，主输入区域都应立即采用同一套最大内容宽度与最小侧边距规则，消除页面切换时的宽度割裂。
- **输入**：用户已启用全局扩展和宽屏布局；ChatGPT target 为 `app://-/index.html`；页面可能只有唯一主布局根与唯一原生 composer，暂时还没有 `.thread-scroll-container`。
- **输出**：修改 ExtensionCore 的 target 资格合同、PageRuntime 宽屏 adapter 与实现 revision，并补齐自动化测试和项目文档；最终交付可重新构建、安装并在新建任务空白页生效的 macOS 应用代码。
- **边界**：不根据中文欢迎文案或视觉坐标识别页面；不把布局根单独视为合格 Target；不让 header、IME 或 Markdown adapter 在缺少各自锚点时强行生效；不改变右侧持久栏动态避让、最大宽度/最小侧边距公式、输入内容、配置 schema 或菜单 UI。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`TargetCoordinator`/`CDPPageRuntimeBridge` 的 surface probe、`PageRuntime/bootstrap.js`、`Adapters/wide-layout.js`、ExtensionCore 与 PageRuntime fixture tests。
- **当前实现方式**：Target 只有在唯一布局根内存在唯一 `.thread-scroll-container` 时才合格；wide-layout 也只有 `surface.qualified` 为真时才在该 scroller 内寻找 content/composer width owner，并把 marker 与 CSS 变量写到 scroller。
- **现有问题 / 缺口**：新建任务空白页已有唯一布局根和唯一 composer，但暂时没有 thread scroller，因此 target 可能无法在直接打开的新窗口中激活；已激活 target 内 SPA 切换到空白页时，wide-layout 会恢复自身样式并进入 recoverable waiting，导致输入框回到原生窄宽度。现有测试还把“空白页等待”作为所有 adapter 的共同预期，固化了该缺口。
- **证据**：`CodexAppExtension/Core/CDP/TargetCoordinator.swift:24` 将身份锚点固定为布局根与 thread scroller；`CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift:155-157` 仅以这两个锚点判定 probe；`CodexAppExtension/Resources/Adapters/wide-layout.js:690-730` 仅在 `surface.qualified` 时从 thread scroller 取 width owner；`PageRuntimeTests/AdapterFixtureTests.swift:1177-1200` 将空白页对所有 adapter 统一断言为等待；用户截图显示新建任务页输入框仍保持原生窄宽度。

### 冲突摘要
- 需求 vs RULES：无冲突；属于 PageRuntime/CDP 变化，必须同步 README/ABSTRACT、执行完整 Core tests 与非破坏 live gate。
- 需求 vs ABSTRACT：存在已知合同差异；ABSTRACT 当前规定 Target 必须有唯一 thread scroller、wide-layout 只写唯一 scroller，需要随实现更新为“唯一布局根 + 唯一内容锚点（thread scroller 或 composer）”及空白页 fallback。
- 需求 vs 现有代码：有冲突；现有代码将新建任务空白页设计为 recoverable waiting。
- Dev-Spec vs 现有代码：无未解决冲突；本方案显式替换上述旧合同，并保留唯一 selector、失败开放与 adapter 隔离原则。

### 影响面分析
- **涉及模块**：ExtensionCore CDP/Target、PageRuntime bootstrap、wide-layout adapter、ExtensionCoreTests、PageRuntimeTests、README/ABSTRACT。
- **核心类 / 页面 / 接口**：`CodexSurfaceProbeResult.isCodexSurface`、`TargetCoordinator.requiredAnchors`、`CDPPageRuntimeBridge.probe`、`wide-layout` 的 probe/reconcile/diagnose、PageRuntime implementation revision。
- **数据库变更**：无。
- **接口变更**：内部 surface 资格合同变化；配置和用户可见 API 无变化。
- **关联历史任务**：`SM-019fcfe3-0cfa-7d6b-987c-0edda8fb811c`（动态宽屏布局稳定修复）；`SM-019fd53f-8d9a-7886-be56-6aa8478898ca`（空白/欢迎页 recoverable waiting 合同）。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/Core/CDP/TargetCoordinator.swift` | 修改 | 保持原编码 US-ASCII | 将 Target 身份从固定 layout+scroller 改为唯一 layout + 唯一且非歧义的 scroller/composer 内容锚点联合判定。 |
| `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift` | 修改 | 保持原编码 UTF-8 | probe 返回空白页可判定的 count-only 资格结果，并提升实现 revision 常量。 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js` | 修改 | 保持原编码 US-ASCII | 提升 implementation revision，确保已注入旧 runtime 能完整卸载并加载新 adapter。 |
| `CodexAppExtension/Resources/Adapters/wide-layout.js` | 修改 | 保持原编码 US-ASCII | 在 scroller 缺失但 layout+composer 唯一时，以 layout root 作为临时宽屏作用域并对 composer width owner 应用同一夹取公式；thread 出现后无残留切换回 scroller。 |
| `CodexAppExtensionTests/TargetCoordinatorTests.swift` | 修改 | 保持原编码 UTF-8 | 覆盖空白页 target 合格、布局单独不合格、锚点歧义不合格和既有会话兼容。 |
| `CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | 修改 | 保持原编码 UTF-8 | 更新 revision 断言并验证 probe 保持 count-only/隐私边界且接受空白页结构。 |
| `PageRuntimeTests/PageRuntimeTests.swift` | 修改 | 保持原编码 US-ASCII | 更新 implementation revision 升级与幂等测试期望。 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持原编码 US-ASCII | 增加新建任务空白页 fixture 生命周期，验证宽屏立即生效、其他 adapter 仍等待、DOM 转换与卸载恢复。 |
| `README.md` | 修改 | 保持原编码 UTF-8 | 更新 Target 资格、空白页宽屏、revision 与失败开放说明。 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8 | 同步 CDP target 和 PageRuntime 模块合同。 |

### 修改方案
- **总体改法**：把“Target 是否属于 Codex 页面”和“某 adapter 当前能力是否就绪”拆开处理：Target 接受唯一主布局下的唯一 thread scroller 或 composer 作为内容身份；wide-layout 对会话页继续使用 scroller，对空白页仅回退到唯一布局根内的 composer width owner。
- **后端改动**：ExtensionCore 的 count-only probe 与 `CodexSurfaceProbeResult` 支持两种合法形态：`layout=1, scroller=1` 的会话页，或 `layout=1, scroller=0, composer=1` 的空白页；任何布局/内容锚点歧义仍拒绝。
- **前端改动**：wide-layout 引入动态 scope：优先唯一 thread scroller，否则在唯一 layout root + 唯一 composer 下选择 layout root；样式 selector 同时支持两种 marker scope，几何参考在空白页使用 layout root，在会话出现后恢复现有 scroller/right-rail 计算。
- **兼容处理**：既有会话页路径、右栏动态避让、owner 去重、流式文本负向 scope 和完整卸载合同不变；implementation revision 提升保证旧注入代码被替换；其他 adapter 保持自身资格条件，不因 Target 放宽而误注入。
- **风险点**：Target 资格放宽可能误选非会话页面；layout-root scope 可能扩大 CSS 继承范围；SPA 从空白页转为会话页时 target/owner/observer 切换可能残留属性或短暂跳动；必须用歧义反例、切换收敛和卸载快照测试封锁。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 扩展空白页 Target 身份合同 | backend/core | `TargetCoordinator.swift`, `CDPPageRuntimeBridge.swift`, `TargetCoordinatorTests.swift`, `CDPPageRuntimeBridgeTests.swift` | — | 直接打开的空白任务页可激活；布局单独、重复 composer/scroller 或错误 URL 仍不合格；probe 不读取正文/输入值 | TargetCoordinator 与 bridge 定向单测、隐私表达式断言 | 输出 counts；合格条件为唯一 layout 且存在一个唯一非歧义内容锚点 |
| U2 | 让 wide-layout 在空白页与会话页连续收敛 | frontend/runtime | `bootstrap.js`, `wide-layout.js`, `PageRuntimeTests.swift`, `AdapterFixtureTests.swift` | U1 | 空白页 composer 立即应用配置宽度/边距；切换到会话页不闪回、不残留旧 scope；关闭/卸载完全恢复 | 空白 fixture、空白→会话、会话→空白、幂等、observer/performance、卸载恢复 | 消费 U1 的合法空白页形态；其他 adapter 的 `surface.qualified` 语义不变 |
| U3 | 同步产品与架构合同 | docs | `README.md`, `.easy-coding/ABSTRACT.md` | U1, U2 | 文档准确描述两种 Target 形态、adapter 隔离、空白页 fallback 和新 revision | 文档搜索、`git diff --check` | 与 U1/U2 最终实现一致 |

**执行策略**：sequential
- 第一批：U1 扩展空白页 Target 身份合同
- 第二批：U2 让 wide-layout 在空白页与会话页连续收敛
- 第三批：U3 同步产品与架构合同

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| Target 接受 layout+composer 空白页并拒绝布局单独/重复锚点 | 必测 | U1 | XCTest 单测 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-tests test -only-testing:ExtensionCoreTests/TargetCoordinatorTests -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests CODE_SIGNING_ALLOWED=NO` |
| 空白页宽屏立即生效且切换/卸载收敛 | 必测 | U2 | PageRuntime fixture/XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-tests test -only-testing:ExtensionCoreTests/AdapterFixtureTests -only-testing:ExtensionCoreTests/PageRuntimeTests CODE_SIGNING_ALLOWED=NO` |
| 全量 Core、PageRuntime、隐私、性能与恢复回归 | 必测 | U1/U2/U3 | XCTest 回归 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-tests test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO` |
| Release 构建、资源、plist、签名扫描与差异检查 | 必测 | U3 | 发布门禁 | `./install.sh --dry-run`、`plutil -lint CodexAppExtension/Supporting/Info.plist`、`git diff --check`（以仓库现有安装/验证入口实际参数为准） |
| 当前 ChatGPT exact target/surface/runtime 状态 | 应测 | U1/U2 | 非破坏只读 live gate | 仅读取 target 数量、selector counts、runtime handshake/hydration 与 performance snapshot；不执行 adapter 生命周期操作 |

- **人工验收**：启用宽屏后依次验证已有会话→新建任务空白页→发送首条消息/进入会话，输入框及内容宽度保持连续；新开一个直接落在新建任务页的窗口也立即宽屏；打开/关闭右侧持久栏仍动态居中；关闭宽屏后恢复原生布局。
- **无法验证项**：自动化可验证结构、状态和样式合同；ChatGPT 当前真实版本的最终视觉连续性仍需用户在正式安装包上验收，live gate 不允许修改当前页面或读取内容。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：strict
- **推荐并选择**：strict
- **选择原因**：改动覆盖 10 个项目文件，并变更跨 ExtensionCore/PageRuntime 的 Target 身份与 runtime revision 合同；错误可能导致 target 误选、增强不注入或布局残留，属于 broad-change-scope 与高风险内部协议边界。
- **状态内执行差异**：IMPLEMENT 按 U1→U2→U3 顺序并在每单元后运行定向测试；REVIEW 独立审查 target 误选、adapter scope/恢复、隐私与性能回归；VERIFICATION 运行全量 ExtensionCoreTests、Release/资源/签名门禁及允许范围内的只读 live gate；MEMORY 记录新的空白页 Target 与 wide-layout fallback 合同。

### 风险与注意事项
- 不能简单把 `layoutRoot === 1` 作为 Target 资格，否则设置页或过渡壳可能误选；必须要求唯一且非歧义的 composer/thread 内容锚点。
- 空白页的 CSS marker 只能落在唯一主布局根，width owner 仍必须经过既有排除规则，禁止影响菜单、浮层、right rail、ProseMirror 文本叶节点或其他主布局子树。
- scope 从 layout root 与 thread scroller 之间转换时必须先恢复旧 marker、变量和 owner offset，再应用新 scope，并维持 observer/RAF/timer 上限。
- implementation revision 必须同步 Swift 常量、bootstrap、测试和文档，否则旧 runtime 会重复复用旧 adapter，造成“代码已安装但页面仍无变化”。
