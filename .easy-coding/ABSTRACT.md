# codex-app-extension 架构摘要

> 最后更新：2026-09-09；当前发布树为 SwiftUI + ExtensionCore + PageRuntime V2（implementation revision 16）。

## 项目定位

`codex-app-extension` 是 macOS 13+ 原生菜单栏 App，为 `/Applications/ChatGPT.app` 中的 Codex 工作区提供本地增强。产品 bundle id 为 `com.ysxiiun.codexappextension`，`LSUIElement=true`；目标 ChatGPT bundle id 为 `com.openai.codex`。

项目不修改 ChatGPT 包体、账号或会话数据。CDP 只绑定 `127.0.0.1` 动态高位端口，正在运行但未启用 CDP 的 ChatGPT 必须经过用户原生确认才能重启。发布树只有 V2，不保留 Shell/Node、固定端口、旧环境变量、CLI 或 selector fallback。

## 顶层结构

```text
CodexAppExtension.xcodeproj/
CodexAppExtension/
  App/
    CodexAppExtensionApp.swift
    AppModel.swift
    StatusMenuView.swift
    Settings/
  Core/
    Models/
    Configuration/
    Lifecycle/
    Startup/
    CDP/
    Features/
    Health/
    Runtime/
  Resources/
    PageRuntime/bootstrap.js
    Adapters/*.js
  Supporting/Info.plist
CodexAppExtensionTests/
CodexAppExtensionUITests/
PageRuntimeTests/
```

Xcode scheme 为 `CodexAppExtension`。主要 targets：

- `CodexAppExtension`：SwiftUI 菜单栏 App 与显式管理的原生设置窗口。
- `ExtensionCore`：配置、生命周期、CDP、PageRuntime bridge、健康与诊断框架。
- `ExtensionCoreTests`：Swift Core tests 与 PageRuntime fixture/performance tests。
- `CodexAppExtensionUITests`：菜单栏、设置与恢复路径 UI tests。

## 核心数据流

1. `AppModel.makeForCurrentProcess()` 组装 `ConfigStore`、`LegacyConfigMigrator`、`AppLifecycleMonitor`、`DebugSessionManager`、`CDPClient`、`CDPPageRuntimeBridge`、`RuntimeController`、`HealthCenter` 与 `DiagnosticLogStore`。
2. `RuntimeController` 迁移/加载配置并监测 ChatGPT 主进程；UI 只调用它的公共接口，不直接操作 CDP 或文件系统。
3. `DebugSessionManager` 只复用同时且唯一声明 `--remote-debugging-address=127.0.0.1` 与有效端口的 CDP，或从 `49152...65535` 分配端口启动 ChatGPT；缺失/宽泛/非 IPv4-loopback 地址均建立待确认重启状态。
4. `CDPClient` 连接 Browser WebSocket，按 request id 与 connection generation 隔离响应；`TargetCoordinator` 订阅创建、销毁和 reload。
5. Target 必须满足 `app://-/index.html` 与唯一布局根。布局内 thread scroller 唯一时会话页即合格，composer 是可选能力，其缺失或歧义不撤销 Target。无 scroller 的空白任务页优先要求唯一、已渲染的 `data-codex-composer="true"` ProseMirror；稳定标记尚未挂载时，才回退到布局内唯一、已渲染且可编辑的 ProseMirror。隐藏节点、布局外浮层和重复 composer 不得触发回退。runtime surface 以 `kind=thread` 或 `kind=empty-composer` 区分两类合格页面；宽屏、头部/主题和 IME adapter 接受两类 surface，Markdown 仍要求完整会话面。
6. `CDPPageRuntimeBridge` 注入 `bootstrap.js` 和四个 adapter，以固定 envelope 执行 handshake/install/update/diagnose/uninstall。bootstrap/adapter source 使用显式 side-effect 求值，可接受 CDP 合法的 `type=undefined` 且无 `value`；probe/handshake/execute/performance 使用 value-required 求值，仍强制存在 `result.value`；两类求值都拒绝 `exceptionDetails`。runtime revision 变化时先通过旧公开 API 卸载历史 adapter，再原位替换 API；fresh runtime 在局部更新前补水四项并标记 hydrated。
7. `HealthCenter`、`RuntimeControllerSnapshot` 与有界 `AsyncStream` 驱动菜单栏和设置；bridge 以 session revision 作为 target health generation，由 `HealthCenter` actor 原子执行 begin/update/remove，使用 tombstone 阻止同代迟到更新复活，并拒绝旧代更新或清理影响新代状态；诊断只记录 allowlisted 类型数据。

