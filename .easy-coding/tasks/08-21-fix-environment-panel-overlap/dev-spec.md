## 技术方案：修复 ChatGPT 更新后宽屏内容与环境信息重叠

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：ChatGPT 新版右侧“环境信息”展开时，宽屏正文、输入区与 Markdown 宽块必须继续以右栏左边界为可用区域右界，不再伸入面板下方；右栏关闭后恢复完整可用宽度。
- **输入**：用户截图中的真实重叠现象；当前 ChatGPT `app://-/index.html` 页面；ChatGPT 151.0.7922.170 安装包中的新版 thread summary panel 结构；现有宽屏配置。
- **输出**：修改 PageRuntime 宽屏 adapter、回归测试、runtime revision 与合同文档，构建并安装经验证的 Codex App Extension；最终由 count-only live gate 与用户视觉确认共同验收。
- **边界**：不读取对话正文、草稿、Cookie 或 payload；不重启 ChatGPT、不点击或代替用户展开面板；不放宽为任意右侧浮层，不改变菜单/listbox/dialog 等瞬态浮层的原生布局；不改宽屏配置模型和 UI。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`CodexAppExtension/Resources/Adapters/wide-layout.js` 的 persistent rail 识别、几何快路径与 observer；`PageRuntimeTests/AdapterFixtureTests.swift` 的 rail fixture；PageRuntime revision 桥接；README/ABSTRACT 合同。
- **当前实现方式**：adapter 先按 `thread-floating-content-*` 稳定壳定位右栏，再只把具有背景色、边框或阴影且整条可见链成立的后代视为已渲染组件；普通 animation-frame 在 rail shell/祖先身份未变化且扩展属性未漂移时走快路径。
- **现有问题 / 缺口**：ChatGPT 新版保持透明 shell 节点不变，仅在展开时给一个透明、300px 宽的占位节点同时设置 `data-pip-home-surface="thread-summary-panel"` 与 `data-pip-obstacle="thread-summary-panel"`，面板动画发生在 shell 后代。现有 painted-only 判定漏掉此明确占位；rail 后代变化又可能被 ordinary identity 快路径吞掉，因此宽屏仍按整页右界计算并与环境信息重叠。
- **证据**：`wide-layout.js:18-22,185-266,415-435,455-544,620-721,910-935`；`AdapterFixtureTests.swift:566` 起的 rail fixture；`bootstrap.js:5`、`CDPPageRuntimeBridge.swift:92` 与 `CDPPageRuntimeBridgeTests.swift:8` 当前均为 revision 13；ChatGPT 静态资源 `/Applications/ChatGPT.app/Contents/Resources/app.asar` 内 `webview/assets/app-initial-B2RlNf_b.js@9746224-9748051` 明确显示 `shouldShow` 同时控制两个 PIP 属性、300px 占位、后代 opacity/translate/scale；只读 live probe 证明旧 shell 选择器仍唯一命中，关闭态两个 PIP 属性计数均为 0。

### 冲突摘要
- 需求 vs RULES：无冲突；按 PageRuntime 独立 adapter、完整恢复、有限 observer、隐私安全 live gate 执行。
- 需求 vs ABSTRACT：无冲突；修复继续遵守“稳定 shell + 已渲染组件几何、不读业务文本”的既有合同，并把宿主显式 PIP obstacle 纳入已渲染占位语义。
- 需求 vs 现有代码：存在兼容缺口；painted-only 与 shell-only ordinary identity 不覆盖新版透明语义占位及后代动画。
- Dev-Spec vs 现有代码：有计划内差异；实现后由 revision 15、fixture 与文档同步闭合。

### 决策闭环
decision_status: closed
- **已解决问题与结论**：① 不是旧 rail class 改名，旧壳仍唯一命中；② 不以“环境信息”文本、行数、aria-label 或宽泛几何猜测识别，改用宿主同时提供的 `thread-summary-panel` PIP home/obstacle 双属性；③ PIP 双属性只在展开态存在，因此关闭壳不占宽，展开态立即占 300px；④ rail 子树属性/动画变化必须绕过 ordinary fast path 并在最终帧重算，避免展开漏算或关闭后永久留白；⑤ live gate 进一步证明宿主会把底部 composer 行选成布局参考矩形，因此精确 PIP obstacle 只要求与稳定 rail shell 纵向相交，普通 painted component 仍要求与布局参考相交；⑥ adapter 资源变化按仓库合同统一升级 runtime revision 13→15；⑦ 当前任务不是 Canonical 任务，无需额外产品决策。
- **确认依据**：用户截图与修复请求；当前代码和既有 right-rail 合同；ChatGPT 安装包静态实现；隐私安全 selector/count live probe；短期记忆 SM-019fcfe3 与 SM-019fda0c 的稳定壳、实际占位、瞬态排除及 live 验收约束。

