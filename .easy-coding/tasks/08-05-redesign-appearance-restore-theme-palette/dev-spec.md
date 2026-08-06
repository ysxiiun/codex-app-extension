## 技术方案：彻底清理 Tab 缩进功能残留

### 项目模式
迭代项目

### 任务类型
重构 / Bug 修复 / 前端设计实现

### 需求解析
- **目标**：不恢复 Tab 缩进开关，彻底删除插件中仍可见或仍参与迁移、注册判断、测试与文档的 Tab 功能残留。
- **输入**：用户发现输入设置页仍展示“Tab 键”说明，先要求开关，确认功能无实际价值后明确改为完整移除且不留残余逻辑。
- **输出**：改代码；输入设置页只保留中文输入保护，产品代码、迁移特殊名单、测试夹具、UI 测试和发布文档不再包含 Tab 缩进能力或 tombstone。
- **边界**：不改变 ChatGPT/macOS 原生 Tab 行为；不增加任何 Tab 键监听；不修改 IME Enter 防护；不恢复焦点着色；不更改 schemaVersion、现有四个 PageRuntime adapter 或已安装 revision 6 的运行时行为。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`InputSettingsView`、`FeatureRegistry`、`LegacyConfigMigrator`、V1 迁移 fixture、Configuration/PageRuntime/Settings UI tests、README 和架构摘要。
- **当前实现方式**：运行时和配置模型已没有 Tab adapter/字段，但设置页仍展示说明；FeatureRegistry 保留 removed qualification tombstone；迁移器把 `tabIndentEnhancement` 特判为 deprecated；多个测试和文档继续固化“已移除 Tab”的负向合同。
- **现有问题 / 缺口**：功能虽不执行，但仍在 UI、迁移分支、公共辅助类型、测试与文档中占据产品认知和维护成本，不满足“彻底移除，不留残余逻辑”。
- **证据**：`CodexAppExtension/App/Settings/InputSettingsView.swift:12` 可见 Tab 分区；`CodexAppExtension/Core/Features/FeatureRegistry.swift:141` 有仅服务资格说明的类型且 `:179` 含 `tab-indent` tombstone；`LegacyConfigMigrator.swift:90` 特判旧键；`SettingsUITests.swift:40` 固化可见说明；`ConfigurationTests.swift:30,139`、`AdapterFixtureTests.swift:1362`、`PageRuntimeTests.swift:159` 固化负向 schema/resource 行为；`config-v1.json:7`、README 和 ABSTRACT 仍含功能名称。

### 冲突摘要
- 需求 vs RULES：无冲突；删除无运行价值的功能残留，并保持 Swift 6、差异写入、adapter fail-open 和测试门禁。
- 需求 vs ABSTRACT：有计划内冲突；ABSTRACT 当前声明 Tab 已废弃，本次连废弃说明本身也从产品架构文档移除。
- 需求 vs 现有代码：有明确差距；运行时已删除，但 UI、迁移、测试和文档未完全清理。
- Dev-Spec vs 现有代码：有计划内变更；删除 Tab 专属 tombstone/fixture/assertion，保留四 adapter、IME 和原生宿主行为。