## SwiftUI App

### App 与状态

- `CodexAppExtension/App/CodexAppExtensionApp.swift`：`MenuBarExtra(.window)`、显式 `SettingsWindowCoordinator`/`NSWindow` 生命周期，以及在 AppModel 尚未绑定时排队一次的启动设置请求。
- `CodexAppExtension/App/AppModel.swift`：主线程 snapshot、配置草稿、快速开关、事务应用、独立原生重启确认、登录启动和诊断动作。
- `CodexAppExtension/App/StatusMenuView.swift`：正常/等待/降级/停用状态、ChatGPT/CDP/target/adapter 摘要、快速开关和动态动作；破坏性重启使用独立 `NSAlert`，不依赖瞬态 MenuBarExtra window。

### 五页设置

- `GeneralSettingsView.swift`：扩展总开关、`SMAppService.mainApp` 登录启动和启动后打开设置。
- `LayoutSettingsView.swift`：宽屏最大宽度/最小边距、自动/自定义 header offset 与预览。
- `InputSettingsView.swift`：IME composition Enter 防护。
- `AppearanceSettingsView.swift`：响应式 Markdown 外观编辑器；宽窗口为滚动编辑区与固定实时预览并排，窄窗口为单列滚动，八个颜色字段均显示色块、语义值或非法状态。扩展不提供也不生成键盘焦点着色。
- `DiagnosticsSettingsView.swift`：运行时/迁移摘要、重新连接/注入、健康检查、复制/导出和 `codex://settings`。

复杂配置只修改 draft；有合格 target 时 `RuntimeController.apply` 先向活动页面预应用，成功后原子持久化；离线时先持久化，后续 connect 使用已保存配置安装。在线页面预应用或持久化失败时恢复已保存配置并回滚页面；菜单快速开关走同一事务边界。配置差异映射为精确 adapter 选择集，wide/header/IME/Markdown 只更新并回滚自身；global 变化或未指定选择集才执行全量四项，纯 App 外观变化不触发页面运行时。App 终止会等待 `RuntimeController.shutdown()` 调用 pipeline stop。

XCUITest 的 Debug 构建保留状态测试窗口覆盖菜单状态，也提供 `--ui-test-real-menu` 路径验证真实状态项、popover 与独立重启警告窗。所有测试宿主均受 `#if DEBUG` 隔离，不进入 Release。

## ExtensionCore

### 配置与迁移

- `Core/Models/AppConfiguration.swift`：唯一 `schemaVersion=2` 强类型配置源，覆盖 global、startup、wide layout、header avoidance、IME、Markdown 和 diagnostics。旧 schema-2 `focusRing` 作为未知键兼容读取但不会再次编码。
- `Core/Configuration/ConfigStore.swift`：在 `~/Library/Application Support/Codex App Extension/` 原子维护 `config.json`、`config.last-known-good.json` 和 `migration-report.json`；首次保存先落 LKG，后续保存先保留旧 current，LKG 失败均不提交新 current。
- `Core/Configuration/LegacyConfigMigrator.swift`：首次启动从 `~/.codex-app-extension/config.json` 迁移，备份到 `config.v1.backup.json`；未知、无效、原生替代和废弃字段只进入迁移报告。

V2 不读取环境变量、CLI 或仓库作者配置。`longTextSendEnhancement` 映射为原生替代；键盘焦点着色、固定 CDP 端口、DOM snapshot、legacy selector override 和旧 preview 字段废弃。legacy `layoutFocusRingFix` 只记录 deprecated，不写入运行配置。

### 生命周期与启动

