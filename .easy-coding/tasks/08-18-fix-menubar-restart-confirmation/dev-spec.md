## 技术方案：修复菜单栏确认重启 ChatGPT 无响应与 CDP 无法恢复

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：让“确认重启 ChatGPT…”在任一次确认执行失败后仍可明确反馈并重新发起，同时在 ChatGPT 已成功重新拉起但 CDP/Target 尚未就绪时消费旧重启计划，交由现有监控自动恢复连接，避免按钮继续显示却静默无效。
- **输入**：用户截图中的 `等待重启确认 / ChatGPT 运行中 / CDP 未连接` 状态；点击“确认重启 ChatGPT…”没有可见响应；本机现场 ChatGPT PID 2087 无 remote-debugging 参数且无监听端口。
- **输出**：改代码；修复 AppModel 的一次性确认锁、RuntimeController 的待确认状态一致性、菜单进行中反馈与相应 Core/XCUITest 回归，并同步 README 的失败重试语义。
- **边界**：不修改 ChatGPT 包体、账号、对话或草稿；不恢复旧 Shell/Node 启动器；不静默重启、不 force kill；自动验证不点击真实用户 ChatGPT 的破坏性重启确认。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`AppModel.requestRestartConfirmation`、`RestartConfirmationPresenter`、`StatusMenuView`、`RuntimeController.confirmRestart/refresh`、`DebugSessionManager.execute`、`SystemApplicationServices.terminate/launch`、Core 与真实菜单栏 UI tests。
- **当前实现方式**：菜单仅在 `pendingRestartConfirmation=true` 时显示动作；AppModel 在 NSAlert 二次确认后把 `hasConfirmedCurrentRestart` 永久置为 true，只有观察到 pending 变为 false 才解锁；RuntimeController 只有 terminate、launch、CDP connect、Target 安装全部成功后才清除 pending。
- **现有问题 / 缺口**：确认后的 terminate/launch/connect 任一步失败时，pending 可能继续为 true，而 AppModel 的锁不复位，后续按钮点击在 guard 中静默返回；若 launch 已成功但 connect/Target 暂未就绪，旧计划已被消费却仍保留 pending，后续既无法重试该计划，也无法正确表达“连接恢复中”。同进程 reconnect 成功也没有清 pending。现有测试只有取消与一次全成功路径，未覆盖失败后重试或 launch 成功、connect 失败的部分成功边界。
- **证据**：`CodexAppExtension/App/AppModel.swift:198-203` 静默 guard 与只置 true；`:71-73` 仅以 pending=false 解锁；`CodexAppExtension/Core/Runtime/RuntimeController.swift:887-903` 仅全链成功后清 pending；`:824-829` reconnect 成功未清 pending；`CodexAppExtensionUITests/MenuBarUITests.swift:36-61` 只覆盖取消与一次成功；现场 `ps` 显示 PID 2087 命令仅为 `/Applications/ChatGPT.app/Contents/MacOS/ChatGPT`，`lsof -a -p 2087 -iTCP -sTCP:LISTEN` 无监听；扩展进程采样主线程处于普通事件循环而非 `NSAlert.runModal`，支持“点击被前置 guard 丢弃”的判断。无法直接读取私有布尔值，因此该现场归因是由状态与代码共同支持的高置信推断。

### 冲突摘要
- 需求 vs RULES：无冲突；继续坚持显式原生确认、正常 terminate、动态回环端口和失败可见，不引入 force kill。
- 需求 vs ABSTRACT：无冲突；保持 AppModel → RuntimeControlling → DebugSessionManager/SystemApplicationServices 分层。
- 需求 vs 现有代码：存在实现缺口；现有代码把“防重复提交”实现为跨失败永久锁，并混淆“重启计划已消费”与“CDP 已完全就绪”。
- Dev-Spec vs 现有代码：无未解决冲突；保留当前工作树中 `RuntimeController.swift` 的新会话恢复改动，只在相邻重启状态逻辑上增量修改。

### 决策闭环
decision_status: closed
- **已解决问题与结论**：1）是否强制终止：否，遵循当前 V2 安全合同，仅在独立 NSAlert 明确确认后正常 terminate；2）失败后是否需要再次弹确认：是，任何未完成的破坏性重启都必须由用户再次确认，不能自动重试终止；3）launch 成功但 CDP/Target 未就绪如何处理：旧重启计划已经消费，pending 立即清除，错误可见并由 2 秒监控按已知新 PID/端口自动 reconnect；4）如何防重复：锁只覆盖实际异步确认执行期，并在调用结束时无条件释放，不能跨失败永久保留。
- **确认依据**：用户目标、截图与本机只读现场；`RULES.md` 的显式确认/正常 terminate 硬约束；`ABSTRACT.md` 的 RuntimeController 自动恢复职责；现有 actor、published UI state 与测试 double 风格；状态 API 已计算机械最低模式为 standard。没有需要用户另行选择且会改变技术路线、契约、范围或验收的开放问题。