### Canonical Spec 来源
- **来源定位**：无，本任务为当前仓库普通 bugfix。
- **设计 / 文档摘要**：无。
- **共享执行状态**：无。
- **选择任务 / 仓库**：无。
- **消费闭包**：无。
- **基线与冲突**：无。
- **待闭合 integration**：无。

### 影响面分析
- **涉及模块**：PageRuntime `wide-layout` adapter、JavaScript fixture tests、CDP runtime revision handshake、README 与项目架构摘要。
- **核心类 / 页面 / 接口**：`persistentRailRecords`、`ordinaryIdentity`/reconcile fast path、rail MutationObserver/motion listener、`AdapterFixtureTests`、`CDPPageRuntimeBridge.implementationRevision`。
- **数据库变更**：无。
- **接口变更**：无外部接口变更；内部 PageRuntime implementation revision 从 13 提升到 14。
- **关联历史任务**：SM-019fcfe3-0cfa-7d6b-987c-0edda8fb811c；SM-019fda0c-9017-72d5-a414-01a80b272a95。

### 改动范围
> 只列真实项目源码/配置文件的改动。任务目录中的 dev-spec、execution、test-strategy 不计入源码范围。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/Resources/Adapters/wide-layout.js` | 修改 | 保持原编码 UTF-8 | 识别 active thread-summary PIP obstacle；观察 PIP 属性；rail 后代 mutation/motion 标记几何脏并绕过快路径，完整重算后清理 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持原编码 UTF-8 | 模拟新版透明 stable shell + PIP obstacle，覆盖关闭、展开、关闭及 observer/filter/清理合同 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js` | 修改 | 保持原编码 UTF-8 | implementation revision 13→15 |
| `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift` | 修改 | 保持原编码 UTF-8 | Swift bridge 期望 revision 13→15 |
| `CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | 修改 | 保持原编码 UTF-8 | revision 断言同步到 14 |
| `README.md` | 修改 | 保持原编码 UTF-8 | 同步新版 PIP obstacle 占位、rail 子树收敛与 revision 15 用户合同 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8 | 同步 PageRuntime 架构合同与 revision 15 |

### 修改方案
- **总体改法**：在既有 stable rail shell 范围内，把宿主明确标记为 `thread-summary-panel` 的 PIP home/obstacle 双属性节点视为有效几何占位；该精确 obstacle 使用 rail shell 的纵向占位合同，避免被底部 composer 参考矩形误排除；同时让 rail 子树变化强制完成一次几何重算，不改变其他浮层分类。
- **后端改动**：仅同步 Swift bridge 的内部 implementation revision 常量与对应测试；不涉及业务后端。
- **前端改动**：新增精确 semantic obstacle 判定；rail MutationObserver 增加两个 PIP attribute；rail mutation/motion 设置有界 dirty 状态，禁止 ordinary fast path 吞掉该轮，完整 reconcile 后清除。
- **兼容处理**：保留旧版 painted component 几何路径，继续支持短空态卡片；新路径只接受同一节点上的 thread-summary 双属性，不增加文本、业务 testid、任意 aside 或右侧几何 fallback。
- **风险点**：若 dirty 标记未在完整 reconcile 后清理会增加几何读；若关闭动画最终帧仍被快路径跳过会残留右侧空白；若只认单个 PIP 属性可能误收瞬态组件。

### 实施拆解

| 单元 | 说明 | 类型 | 仓库 / 来源任务 / 步骤 | 涉及文件 / 符号 | 依赖 | 验收条件 | 测试点 / 命令 | 跨单元契约 |
|------|------|------|----------------------|-----------------|------|---------|---------------|-----------|
| U1 | 修复新版环境信息 PIP 占位识别并同步 runtime 合同 | frontend/runtime+test+docs | 当前仓库 / 无 / 无 | `wide-layout.js#persistentRailRecords/ordinaryIdentity/handleGeometryMutations/handleGeometryMotion/reconcile`；`AdapterFixtureTests`；revision 三处；README/ABSTRACT | — | 关闭态 `rightRail=false` 且使用完整宽度；添加 PIP 双属性后 `rightRail=true`、rightBoundary 落在 rail 左边；移除双属性并结束动画后恢复完整宽度；旧 painted rail、短空态及瞬态排除不回归；revision 15 五处一致 | 定向 AdapterFixture/CDP bridge；全量 ExtensionCoreTests；JS syntax、diff lint、Release build/安装审计；count-only live gate | 输入为 stable shell 与宿主 PIP 双属性，输出为动态 right boundary；无外部接口 |