### 影响面分析
- **涉及模块**：SwiftUI 输入设置、ExtensionCore feature/migration 辅助逻辑、迁移 fixture、Core/PageRuntime/UI tests、发布与架构文档。
- **核心类 / 页面 / 接口**：`InputSettingsView`、`FeatureRegistry`、`FeatureQualificationDecision`、`LegacyConfigMigrator`、`ConfigurationTests`、`AdapterFixtureTests`、`PageRuntimeTests`、`SettingsUITests`。
- **数据库变更**：无。
- **接口变更**：删除未被产品运行时消费的 `FeatureQualificationDecision` 和 `FeatureRegistry.qualificationDecisions` 内部公开辅助 API；配置 schema 与 PageRuntime envelope 不变。
- **关联历史任务**：当前任务 `08-05-redesign-appearance-restore-theme-palette` 的已验证实现；其余无。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/App/Settings/InputSettingsView.swift` | 修改 | 保持 UTF-8 | 删除 Tab 分区、说明、图标、Divider 和 accessibility identifier。 |
| `CodexAppExtension/Core/Features/FeatureRegistry.swift` | 修改 | 保持 UTF-8 | 删除 Tab removed tombstone，并删除已无消费者的 qualification decision 辅助类型/数组。 |
| `CodexAppExtension/Core/Configuration/LegacyConfigMigrator.swift` | 修改 | 保持 UTF-8 | 取消对 `tabIndentEnhancement` 的专属 deprecated 分类。 |
| `CodexAppExtensionTests/Fixtures/config-v1.json` | 修改 | 保持 UTF-8 | 从迁移 fixture 删除旧 Tab 字段。 |
| `CodexAppExtensionTests/ConfigurationTests.swift` | 修改 | 保持 UTF-8 | 删除 Tab 专属 schema/迁移断言。 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持 UTF-8 | 删除 removed-Tab 专属 fixture 测试。 |
| `PageRuntimeTests/PageRuntimeTests.swift` | 修改 | 保持 UTF-8 | 删除 Tab registration/resource/tombstone/schema 断言并重命名测试。 |
| `CodexAppExtensionUITests/SettingsUITests.swift` | 修改 | 保持 UTF-8 | 输入页改为只验证 IME 控件，不再验证 Tab 说明。 |
| `README.md` | 修改 | 保持 UTF-8 | 删除所有 Tab 能力、迁移与已移除清单说明。 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持 UTF-8 | 删除架构层 Tab 说明，保留焦点着色与原生宿主边界。 |

### 修改方案
- **总体改法**：从可见 UI 向下清理 Tab 专属说明、tombstone、迁移特判、fixture、测试和文档，最终产品树只保留 IME 输入保护，不实现任何 Tab 逻辑。
- **后端改动**：删除资格决策辅助 API 和 legacy Tab 特判；未知旧字段仍按迁移器通用 unknown 路径安全处理，不进入 V2 配置。
- **前端改动**：输入页移除 Tab 整个分区及分隔线，只保留中文输入保护 Toggle。
- **兼容处理**：现有 V2 配置从未编码 Tab 字段，无数据迁移；真实旧 V1 配置若含该键，将被通用 unknown 处理并继续不写入 V2。
- **风险点**：删除公共辅助类型后的编译引用；UI 测试仍按旧文案查找；迁移测试 entry 数/分类变化；误删 IME keydown 逻辑或原生焦点相关系统行为。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U9 | 产品与迁移残留清理 | frontend/backend/docs | InputSettingsView、FeatureRegistry、LegacyConfigMigrator、config-v1 fixture、README、ABSTRACT | — | UI 和产品/迁移代码无 Tab 专属入口或分支；四 adapter 与 IME 行为不变 | 编译、文本扫描、迁移定向测试 | 不新增配置字段或 listener；未知 legacy 字段走通用路径 |
| U10 | 测试合同收敛 | test | ConfigurationTests、AdapterFixtureTests、PageRuntimeTests、SettingsUITests | U9 | 测试不再固化 Tab tombstone/说明，仍覆盖 IME 输入页、四 adapter 与焦点删除边界 | 定向 Core/PageRuntime/UI 测试 | 测试只验证现有能力，不保留被删除功能名称 |

**执行策略**：sequential
- 第一批：U9 产品与迁移残留清理
- 第二批：U10 测试合同收敛

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 产品树无 Tab 专属残留 | 必测 | U9 | 静态扫描 | `rg -n 'tab-indent|tabIndentEnhancement|settings\.input\.nativeTab|Tab 缩进|Tab 键' CodexAppExtension CodexAppExtensionTests PageRuntimeTests README.md .easy-coding/ABSTRACT.md` 期望无结果 |
| 配置迁移与注册表编译回归 | 必测 | U9/U10 | XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests/ConfigurationTests -only-testing:ExtensionCoreTests/PageRuntimeTests` |
| IME 输入页与事件保护不回归 | 必测 | U10 | XCTest/XCUITest | AdapterFixture IME tests + Settings 输入页导航 |
| 全量 Core/PageRuntime | 必测 | U10 | XCTest | `xcodebuild ... test-without-building -only-testing:ExtensionCoreTests` |
| Release 安装 | 必测 | U9/U10 | 构建签名审计 | `./install.sh` |

- **人工验收**：设置 > 输入只显示“中文输入保护”，不再显示 Tab 标题、说明或开关；ChatGPT 原生 Tab 行为不由扩展接管。
- **无法验证项**：XCUITest 若受 macOS Accessibility runner 阻断，保留 Core/编译/静态扫描与人工界面验收证据，不把环境失败伪装为通过。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：strict
- **推荐并选择**：strict
- **选择原因**：当前任务已冻结 Strict；本次删除涉及 SwiftUI、ExtensionCore 辅助 API、legacy 迁移、测试与发布文档，必须重新 REVIEW、全量验证和安装。
- **状态内执行差异**：IMPLEMENT 顺序处理 U9/U10 并定向测试；REVIEW 两路独立审查 correctness/contracts 与 compliance/tests/security；VERIFICATION 执行静态扫描、全量 139+ tests、Release 安装和只读 live CDP；MEMORY 记录最终删除边界。

### 风险与注意事项
- 不得为了证明删除而新增新的 Tab tombstone、marker、listener 或配置字段。
- 不得误删 IME Enter window-capture 修复、焦点着色退役清理或四 adapter 注册。
