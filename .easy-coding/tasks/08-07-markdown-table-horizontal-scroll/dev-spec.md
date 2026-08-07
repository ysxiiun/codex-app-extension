## 技术方案：Markdown 表格超宽时改为组件内水平滚动

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：宽屏布局启用时，Markdown 表格不得通过自身 wide-block 外壳撑破已配置的内容宽度；列内容超过可用宽度后，只在该表格组件内部横向滚动。
- **输入**：ChatGPT `app://-/index.html` 会话页、已启用扩展与宽屏布局、Markdown 响应中出现宽表格；表格可能包含长路径、代码或多列内容。
- **输出**：修改 PageRuntime 宽屏 adapter 及其兼容 revision、测试夹具和文档；交付可构建、安装并让表格外壳受正文宽度约束、超宽内容保留原生横向滚动的 macOS 应用代码。
- **边界**：不压缩整张表格、不强制断词或 nowrap、不修改单元格语义/配色、不读取表格内容、不插入或重排 DOM、不为表格增加独立配置开关；关闭宽屏后恢复 ChatGPT 原生表格布局。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`Adapters/wide-layout.js` 负责内容宽度变量和作用域样式，`bootstrap.js`/`CDPPageRuntimeBridge.swift` 负责热升级 revision，`AdapterFixtureTests.swift` 与 `current-surface.html` 负责页面回归，README/ABSTRACT 维护兼容合同。
- **当前实现方式**：wide-layout 将 `--markdown-wide-block-max-width` 写为有效内容宽度，但主动排除 selected Markdown subtree 和 markdown wide block，不对表格外壳做约束；当前 ChatGPT 自带稳定的 `[data-markdown-table]` 外壳与内部横向 scroller。
- **现有问题 / 缺口**：ChatGPT 当前表格外壳使用 `width: calc(100% + 2 × thread-content-margin)` 和负 inline margin，wide-block 模式又可扩大到 `--wide-block-default-max-width`。因此外层组件可以超过扩展设定的正文宽度；内部虽然已有 `overflow-x:auto`，但滚动边界本身也被放大，不能阻止组件越界。
- **证据**：`CodexAppExtension/Resources/Adapters/wide-layout.js:7-12` 写入 Markdown 宽度变量；`:22-41` 排除 Markdown subtree；`:112-135` 只生成 width owner 规则而没有表格 containment。`CodexAppExtension/Resources/Adapters/markdown-semantic-theme.js:72-85` 仅处理标题、强调、行内代码和引用外观。当前 `/Applications/ChatGPT.app/Contents/Resources/app.asar` 的本机资源包含稳定 `[data-markdown-table]`，原生 CSS 为表格外壳增加双侧 margin 宽度，同时其直接表格子树已有 `overflow-x:auto`。用户截图显示表格超过正文设定宽度。

### 冲突摘要
- 需求 vs RULES：无冲突；实现必须使用稳定结构标记、保持 adapter 可卸载，并补齐 PageRuntime、Release 与 live gate。
- 需求 vs ABSTRACT：存在待同步合同；ABSTRACT 当前只说明 Markdown wide width 变量，没有记录表格组件 containment。
- 需求 vs 现有代码：有冲突；现有 wide-layout 明确排除 Markdown subtree，未修正原生表格外壳的 margin overhang。
- Dev-Spec vs 现有代码：无未解决冲突；方案只为稳定 `[data-markdown-table]` 增加宽屏作用域 CSS，不改变宽度公式、DOM 或主题配置。

### Canonical Spec 来源
- **来源**：无。
- **选择任务 / 仓库**：无。
- **消费闭包**：无。
- **基线与冲突**：无。
- **待闭合 integration**：无。