- `Core/Lifecycle/AppLifecycleMonitor.swift`：只匹配 `/Applications/ChatGPT.app`、bundle `com.openai.codex` 和精确主 executable，不匹配 helper。
- `Core/Lifecycle/DebugSessionManager.swift`：动态回环端口、connect/launch/restart-after-confirmation 计划。
- `Core/Lifecycle/SystemApplicationServices.swift`：NSWorkspace 启停、进程命令行端口读取和 `codex://settings`。
- `Core/Startup/LaunchAtLoginController.swift`：`SMAppService.mainApp`，保留 enabled/notRegistered/requiresApproval/unavailable/error 原始语义。

重启只接受 UI 明确确认；使用正常 terminate 与有界退出等待，不允许自动 kill 或无确认重启。任何错误发布到健康状态，不终止无关进程。

### CDP 与 target

- `Core/CDP/CDPClient.swift`：HTTP readiness、URLSession WebSocket、请求关联、generation 隔离、事件流和退避。
- `Core/CDP/TargetCoordinator.swift`：Browser target 生命周期、URL 门禁、surface probe、reload/destroy 清理。
- `Core/CDP/CDPPageRuntimeBridge.swift`：bundle 脚本加载、V2 handshake、typed apply/diagnose/performance poll。
- `Core/Runtime/RuntimeController.swift`：对 UI 暴露 start/refresh/reconnect/reinject/diagnose/apply/rollback/diagnostic APIs，并协调进程 monitor。

连接只使用明确的 `127.0.0.1:<dynamic-port>`。不存在固定端口 fallback，也不会连接外部网卡或对第一个 page target 盲注入。

同 ID、同 URL 的 `targetInfoChanged` 视为可能包含 metadata 更新或同 URL reload：pipeline 保留当前 active target，原位重新 probe/apply，从而在刷新期间不向菜单发布短暂的 nil。`targetCreated` 与 `targetInfoChanged` 对合格的新 ID 共用 replacement 流程：新 target 先 probe/install，成功后切换 active target，再只 invalidate 旧 ID。event loop 捕获 runtime lifecycle generation，每次 target 激活再捕获 per-target revision；`HealthCenter` 只允许当前未结束 generation + revision 更新或清除 `adapterIdentifier=runtime`，更高 revision 可 reopen，tombstone 拒绝旧操作且不干扰 bridge session generation。destroy、URL dequalification、replacement 与 stop 共用唯一 invalidation 入口，先 tombstone、再收敛 bridge/known/active。旧 revision 异步结果只以精确 `PageRuntimeBridgeError.staleRevision` 表示 supersession：target wait 忽略该旧结果并在策略边界内继续，事件激活静默丢弃；它不进入 runtime degraded health。其他 transport、probe、apply、adapter 或协议错误仍按原路径发布，禁止用宽泛 catch 掩盖。

同 ID 页面导航会替换 JavaScript 上下文，而 composer DOM 可能晚于唯一一次 `targetInfoChanged` 到达。performance poll 使用只包含 `runtimeMissing` 与 observer 健康字段的类型化 envelope；只有 PageRuntime 或其 performance API 缺失才抛出专用 `runtimeUnavailable` 并重新 probe/install，畸形 snapshot、transport、protocol 与 stale 错误不得触发 DOM 写入。恢复只在捕获的 lifecycle generation、active target 身份与 per-target revision 仍完全匹配时执行，因此并发刷新、destroy 或 reconnect 已推进生命周期后，迟到 poll 只能丢弃，不能重复 apply。

target health 的生命周期顺序不得依赖跨 actor `await` 的先后推断。bridge 必须把 session revision 传给 `HealthCenter` 的 generation-aware API；新 generation 开始时清除旧 adapter 状态，低 generation update/remove 必须被忽略，同 generation remove 留下 tombstone 并拒绝迟到 update。既有无 generation API 保持给非 bridge 调用方使用，不得借它绕过 bridge 的顺序合同。

## PageRuntime 与 adapters

