## 技术方案：重构 Codex App Extension 为 macOS 菜单栏运行时 V2

### 项目模式
迭代项目；本任务是经用户批准的替换式架构升级，最终发布树只保留 Swift＋JavaScript V2。

### 任务类型
重构 + 新功能 + 前端设计实现。

### 需求解析
- **目标**：解决 ChatGPT/Codex 频繁升级后现有 CDP 注入工具静态验证全绿却持续局部失效、生命周期不能自恢复、配置不可视和单文件耦合过重的问题；一次性交付原生 macOS 菜单栏 App、设置窗口、重构后的运行时、功能重新准入、V1 配置迁移、诊断和旧链路清理。
- **输入**：用户批准的 `.easy-coding/spec/codex-menu-bar-runtime-v2-design.md`；当前 `/Applications/ChatGPT.app` `26.727.51351`（build `6119`，bundle id `com.openai.codex`）；现有 `~/.codex-app-extension/config.json`；当前未提交的两项 `26.727.51351` 兼容修复和 Harness 变更。
- **输出**：改代码；新增可构建、可运行、可登录启动、默认无 Dock 图标的 `Codex App Extension` macOS App，完成 Swift 运行时、Browser 级 CDP、独立页面 adapters、菜单栏四态、五页设置、配置事务、V1→V2 迁移、脱敏诊断、完整自动/live 验证，并在绿色切换后删除旧 Shell/Node 产品链。
- **边界**：不修改 ChatGPT 包体、签名、账号、Cookie、对话、输入或历史；不静默重启 ChatGPT；不支持旧独立 `Codex.app`、旧 selector/CLI/`CODEX_WIDE_*` 运行时；不引入云、账号、Codex Plugin、MCP、App Server 会话管理、公开市场或自动更新后台；不回滚当前任务外的工作树改动。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`inject-wide-layout.mjs` 同时负责 CLI、配置、CDP、surface、布局、输入、主题和诊断；`lib/runtime.sh`、`launch.sh`、`inject-current.sh` 负责应用/Node/端口和一次性注入；`verify.sh` 是零依赖验证入口；`README.md`、`.easy-coding/ABSTRACT.md` 描述旧架构。
- **当前实现方式**：固定默认端口 `9229`，Node 连接 page WebSocket，以 `Runtime.evaluate` 注入一个巨大的页面源码；根级 observer 和多轮刷新维持布局；JSON 配置、环境变量、CLI 和作者软链共同决定选项；应用未带 CDP 时由 Shell 在确认后强制重启。
- **现有问题 / 缺口**：核心和验证脚本分别达到 3578/2872 行；页面逻辑依赖动态类名、几何、文本信号、根级 mutation 和全 DOM 扫描；target 生命周期和 app 重启不能由常驻进程恢复；配置无 schema/事务/迁移/last-known-good；静态 anchor/字符串测试曾漏掉真实 `.main-surface` 移除；新版已原生覆盖长文本 Cmd+Enter 等功能；没有菜单栏、设置、登录启动或可消费的 adapter 健康模型。
- **证据**：`inject-wide-layout.mjs:12-29` 固定端口和混合新旧 selector；`inject-wide-layout.mjs:201-268` 一次性 target/page 注入；`inject-wide-layout.mjs:271-638` 把配置、环境变量和功能解析留在同一文件；`inject-wide-layout.mjs:807-891` 仅连接选中的 page WebSocket；`inject-wide-layout.mjs:1530-1706` 使用文本、动态类名和几何识别浮层；`inject-wide-layout.mjs:2023` 存在 `document.body.querySelectorAll("*")`；`inject-wide-layout.mjs:2398-2535` 根级 observer 和多轮刷新；`verify.sh:1929-2145` 主要动态暴露源码、字符串/手写 stub 断言；`verify.sh:2842-2865` 只验证 `app.asar` 锚点且 live 为条件式；当前 `./verify.sh` 全绿但本日两个任务仍需修复 Markdown 根和 header 根；本轮 live diagnose 证实 current surface `mainSurface=0`、`threadScroll=1`、`layoutRoot=1`。