### Canonical Spec 来源
- **来源定位**：无
- **设计 / 文档摘要**：无
- **共享执行状态**：无
- **选择任务 / 仓库**：无
- **消费闭包**：无
- **基线与冲突**：无
- **待闭合 integration**：无

### 影响面分析
- **涉及模块**：SwiftUI 菜单动作、AppModel UI 状态、ExtensionCore 重启/连接状态机、Core tests、真实 MenuBarExtra XCUITest、README。
- **核心类 / 页面 / 接口**：`AppModel`、`RestartConfirmationPresenter`、`StatusMenuView`、`RuntimeController`、`RuntimeControlling` 既有 void async 合同、`UITestingRuntimeController`。
- **数据库变更**：无
- **接口变更**：无公开接口变更；只收紧既有内部状态语义并增加菜单进行中展示。
- **关联历史任务**：`08-03-rebuild-codex-menu-bar-runtime-v2`、`SM-019fcfe3-0cfa-7d6b-987c-0edda8fb811c`；历史 Shell 启动器任务 `07-20-handle-running-chatgpt` 仅作为失败边界参考，不恢复其强杀方案。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/App/AppModel.swift` | 修改 | 保持原编码 UTF-8 | 把跨失败永久确认锁改为有生命周期的执行中状态；异步调用结束必定解锁；测试 double 支持失败后仍 pending 的回归场景 |
| `CodexAppExtension/App/StatusMenuView.swift` | 修改 | 保持原编码 UTF-8 | 重启执行中显示明确状态并禁用重复触发，结束后失败路径恢复可点击确认 |
| `CodexAppExtension/Core/Runtime/RuntimeController.swift` | 修改 | 保持原编码 UTF-8 | 成功 launch 后立即消费旧重启计划并清 pending；同端口 reconnect 成功也清理遗留 pending；失败前后保持计划/状态一致 |
| `CodexAppExtensionTests/RuntimeControllerTests.swift` | 修改 | 保持原编码 UTF-8 | 增加 terminate 失败可重试、launch 后 connect 失败不保留伪 pending、monitor reconnect 收敛测试 |
| `CodexAppExtensionUITests/MenuBarUITests.swift` | 修改 | 保持原编码 UTF-8 | 增加确认执行失败后菜单可再次弹出确认、无静默锁死的真实 MenuBarExtra 回归 |
| `README.md` | 修改 | 保持原编码 UTF-8 | 说明进行中反馈、失败后的显式重试与 launch 后自动连接恢复语义 |

### 修改方案
- **总体改法**：把“防重复确认”限制为一次 async 执行的临界区，并把重启状态拆成“破坏性计划是否尚待确认”和“新进程/CDP 是否已就绪”两个事实，确保 UI、pendingPlan 与监控恢复始终一致。
- **后端改动**：RuntimeController 在 `sessionManager.execute` 返回后先原子消费 pendingPlan、更新新 PID/端口并发布 pending=false，再连接 CDP；连接失败保留错误供 UI 显示，由监控以新 PID/端口继续 reconnect；terminate/launch 在返回前失败则保留原 pending 供下一次显式确认。reconnect 成功显式清理任何历史 pending。
- **前端改动**：AppModel 发布 `isRestartConfirmationInFlight`；用户在 NSAlert 选择重启后置为 true，并在 runtime 调用返回时通过 defer 复位。菜单执行中改为不可重复点击的“正在重启 ChatGPT…”，失败返回后恢复“确认重启 ChatGPT…”。
- **兼容处理**：不改变 NSAlert 文案、二次确认、安全终止方式、动态端口、RuntimeControlling 方法签名和既有成功路径；保留当前 RuntimeController/PageRuntime 未提交改动。
- **风险点**：Swift actor 在 await 处可重入，监控刷新可能与确认执行交错；必须让 pendingPlan 的消费时点、observed PID/port 与发布顺序可重复收敛。真实重启会终止承载当前任务的 ChatGPT，只能由用户在安装后人工确认。

### 实施拆解

| 单元 | 说明 | 类型 | 仓库 / 来源任务 / 步骤 | 涉及文件 / 符号 | 依赖 | 验收条件 | 测试点 / 命令 | 跨单元契约 |
|------|------|------|----------------------|-----------------|------|---------|---------------|-----------|
| U1 | 修复重启计划消费与监控恢复状态机 | backend/test | 当前仓库 / 无 / 无 | `RuntimeController.confirmRestart`、`refresh`；`RuntimeControllerTests` doubles | — | terminate 失败仍保留待确认计划；launch 成功后旧 pending 立即清除；connect 失败可由 monitor 无二次破坏性确认恢复 | 定向 `ExtensionCoreTests/RuntimeControllerTests`，再跑完整 `ExtensionCoreTests` | 输入为一次已确认 pendingPlan；输出把“是否还需破坏性确认”与“CDP 是否已连接”分离 |
| U2 | 修复菜单确认执行锁与可见反馈 | frontend/test | 当前仓库 / 无 / 无 | `AppModel.requestRestartConfirmation`、`isRestartConfirmationInFlight`、`StatusMenuView`、`UITestingRuntimeController`、`MenuBarUITests` | U1 | 单次执行期不能重复提交；执行返回后无论成功失败都解锁；失败且 pending 仍在时再次点击能显示 NSAlert | targeted `MenuBarUITests`；成功、取消、失败重试三路径 | 只在用户于独立 NSAlert 点“重启”后调用 U1；一次执行期最多调用一次 |
| U3 | 同步用户可见重启恢复合同 | docs | 当前仓库 / 无 / 无 | `README.md` 重启段落 | U1, U2 | 文档与实际进行中、失败重试、自动 reconnect 语义一致，且不宣称 force kill/静默重启 | `git diff --check`，人工对照代码 | 不扩张产品接口或安全边界 |

**执行策略**：sequential
- 第一批：U1 修复核心状态机
- 第二批：U2 修复 UI 临界区与回归
- 第三批：U3 同步文档

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| terminate 失败保持 pending 且第二次确认可成功 | 必测 | U1 | XCTest actor doubles | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-restart-core test -only-testing:ExtensionCoreTests/RuntimeControllerTests CODE_SIGNING_ALLOWED=NO` |
| launch 成功、connect 失败后清除旧 pending，并由 monitor reconnect 收敛 | 必测 | U1 | XCTest actor doubles | 同上 |
| 真实 MenuBarExtra 的取消、成功、失败后重试 | 必测 | U2 | XCUITest + Debug-only runtime double | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-restart-ui build-for-testing` 后运行 targeted `CodexAppExtensionUITests/MenuBarUITests` |
| 完整 Core 回归 | 必测 | U1/U2 | XCTest | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO` |
| Release 构建与安装包生存 | 应测 | U1/U2 | Xcode/安装脚本 | Release build；`./install.sh`；安装后进程存活检查 |
| 文档和补丁格式 | 必测 | U3 | 静态 | `git diff --check` |