`Resources/PageRuntime/bootstrap.js` 只暴露不可写的 `window.__codexAppExtensionV2`，固定支持 register、handshake、install、update、diagnose、uninstall、surface、observer 和 performance snapshot。当前 `runtimeVersion=2`、`implementationRevision=16`；同 revision 重注入完全幂等，revision 15 或更旧 revision 先 best-effort 卸载历史五项（只包含用于清理的 retired `focus-ring` id）再原位升级，避免旧 observer 或焦点副作用滞留。surface 同时暴露 `kind` 与 `editorSignal`，空白页优先稳定 composer 标记，仅在无 scroller 时选择唯一且可见的布局内编辑器；这条受限回退不进入已有会话页。空白页会有界观察 ProseMirror 候选、layout 与有限祖先的 `contenteditable`、composer、hidden、aria-hidden、style 等资格属性，即使候选暂时被过滤为不合格，同一节点恢复可见也能触发重新审查。显式 install/update 抛错会写入不可命中配置的失败签名；observer reconcile 只更新 surface/健康状态，不恢复正式签名，后续必须成功执行显式 install/update 才能重新进入幂等快路。wide-layout 对普通正文 DOM burst 使用几何身份快路径，只有 surface/owner/right-rail 身份变化或专用 resize/mutation/motion 触发才执行完整几何重算；width owner 自身的原生 transform 会计入 native offset，但扩展拥有的 individual translate 必须排除，避免 residual offset 自反馈。空白页的 width owner 必须位于唯一 editor 到唯一 layout 的有限祖先路径上，可使用 `thread-composer-max-width` 或新版宿主的 `thread-content-max-width` token；空白页 CSS 只接受 wide adapter 写给当前确认 editor 的专用 marker，隐藏或残留的宿主 marked editor 无法让旁支 owner 命中，并继续以独立 composer 宽度变量控制和恢复。owner 尚未出现时，adapter 仅观察唯一 editor 到当前 surface scope（会话为 scroller、空白页为 layout）的有限祖先 class；宿主复用同一节点并原地增加或移除 width-owner token 时，下一合并帧通过 runtime transaction 将 owner、偏移和 observer health 双向同步到 healthy 或 recoverable waiting，期间不撤销 marker、不依赖 child-list 变化，也不掩盖永久缺失。右侧浮窗通过两条已验证路径建立占位：唯一 layoutRoot 内、scroller 与 editor/width-owner 分支之外的通用 `[data-pip-obstacle]` 语义节点，或已有原生 rail shell 内的已绘制组件。语义节点直接测量自身矩形及到 layoutRoot 的完整可见链，允许透明、childless 和 pointer-events:none，不依赖业务属性值、home 属性或旧 shell class。候选还必须满足右侧浮层定位与有效尺寸，并排除 header/composer、正文、布局外和瞬态 menu/listbox/dialog。水平居中 reference 与纵向可见范围独立：所有 body/shell 统一使用 surface/layout 与 viewport 的交集，顶部组件不再和底部 composer 的 Y 区间比较。多个有效候选取最左边界，不累计预留宽度，原有宽度/padding/native-residual offset 算法保持。候选集合先于可见性过滤进入身份缓存；layoutRoot 子树仅观察 data-pip-obstacle 属性发现新增/删除，已发现候选及有限祖先观察相关属性、尺寸和动画，节点去重并在删除、surface 切换和卸载时解绑；普通正文 burst 保留快路径。关闭或隐藏后释放占位，短空态参与，透明空壳与瞬态菜单保持排除。

固定 envelope 字段：

```text
runtimeVersion / requestId / adapterId / operation / config / result / error
```

发布的四个 adapter：