### 冲突摘要
- 需求 vs RULES：存在经用户明确批准的架构例外。旧 RULES 假定“无构建系统、不得引入依赖、保留旧 alias”，而用户已批准原生 Xcode/Swift 替换、仅迁移配置、删除旧代码。仍保留其安全、surface 门禁、失败开放、敏感数据、文档同步和验证原则；切换后 README/ABSTRACT 必须同步，项目知识需按新架构刷新。
- 需求 vs ABSTRACT：有意替换。现 ABSTRACT 只描述 Shell/Node/固定入口，本任务最终必须改写为 SwiftUI＋ExtensionCore＋PageRuntime＋adapter 架构。
- 需求 vs 现有代码：有意冲突。旧单文件/脚本产品链在新实现全绿前保留作对照，在 U6 原子切换时删除，不发布双实现。
- Dev-Spec vs 现有代码：无未解决冲突。当前工作树中旧文件的未提交兼容修复属于已知基线；删除它们只发生在新 App 完整验证后，其他 Harness/用户改动不回滚。

### 影响面分析
- **涉及模块**：macOS App/Xcode 工程、SwiftUI 菜单栏与设置、应用生命周期、CDP/WebSocket、surface/target、配置与迁移、PageRuntime、布局/输入/主题 adapters、健康/日志/诊断、自动/live 验证、README 与架构摘要、旧链路删除。
- **核心类 / 页面 / 接口**：`CodexAppExtensionApp`、`SettingsWindowCoordinator`、`AppModel`、`AppLifecycleMonitor`、`DebugSessionManager`、`CDPClient`、`TargetCoordinator`、`ConfigStore`、`LegacyConfigMigrator`、`FeatureRegistry`、`HealthCenter`、`window.__codexAppExtensionV2`、`FeatureAdapter` envelope、`MenuBarExtra`、显式原生设置 `NSWindow`、`app://-/index.html`。
- **数据库变更**：无数据库；新增 `schemaVersion=2` JSON、last-known-good、migration report 和轮转日志。
- **接口变更**：有。删除旧 CLI/环境变量/作者软链/固定脚本入口；新增 Swift 强类型配置、菜单/UI 操作、版本化 Swift↔PageRuntime JSON envelope、adapter 状态和脱敏诊断格式。
- **关联历史任务**：`SM-019f8ec0-b3d2-7bb3-8327-54be49bbebf7`、`SM-019f9237-1a27-7dff-a9b8-557d911db38d`、`SM-019fa354-fcbc-73c8-bb85-fb7317c4f4e7`、`SM-019fc5a8-f783-78a3-880a-ca2a2ac96bbe`、`SM-019fc5c8-55c1-72a5-b45b-37d2af6f3470`。

### 改动范围
> 任务 artifacts 不计入产品改动。新文件按职责目录列出；实现必须遵守 `execution.jsonl` 的精确单元 ownership。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension.xcodeproj/project.pbxproj`、`CodexAppExtension/Supporting/Info.plist` | 新增 | Xcode project / UTF-8 XML；依据：Xcode 26.6 与 `plutil` | 创建 macOS 13+、bundle id `com.ysxiiun.codexappextension`、`LSUIElement=true` 的 App 和测试 targets |
| `CodexAppExtension/App/**/*.swift` | 新增 | UTF-8；依据：Swift 6.3.3 | `MenuBarExtra`、AppModel、菜单四态、显式原生设置窗口与五页设置 |
| `CodexAppExtension/Core/**/*.swift` | 新增 | UTF-8；依据：Swift 6.3.3 | 生命周期、动态 CDP、target、配置迁移、feature registry、健康、日志与诊断 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js`、`CodexAppExtension/Resources/Adapters/*.js` | 新增 | UTF-8；依据：页面运行时需 DOM/CSS/事件 API | 版本化 PageRuntime 与独立布局、输入、主题 adapters |
| `CodexAppExtensionTests/**/*.swift`、`PageRuntimeTests/**/*`、`CodexAppExtensionUITests/**/*.swift` | 新增 | UTF-8 | Swift 单测、WKWebView DOM fixture、性能/隐私与 UI 测试 |
| `README.md`、`.easy-coding/ABSTRACT.md` | 修改 | 保持 UTF-8 | 切换安装、配置、诊断、验证、卸载和架构契约到 V2 |
| `inject-wide-layout.mjs`、`launch.sh`、`inject-current.sh`、`config.sh`、`follow-author-config.sh`、`lib/runtime.sh`、`verify.sh`、`data/author-config.json`、`strong-text-color-preview.html` | 删除 | — | 新 App 全量验证后删除旧 Shell/Node、作者配置和旧预览链路 |