**执行策略**：single
- 由主 Agent 按 U1 单元直接执行；这是一个共享 `wide-layout` 状态机和 revision 合同，不拆分并行写入。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 新版 PIP obstacle 的关闭→展开→关闭几何收敛，含快路径与 observer filter | 必测 | U1 | JavaScriptCore fixture/XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-environment-panel test -only-testing:ExtensionCoreTests/AdapterFixtureTests CODE_SIGNING_ALLOWED=NO` |
| runtime revision 15 桥接与旧 runtime 升级合同 | 必测 | U1 | XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-environment-panel test -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests CODE_SIGNING_ALLOWED=NO` |
| 既有 PageRuntime、observer、性能、隐私与恢复回归 | 必测 | U1 | 全量 Core/XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-environment-panel test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO` |
| 资源语法、文档/代码 revision 一致与 diff 质量 | 必测 | U1 | 静态检查 | `node --check CodexAppExtension/Resources/Adapters/wide-layout.js && node --check CodexAppExtension/Resources/PageRuntime/bootstrap.js && git diff --check` |
| Release 产物、安装审计、资源一致与运行存活 | 必测 | U1 | 构建/安装 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Release -destination 'platform=macOS' build`，随后使用仓库 `install.sh` 的既有安全入口安装并审计 |
| 当前 ChatGPT exact target、PIP selector、runtime/adapter 健康及展开几何 | 应测 | U1 | 只读 count-only CDP + 人工视觉 | 禁止读取正文/草稿；用户保持环境信息展开时核对 PIP 双属性唯一命中、rail 左边界与应用后的 rightBoundary/offset |

- **人工验收**：正式安装后保持宽屏开启，展开“环境信息”确认正文/输入区不进入面板下方；关闭后确认内容恢复完整宽度；缩放窗口与重复开关一次确认无残留留白或跳动。
- **无法验证项**：用户未保持面板展开时，自动 live gate 只能证明关闭态与 runtime 健康，不能替代展开态像素级视觉验收；不会为此自动点击 UI 或重启 ChatGPT。

### Workflow Mode
- **项目配置**：adaptive。
- **Session 覆盖**：无。
- **机械最低模式**：fast；state API 原因 `single-bounded-unit`（单仓、1 个单元、7 个文件、无公共接口）。
- **推荐并选择**：standard。
- **选择原因**：范围虽小，但属于当前 ChatGPT 版本兼容、动画生命周期与几何快路径的有界联动修复，并要求 runtime revision、完整回归、Release 安装和 live 边界验证；Standard 能覆盖受影响面而无需 Strict 的多仓/高风险深度。
- **状态内执行差异**：IMPLEMENT 单元内完成 adapter、fixture、revision 和文档同步；QUALITY 运行受影响与全量 ExtensionCoreTests、静态/Release/安装门禁并做 correctness/compliance review；MEMORY 记录新版 PIP obstacle 结构和验证边界。

### 风险与注意事项
- ChatGPT DOM 仍属外部宿主兼容面；只绑定安装包可证明的双属性语义，不猜测文本或宽泛容器。
- 必须同时证明展开会避让、关闭会释放；只测最终展开状态会漏掉 fast-path/动画结束残留。
- 当前工作树已有大量用户/前序 Harness 与 runtime 改动，实施只追加本任务最小修改，不回退、不重写无关差异。
- 自动 live 检查严格保持 count-only/read-only；最终视觉结论需用户在真实窗口确认。