- `Adapters/wide-layout.js`：会话页优先在唯一 thread scroller 以差异写入维护宽度变量；空白任务页仅在 layout 唯一、composer 唯一且无 scroller 时回退 layout root，沿当前唯一 editor 祖先链只绑定其最外层 composer width owner，并在已确认 editor 写入可完整恢复的专用 marker，让无稳定 composer 标记的 fallback 仍能命中宽度 CSS；无关或残留 owner 不改。空白页只向 layout root 写 `--thread-composer-max-width`，不覆盖 content/Markdown/side-padding/content-offset 变量。会话页的原生 thread content、Markdown width consumer 与 selected overlay 是统一候选集合，每个分支仅无候选祖先的最外层节点应用 `min(配置上限, 100% - 2 × 最小 side padding)`；selected Markdown 内稳定 `[data-markdown-table]` 外壳被限制为当前内容宽度，原生列宽保持不变，超出内容只在直接表格子树中水平滚动，不依赖 CSS module 哈希；right rail、menu/listbox/dialog 与浮层保持原生宽度。
- `Adapters/header-offset.js`：在唯一 layout root 应用自动或自定义 header offset。
- `Adapters/ime-enter-guard.js`：在 editor/descendant 的 composition Enter、keyCode 229 或 compositionend 后 `120 ms` 有界宽限期内阻止默认事件，宽限期后的普通 Enter 不拦截。
- `Adapters/markdown-semantic-theme.js`：只在合格 thread scroller 的 Markdown candidate 下增强语义元素，并排除代码块；经典默认精确使用金色标题/强调、粉色行内代码和单层粉色引用样式。

每个 adapter 只接收自己的配置片段，独立 probe/install/update/diagnose/uninstall。Target 与 runtime 都把 layout + composer 的空白页视为 `empty-composer` 合格面：wide-layout 使用受限 layout/composer 回退，header-offset 与 ime-enter-guard 直接运行；markdown-semantic-theme 仍因缺少 thread scroller 与正文候选进入 recoverable waiting。明确返回 `qualified=false/recoverable=true` 的页面暂缺状态进入 waiting，不生成事务错误且在 DOM 恢复后自动收敛为 healthy；缺省或明确不可恢复的不合格仍是 degraded。首次 install 单 adapter 失败只降级该 adapter，候选 update 的目标 adapter 硬失败仍抛错以触发对称局部回滚。稳定 document-root observer 识别同 target SPA 的 layout/scroller/editor 身份变更并自动重新资格审查、重新绑定。adapter 保存宿主原有 attribute、inline property 值/priority 和 style 内容，target 失效、pipeline stop 或 App 退出时先有界卸载再 detach；IME 同时移除全部 handler。扩展不注册、不加载、不生成任何焦点 marker、CSS 变量或 `:focus-visible` 规则。

observer bus 只观察稳定 document root 的 `childList/subtree` 与当前合格节点的原生资格属性，不观察正文或任意属性。adapter 对自己拥有的 marker、style 文本与 CSS property 必须先比较再写，并返回真实 changed，防止自身 DOM mutation 形成反馈环。DOM burst 合并为最多一次 RAF 和一次 80 ms settle；单 adapter 每次预算 8 ms，连续 3 次超限即仅降级该 adapter 并停止后续写入。observer 最多 16 个，performance event 最多 32 条；最终 observer、RAF、timer 都必须可清理。

## 健康、诊断与隐私

- `Core/Health/HealthCenter.swift`：连接、target 与单 adapter 的 healthy/waiting/degraded 状态，最新状态 stream buffer 为 1。
- `Core/Health/DiagnosticEvent.swift`：仅版本、固定 enum、count、duration、timestamp；无任意字符串/payload 字段。
- `Core/Health/DiagnosticLogStore.swift`：actor，默认 `1 MiB × 5` 确定性轮转，磁盘失败返回 false。
- `Core/Health/DiagnosticExporter.swift`：只导出 allowlisted configuration/health/events/manifest；不复制 raw log。

loss-sensitive CDP/target streams buffer 为 64。任何诊断新增字段必须先扩展隐私负向测试，且不得记录正文、草稿、Cookie、完整 DOM、CDP/WebSocket payload、URL 或 target id。

## 测试架构

- `CodexAppExtensionTests/`：配置、迁移、生命周期、CDP、target、runtime 事务、可靠性、隐私、轮转、导出与性能。
- `PageRuntimeTests/`：当前会话/空白任务/不支持/虚构旧 surface fixture、adapter lifecycle、IME、CSS、observer coalescing、预算与清理。
- `CodexAppExtensionUITests/`：菜单四态、设置五页、配置失败、启动设置和六类恢复路径。
- current ChatGPT live gate：exact target + count/style/status-only selectors，验证四个 adapter、经典 computed style、waiting 收敛与焦点侵入负向状态；禁止读取正文、草稿、Cookie 或 payload，结束时校验宿主状态和 observer/RAF/timer 有界。