### 修改方案
- **总体改法**：以一个原生 SwiftUI 菜单栏 App 承载 `ExtensionCore`，通过 Browser 级 CDP 管理 target，把页面增强重写为具备统一 probe/install/update/diagnose/uninstall 契约的独立 JS adapter；配置和 UI 走事务式强类型契约，最终以新验证体系替换旧脚本。
- **后端改动**：本地 Swift 核心负责 `NSWorkspace` 应用监控、精确 bundle/PID 校验、用户确认重启、随机回环 CDP、`URLSessionWebSocketTask` 请求代次与重连、Target 事件、配置/迁移/last-known-good、feature registry、状态聚合、隐私白名单日志和诊断导出。
- **前端改动**：SwiftUI 采用克制的系统原生信息架构：菜单弹层只显示状态、关键开关和当前可执行动作；设置窗口用 sidebar/分区/分隔线组织五页，避免卡片矩阵和装饰渐变；一个强调色用于主动作，绿/黄/红/灰仅表达状态；默认系统字体和 reduced-motion 友好过渡。页面侧重写宽屏、自动/自定义 header 避让、IME、Tab、focus-ring、Markdown 语义主题 adapters。
- **兼容处理**：读取并备份 V1 配置，把有效偏好映射到 schema v2；`longTextSendEnhancement` 记录为原生接管并提供 `codex://settings`；未知/废弃/无效字段进入迁移报告；不保留旧 `Codex.app`、selector、CLI 或环境变量运行代码。IME、Tab、focus-ring 必须在最终 release 前明确“验证保留”或“删除无残留”。
- **风险点**：跨 Swift/JS/CDP 的并发状态机、ChatGPT 确认重启的数据丢失风险、非公开 DOM 变化、输入协议同步、Xcode/登录启动 bundle 合同、配置迁移与回滚、诊断隐私、菜单/UI 测试稳定性，以及在脏工作树中删除旧文件时误伤任务外改动。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 原生工程、核心模型与配置迁移 | platform | Xcode project、Info.plist、AppConfiguration、ConfigStore、LegacyConfigMigrator、配置 tests | — | macOS 13+ App/test targets 可构建；schema v2、原子写、last-known-good、V1 迁移与报告可用 | Codable、值域、V1 fixture、未知/无效字段、原子回滚、plist | `AppConfiguration` 是唯一配置源；后续不建立第二份状态 |
| U2 | ChatGPT 生命周期、动态 CDP 与 target 状态机 | runtime | Lifecycle/CDP/Target/Health Swift 与 tests | U1 | 精确识别 ChatGPT；无 CDP 需确认；随机 loopback；Browser Target 重连；surface 双门禁 | 全状态机、端口、WebSocket 超时/代次/退避、target/surface | `RuntimeSnapshot` 供 UI；只向合法 target 交付 PageRuntime |
| U3 | PageRuntime、功能准入与独立 adapters | frontend-runtime | bootstrap、六类 adapters、FeatureRegistry、WKWebView fixtures | U1, U2 | adapter 独立、幂等、失败开放、禁止全扫/文案识别；保留功能可完全卸载 | DOM fixture、异常隔离、布局/输入/主题、observer 预算 | 固定 JSON envelope；adapter 只收自己的 config；共享 scoped observer bus |
| U4 | 菜单栏四态、设置五页与配置事务 UI | frontend | AppModel、StatusMenuView、Settings views、UI tests | U1, U2, U3 | 默认无 Dock；四态准确；复杂配置预览/应用/回滚；确认重启和登录启动可解释 | 菜单/设置/UI、辅助功能、SMAppService、错误路径 | UI 只调用 ExtensionCore；快速与复杂配置使用同一事务 |
| U5 | 脱敏诊断、性能门禁与全链验证 | verification | DiagnosticEvent/Store/Exporter、隐私/性能/UI recovery tests | U1-U4 | 白名单诊断、1 MiB×5 轮转、超预算降级；六条主路径和功能 live gate 有证据 | 敏感负向、日志、observer/refresh、真实 current app | live gate 绑定实现/config 指纹且不发送消息/保存正文 |
| U6 | 原子切换、旧链路删除与文档重写 | cutover | README、ABSTRACT、全部旧产品文件 | U1-U5 | 新 Release 与全测试/live gate 绿后删除旧链；文档/安装/卸载真实；任务外改动保留 | Release、全测试、迁移、旧引用清理、diff/范围审计 | 不允许双实现 fallback；旧删除必须绑定 U1-U5 最终绿色证据 |