### 影响面分析
- **涉及模块**：PageRuntime wide-layout、CDP bridge revision、PageRuntime fixture tests、产品与架构文档。
- **核心类 / 页面 / 接口**：`wide-layout.desiredStyleText()`、`CDPPageRuntimeBridge.implementationRevision`、`window.__codexAppExtensionV2.implementationRevision`、`AdapterFixtureTests`。
- **数据库变更**：无。
- **接口变更**：无用户配置或公开接口变化；内部 implementation revision 从 10 提升到 11。
- **关联历史任务**：`SM-019fc5a8-f783-78a3-880a-ca2a2ac96bbe`（Markdown selector 兼容）；`SM-019fda0c-9017-72d5-a414-01a80b272a95`（revision 10 宽屏连续收敛）。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/Resources/Adapters/wide-layout.js` | 修改 | 保持 UTF-8 | 在宽屏且 selected Markdown scope 内，用稳定 `[data-markdown-table]` 限制外壳为 100%，复用/加固直接表格子树的横向滚动。 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js` | 修改 | 保持 US-ASCII | implementation revision 升至 11，确保已打开 revision 10 页面热升级。 |
| `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift` | 修改 | 保持 UTF-8 | Swift bridge revision 同步升至 11。 |
| `CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | 修改 | 保持 UTF-8 | 更新 revision 合同断言。 |
| `PageRuntimeTests/Fixtures/current-surface.html` | 修改 | 保持 US-ASCII | 加入稳定 data attribute、外壳、scroller、wrapper 与 table 的本地结构夹具。 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持 US-ASCII | 回归表格 containment、内部 overflow、作用域隔离、幂等与卸载恢复；调整旧 margin 负向断言只约束 owner 规则。 |
| `README.md` | 修改 | 保持 UTF-8 | 说明宽屏下表格只在组件内部横向滚动。 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持 UTF-8 | 同步 revision 11 与稳定表格组件 containment 合同。 |

### 修改方案
- **总体改法**：不另造滚动容器；在 wide-layout 的 style node 中约束 `[data-selected-text-overlay-target] [data-markdown-table]` 外壳不超过当前 Markdown 宽度，并让其直接、包含 `table` 的原生子树保持 `overflow-x:auto`。
- **后端改动**：仅同步 Swift bridge implementation revision 与测试断言，不变更配置、事务或诊断模型。
- **前端改动**：表格外壳使用 `box-sizing:border-box`、`inline-size/max-inline-size:100%` 和 `margin-inline:0`；直接表格子树使用 `min-inline-size:0`、`max-inline-size:100%`、`overflow-x:auto`、`overflow-y:hidden` 与 inline overscroll containment。表格自身继续由 ChatGPT 使用 fit-content/列宽规则，不强制换行。
- **兼容处理**：只依赖当前稳定 `data-markdown-table` 和语义 `table`，不依赖 CSS module 哈希；选择器受 `.thread-scroll-container[data-cae-wide-layout='true']` 与 selected Markdown 双重门禁。旧宿主没有该标记时规则自然不命中；uninstall 移除/恢复 style node 后原生 margin 与 wide-block 行为自动恢复。
- **风险点**：错误地把 overflow 放在整个 Markdown root 会产生整段正文滚动；直接修改 table width 会破坏列宽和普通窄表；只覆盖 hashed scroller class 会在升级后失效；revision 不同步会让已打开页面继续使用旧 CSS。

### 实施拆解

| 单元 | 说明 | 类型 | 仓库 / 来源任务 / 步骤 | 涉及文件 / 符号 | 依赖 | 验收条件 | 测试点 / 命令 | 跨单元契约 |
|------|------|------|----------------------|-----------------|------|---------|---------------|-----------|
| U1 | 表格宽度 containment、revision 与回归合同 | frontend/runtime + test + docs | 当前仓库 / 无 / 无 | `wide-layout.js#desiredStyleText`、bootstrap/bridge revision、fixture、`AdapterFixtureTests`、README/ABSTRACT | — | 表格外壳不超过当前 Markdown 内容宽度；仅表格子树超宽时横向滚动；普通正文、输入框、right rail 与 Markdown 主题不受影响；关闭/卸载恢复原生；revision 11 热升级 | `node --check`；定向 `AdapterFixtureTests`/`PageRuntimeTests`/`CDPPageRuntimeBridgeTests`；全量 `ExtensionCoreTests`；Release install/sign/audit；live geometry gate | 稳定输入为 `[data-markdown-table]` + descendant `table`；输出只是一组受 wide-layout marker 门禁的 CSS 规则，不修改 DOM 或配置 |

**执行策略**：single
- 单一单元：U1 表格宽度 containment、revision 与回归合同。
- 由主 Agent 顺序完成 CSS、fixture/test、revision、文档、REVIEW 与 VERIFICATION，避免并行修改同一 revision 合同。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 表格外壳使用稳定 data attribute 且 containment 不依赖 CSS module hash | 必测 | U1 | PageRuntime fixture/XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/AdapterFixtureTests CODE_SIGNING_ALLOWED=NO` |
| 内部表格子树横向 overflow、正文/overlay 负向 scope、幂等与卸载恢复 | 必测 | U1 | PageRuntime fixture/XCTest | 同上，并执行 `PageRuntimeTests` |
| revision 11 跨 bootstrap/Swift bridge/测试一致且旧 runtime 可升级 | 必测 | U1 | Bridge/PageRuntime XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests -only-testing:ExtensionCoreTests/PageRuntimeTests CODE_SIGNING_ALLOWED=NO` |
| 全量 Core、Release 构建、签名、资源与差异检查 | 必测 | U1 | 最终门禁 | 全量 `ExtensionCoreTests`、`./install.sh`、`codesign --verify --deep --strict`、资源 SHA-256、`git diff --check` |
| 当前 ChatGPT 表格几何与滚动能力 | 应测 | U1 | 隐私安全 live CDP | 只读取 `[data-markdown-table]`/`table` 数量、rect、clientWidth/scrollWidth、computed overflow，不读取内容 |

- **人工验收**：在正式安装版本中打开一张超宽 Markdown 表格，确认表格右侧不越过正文配置边界、组件底部可水平滚动；窄表格、流式输出、右侧环境信息和输入框宽度保持正常；关闭宽屏后恢复原生布局。
- **无法验证项**：当前页面的表格已经被虚拟列表卸载；实现后若 live gate 仍无表格节点，最终真实视觉与滚动手感需用户在包含宽表格的页面验收。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：strict。
- **推荐并选择**：strict。
- **选择原因**：状态机按 8 个项目文件判定为 `broad-change-scope`；虽然行为局部，但涉及 PageRuntime 热升级 revision、当前宿主结构兼容、测试夹具和正式安装验证，错误会造成 Markdown 布局越界或旧页面不生效。
- **状态内执行差异**：IMPLEMENT 完成单一受控单元并先跑定向测试；REVIEW 检查 selector 作用域、原生行为恢复、宿主漂移和 revision 一致性；VERIFICATION 按冻结模式运行受影响或全量 Core/Release/live gate；MEMORY 仅保留稳定表格结构与 containment 合同。

### 风险与注意事项
- 必须使用稳定 `[data-markdown-table]`，禁止把当前 `_table*_<hash>_*` CSS module 类固化进产品 selector。
- overflow 只允许落在表格组件内部；不得使整个 selected Markdown root 或会话区域横向滚动。