CDP bridge tests 必须分别覆盖 side-effect 合法 undefined、非 undefined 缺 value、value-required 缺 value、`exceptionDetails`、专用 runtime-missing envelope 与畸形 performance snapshot；runtime reliability tests 必须覆盖 target wait/event 两条 stale revision 路径、同 ID/同 URL 原位刷新期间 active target 稳定、metadata burst、PageRuntime 缺失后的轮询恢复、非缺失 poll 错误零 apply、迟到 poll 的 revision/reconnect 隔离，以及真实 URL 变化和非 stale 失败反例。PageRuntime fixture 必须覆盖 wide-layout no-op 写次数、observer 收敛、联合夹取公式、负向 scope 与卸载恢复；菜单 UI test 必须覆盖四个标题左列和四个 switch 右列对齐。

Xcode 26.6 的 unsigned UI runner 可能因缺失 `@rpath/lib_TestingInterop.dylib` 在产品启动前终止。UI tests 使用默认本地签名；必要时只修补并重签临时 DerivedData runner，禁止把该 dylib 放进产品或工程。

## 构建与验证命令

Core + PageRuntime tests：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO
```

UI test compile（保留默认本地签名）：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests build-for-testing
```

Release：

```bash
./install.sh
```

`install.sh` 是唯一推荐的本地 Release 安装入口：预检后以当前用户增量构建并按 framework → App 顺序做 ad-hoc 签名，静态审计 `@rpath/ExtensionCore.framework/Versions/A/ExtensionCore`、App `@executable_path/../Frameworks` runpath、Info、严格五个 JavaScript 资源（bootstrap + 四 adapter，无 focus 资源）和签名；随后在目标父目录内 stage/backup/swap，安装后重复同一审计，并对精确 bundle id 做冷启动和至少 3 秒存活检查。脚本不能整体以 sudo 运行，只有安装父目录写操作可按需提权；失败 trap 恢复旧 App。重复执行复用固定 DerivedData，相同包可跳过 swap，但不能跳过终检。

Release 静态终检还包括：`plutil -lint CodexAppExtension/Supporting/Info.plist`、`otool -L` App executable、`otool -D` embedded framework、Release resource inventory、Release Debug-fixture/legacy/privacy scan、旧文件不存在、README 命令可解析、`git diff --check` 和工作树范围审计。只通过 build 或 `codesign --verify` 不足以证明可发布；实际安装后的 cold-launch survival 是硬门禁。

## 架构约束

- 只有 V2 一套产品实现；禁止恢复 legacy fallback 掩盖失败。
- UI 不直接访问 CDP 或配置文件；所有操作经过 ExtensionCore 公共接口。
- 破坏性重启必须精确匹配 ChatGPT 主进程并经过原生确认。
- CDP 必须是动态回环端口；target 必须通过 URL + 唯一 surface 双门禁。
- `Runtime.evaluate` 的 side-effect 与 value-required 合同必须显式分离；只有前者允许无 value 的 undefined，任何 `exceptionDetails` 都是失败。
- 只有精确 stale revision 可以作为 target supersession 静默丢弃；其他运行时错误必须保持可见。
- 每个 adapter 独立失败开放、可诊断、可卸载、可恢复宿主状态。
- 键盘焦点表现始终由 macOS/ChatGPT 原生实现；产品配置、UI、adapter、资源包和运行时不得恢复焦点着色。
- 配置写入必须原子化，页面预应用和持久化失败必须回滚。
- 诊断只能扩展 allowlist 类型模型，不能事后字符串脱敏。
- 不得把静态 fixture 或单元测试表述为 current ChatGPT live 验收。
- README、ABSTRACT、Xcode 工程、资源清单和验证命令必须同步更新。
- ExtensionCore 必须作为 App 内嵌 framework 使用 `@rpath` install id；禁止通过安装到 `/Library/Frameworks` 掩盖打包错误。
- Release 交付必须验证安装后真实冷启动，不能用 codesign-only 结果替代 dyld 加载证据。