**执行策略**：sequential
- 顺序：U1 → U2 → U3 → U4 → U5 → U6。
- 原因：工程/配置协议、CDP/状态模型、页面 envelope、UI 和切换存在强依赖；并行修改共享 Xcode 工程或跨语言契约会放大返工和误删风险。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| Swift 配置、迁移、状态机、CDP、target、诊断和性能 | 必测 | U1/U2/U5 | XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test -only-testing:ExtensionCoreTests` |
| PageRuntime 与全部 adapters 的当前/未知 DOM、幂等、异常隔离和卸载 | 必测 | U3 | WKWebView fixture XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test -only-testing:PageRuntimeTests` |
| 菜单四态、设置、事务回滚、迁移/重启确认和登录启动 | 必测 | U4/U5 | XCUITest；真实状态项 identifier 冒烟 + Debug 同源 StatusMenuView 宿主内容/动作 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test -only-testing:CodexAppExtensionUITests` |
| 全套与 Release 构建 | 必测 | U6 | Xcode build/test | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test`；`xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Release -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` |
| Info.plist、格式与工作树 | 必测 | U1/U6 | 静态 | `plutil -lint CodexAppExtension/Supporting/Info.plist`；`git diff --check` |
| 当前 ChatGPT 生命周期、真实布局/输入/主题、reload 和清理 | 必测 | U2-U6 | Live CDP + 人工边界 | 运行构建产物，从菜单执行健康检查；真实重启必须再次取得用户确认 |

- **人工验收**：真实菜单栏状态项点击与弹层定位、菜单栏图标与四态、五页设置的信息密度和可读性；布局/顶部/主题真实观感；中文输入法组合与 Tab 编辑器行为；确认重启风险提示；登录启动授权；卸载时保留/删除数据选择。
- **无法验证项**：未来未知 ChatGPT build 的兼容性无法预先证明，以 build 变化后的 preflight、degraded/unsupported 和失败开放覆盖；未经用户确认不能执行真实强制重启；自动 fixture 不能替代真实中文输入法和最终审美验收。

### Workflow Mode
- **项目配置**：adaptive。
- **Session 覆盖**：无。
- **机械最低模式**：strict（状态 API：`broad-change-scope`、`high-risk-contract-or-domain`）。
- **推荐并选择**：strict。
- **选择原因**：一次替换 Xcode/Swift/JS 架构，包含配置 schema 迁移、进程重启安全、异步 CDP 状态机、隐私诊断、广泛文件增删、UI、live 验证和旧链路原子删除；任何弱化都会产生数据丢失、静默失效或双实现风险。
- **状态内执行差异**：IMPLEMENT 严格顺序执行 U1-U6，每单元 shift-left 运行定向 tests 并记录契约；REVIEW 覆盖配置迁移、并发/取消、安全重启、DOM 失败开放、隐私和删除范围；VERIFICATION 执行全 XCTest/XCUITest、Release build、plutil、diff、迁移与 current ChatGPT live gates，绑定最终实现/config 指纹；MEMORY 记录新架构、迁移和删除事实，且只有验证绿色后自动完成。

### 风险与注意事项
- 当前工作树包含两个已完成但未提交的 `26.727.51351` 修复、Harness 升级、memory distill 和作者配置改动；实现不能 reset/checkout 它们，U6 删除旧产品文件须严格按已批准清理范围，其他 `.easy-coding` 改动必须保留。
- `MenuBarExtra` 和 `SMAppService` 需要 macOS 13+；`LSUIElement=true`、主 App 登录启动授权和设置窗口激活必须用真实 bundle 验证，不能只跑 Swift 单测。
- CDP 无应用层认证；随机回环端口降低可预测性但不消除同用户本地进程风险，严禁外网监听并在诊断中明确暴露会话状态。
- Browser 级 Target 生命周期和 `URLSessionWebSocketTask` 的 actor 取消/重连必须以 connection generation 隔离迟到事件。
- 输入 adapter 不能稳定证明 ProseMirror/request input 状态同步时必须从首版代码、配置和 UI 中删除，不能以 legacy selector 或 `execCommand` 强行保留。
- 旧 `verify.sh` 删除前，新测试必须覆盖其安全状态机、surface/target 和失败开放价值；删除后再跑完整门禁，防止验证真空。
- Frontend 视觉原则：系统原生、克制、稠密但可扫读；避免卡片矩阵、装饰渐变和多强调色；状态色只表达状态，动作使用一个主强调色；动画遵从 Reduce Motion。