- **人工验收**：安装修复后的 Release；保持当前 ChatGPT 无 CDP，点击“确认重启 ChatGPT…”应弹独立警告框；取消零破坏；再次确认后菜单显示进行中，ChatGPT 正常退出并带动态 `127.0.0.1` CDP 参数重启，最终状态恢复“运行正常”。若正常退出或启动失败，错误可见且按钮可再次发起新的显式确认。
- **无法验证项**：自动流程不得替用户点击真实 ChatGPT 的破坏性重启确认，因为会终止当前任务会话；最终真实重启/CDP 完成需要用户在安装后操作。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：standard（`bounded-high-risk-change`、`multiple-units`、`multi-file-impact`）
- **推荐并选择**：standard
- **选择原因**：单仓库、三顺序单元、六个真实文件；涉及破坏性重启的安全门禁和 actor 重入，机械 floor 已要求 standard，但无公开接口、跨仓库、四单元或十文件以上复杂度，不满足 strict 的复杂度条件。
- **状态内执行差异**：IMPLEMENT 按 U1→U2→U3 顺序并先补失败回归；REVIEW 聚焦状态一致性、重复终止与安全确认；VERIFICATION 跑 targeted + full Core + targeted UI + Release/格式门禁；MEMORY 记录可复用的重启状态语义。

### 风险与注意事项
- 不得把历史 Shell 方案中的 force kill 带回 V2；失败重试仍必须重新取得用户确认。
- 当前工作树已有 Harness 升级及新会话 Runtime/PageRuntime 未提交改动；实现只增量修改明确文件，不回滚、覆盖或混入无关改动。
- 现有诊断 error code 只能说明 CDP/生命周期失败，不能承载任意文本或 UI 私有状态；本任务不扩展诊断隐私面。
