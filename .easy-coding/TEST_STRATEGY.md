# codex-app-extension 测试策略

> 由 ec-init 根据 Xcode scheme、XCTest/XCUITest、PageRuntime fixtures、README 和当前运行环境生成。

## 测试基线

- 测试框架：XCTest/XCUITest；PageRuntime JavaScript 由 `ExtensionCoreTests` 中的 fixture/lifecycle/performance tests 覆盖。
- 标准 Core 命令：`xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO`。
- Release 命令：同一 project/scheme 以 `-configuration Release -destination 'platform=macOS' build`。
- UI tests 使用默认本地签名的 `build-for-testing` / `test-without-building`；不使用 unsigned runner 作为执行证据。
- 不声明无法采集的行覆盖率百分比；以关键状态机、负向隐私、性能和 live 恢复门禁作为交付证据。

## 测试位置与命名

- Swift/Core tests 位于 `CodexAppExtensionTests/`，命名为 `*Tests.swift`。
- PageRuntime tests 位于 `PageRuntimeTests/`，包含 current/unsupported/legacy-fictional HTML fixtures。
- UI tests 位于 `CodexAppExtensionUITests/`，覆盖菜单、五页设置、启动设置和六类恢复路径。受 Xcode 26 多显示器状态项坐标错投影响，Debug 测试通过复用同一 `StatusMenuView` 的宿主窗口执行内容/动作，并对真实 `MenuBarExtra` 状态项做 `menuBar.status` 标识冒烟；这不宣称真实状态项点击 E2E，宿主不进入 Release。
- 新增功能必须在对应目录增加最便宜的单元/fixture 测试，不得只依赖 live 页面。

## 标准验证覆盖

Core/PageRuntime 基线必须同时覆盖：

1. V2 配置默认值/验证/Codable、原子写入、last-known-good 和 V1 迁移/备份/报告。
2. ChatGPT 精确进程、仅显式 `127.0.0.1` 地址的动态端口复用、重启确认零破坏边界、CDP generation/超时/断开/退避。
3. `app://-/index.html` + layout/thread/editor 双门禁，target create/reload/destroy、同 target SPA 三类节点替换自动重绑和旧连接迟到响应隔离。
4. PageRuntime handshake/envelope、5 adapter 资格审查、幂等 apply/update/diagnose/uninstall、初装单 adapter 失败隔离、候选更新失败回滚和宿主恢复。
5. IME compositionstart/compositionend、`keyCode=229`、compositionend 后 `120 ms` 有界宽限期、宽限期后普通 Enter、完整 handler 清理、原生 Tab 边界、focus ring、Markdown 语义节点/代码块排除/嵌套引用。
6. DOM burst 合并、per-adapter 性能降级、有界 stream/observer/event，以及 target invalidation、pipeline stop、App shutdown 的 uninstall-before-detach 与最终清零。
7. 诊断隐私负向样本、`1 MiB × 5` 轮转、并发写入、导出 allowlist 和失败容错。
8. `plutil`、Release resource/Debug fixture/privacy/legacy scan、签名验证、旧文件不存在与 `git diff --check`。
9. Release App 的 `otool -L` 与 embedded ExtensionCore 的 `otool -D` 必须精确匹配 `@rpath/ExtensionCore.framework/Versions/A/ExtensionCore`，App 必须包含 `@executable_path/../Frameworks` runpath，且两处均不得引用 `/Library/Frameworks/ExtensionCore.framework`。
10. `./install.sh` 首次与重复执行都必须通过包体审计；真实安装后 10 秒内进入 running、再存活至少 3 秒，且不得新增 `Library missing` dyld crash。仅 build 或 codesign 通过不能替代 cold-launch 证据。
11. `Runtime.evaluate` 必须覆盖四类协议返回：side-effect 的 `type=undefined` 无 value 成功；非 undefined 缺 value 失败；value-required 缺 value 失败；任意 `exceptionDetails` 失败。
12. target wait 与 target event 的旧 revision 必须作为 supersession 丢弃并允许最新 target 激活，且不产生 runtime degraded；非 stale fixture 失败仍必须发布 degraded。
13. target health 的 generation 顺序必须在 `HealthCenter` actor 内原子验证并变更：新代 begin 清旧 adapter；低代 update/remove 无效；同代 remove 留 tombstone，迟到同代 update 不得复活；无 generation 的既有调用保持原语义。
14. bridge 必须覆盖真实 actor 重入交错：阻塞旧 session uninstall，在等待期间完成同 target 新 revision attach/apply 并写入健康状态，再释放旧 cleanup；最终健康快照只能保留新 revision 状态。
15. 同 ID、同 URL 的 `targetInfoChanged` 单次与 burst 必须原位 probe/apply，刷新期间 active target 始终保持；URL 真实变化和 destroy 仍必须 invalidate，原位刷新真实错误仍进入 degraded。
16. wide-layout 首次写入后，相同 DOM/config 的 reconcile 和 observer settle 不得增加 adapter-owned 写次数；原生 thread 内容与 Markdown consumer 共享 `min(配置上限, 100% - 2 × 最小侧边距)`，composer、right rail、menu/listbox/dialog 与浮层作为负向范围保持原生。
17. 菜单四个快速开关的标题 `minX` 和 switch `maxX` 必须分别在 1 px 容差内对齐，并覆盖至少一次真实 toggle value 变化和布局页上限文案。
18. pipeline runtime health 使用独立 lifecycle generation：HealthCenter 仅允许当前未结束代写入、清除或结束 `runtime` pseudo-adapter；旧 refresh 跨 stop/reconnect 释放后不得复活健康状态，也不得影响 bridge adapter generation。
19. `targetCreated` 与 `targetInfoChanged` 的合格新 ID 均先 probe/install、再切 active、最后 invalidate 旧 ID；覆盖 created-new 后只收到 destroyed-old 的真实顺序。
20. canonical、Markdown 与 selected overlay 作为统一候选集合，所有正向、反向和同类型嵌套分支合计只能有一个最外层 clamp owner。
21. target runtime health 同时使用 lifecycle generation 与 per-target revision；destroy、URL dequalification、replacement、stop 必须经唯一 invalidation 入口先 tombstone。覆盖 degraded 后 URL change 无 destroy，以及旧 refresh 在同连接 target invalidation 后迟到的受控交错。

## 条件式在线验证

current ChatGPT live gate 只允许只读/非破坏 CDP：

- 先确认 exact `app://-/index.html` main target 数量为 1，只输出 selector count 和布尔值。
- 在 isolated world 加载 bootstrap + 5 adapters，install/diagnose 后必须 `finally` uninstall 全部。
- 对比前后 `data-cae-*`、相关 inline CSS property/style node、main runtime 和 observer 状态。
- 结束时 observer/RAF/timer 必须为 0；禁止重启、发送、保存配置、读取正文/草稿/Cookie/DOM 文本/payload。
- 安装后 smoke 可读取扩展自身公开的 connection/target/adapter 健康摘要，确认不再出现 `CDP Runtime 响应无效: Runtime.evaluate` 或 `旧 revision 结果已丢弃`；不得以读取 raw CDP response/page payload 代替。

无动态 CDP 或 exact target 不唯一时必须标记 live gate 未运行，不能用 fixture 代替。

## 人工验收范围

以下行为依赖真实 Electron 窗口、输入法或视觉布局，不由默认脚本完全证明：

- 真实中文输入法组合期间 Enter 与组合结束后普通 Enter。
- 宽屏、顶部避让、Markdown 颜色和 focus ring 在当前 ChatGPT 版本的视觉可读性。
- 用户确认重启前未发送内容处理，以及 macOS 登录项 `requiresApproval` 的系统 UI。
- 真实菜单栏状态项点击、弹层定位与多显示器视觉行为；自动测试只覆盖真实状态项标识和同源 `StatusMenuView` 内容/动作。
- 安装后宽屏增强持续开启时的 10 秒无闪烁、窗口缩放与全部 thread 内容侧边距视觉一致性；自动测试只证明状态生命周期、写入收敛和布局合同。
- 删除 App 后登录项已注销，以及正常重开 ChatGPT 后无运行期样式残留。

## 必测与暂不测试的代码类别

### 必测

- ChatGPT 精确主进程/动态回环端口与确认重启门禁。
- V2 强类型配置、迁移、原子写入和 last-known-good。
- CDP target 防误选；Codex surface 资格失败必须阻止注入，adapter 运行失败保持失败开放。
- adapter CSS/handler/observer 作用域、失败开放、异常隔离与完整卸载。
- 诊断允许字段、隐私负向样本、轮转/导出和性能门禁。

### 暂不自动化

- 真正确认重启 ChatGPT：会中断当前用户状态，默认自动测试不得执行。
- 像素级截图比较和真实 IME 自动化：仓库没有截图基线或输入法控制设施。
- 登录项注销：属于卸载验收，默认安装脚本不删除 App 或用户配置，因此不自动执行。
- Developer ID、公证、跨机器 Gatekeeper：当前仅提供本机 ad-hoc 签名，不把本机冷启动扩张为公开分发证据。

## 变更到验证的映射

| 变更类型 | 最低验证 |
|---|---|
| Swift models/config/lifecycle/CDP/runtime | 对应 `CodexAppExtensionTests/*Tests.swift`，再运行全部 `ExtensionCoreTests` |
| `Runtime.evaluate` response parsing | `CDPPageRuntimeBridgeTests` 的 undefined/value/exceptionDetails 正反例，再运行全部 `ExtensionCoreTests` |
| target revision / event lifecycle | `RuntimeReliabilityTests` 的 wait/event stale supersession 与非 stale degraded 反例，再运行全部 `ExtensionCoreTests` |
| same-target metadata refresh | `RuntimeReliabilityTests` 的原位刷新、active target 中间态、burst、URL 变化与真实错误反例 |
| runtime lifecycle generation / target replacement | `RuntimeReliabilityTests` 的 created/info-changed replacement 与跨 stop/reconnect 迟到事件；`PerformanceBudgetTests` 的 begin/degrade/clear/end 原子排列及 bridge generation 独立性 |
| target health generation ordering | `PerformanceBudgetTests` 的 begin/update/remove/tombstone 排列与 `CDPPageRuntimeBridgeTests` 的旧 uninstall/新 apply 受控交错，再运行全部 `ExtensionCoreTests` |
| `Resources/PageRuntime/bootstrap.js` 或 adapters | `AdapterFixtureTests` 的写次数/observer 收敛/width clamp/负向 scope，加完整 `PageRuntimeTests` lifecycle/performance、Release resource scan 与 count-only live gate |
| SwiftUI App/设置 | Core 的 AppModel/runtime 合同 + UI test compile；菜单快捷开关同时验证标题/开关双列 frame 和交互，用户路径变更运行相关 XCUITest |
| Info.plist / pbxproj / scheme | `plutil`、`xcodebuild -list`、Debug test build、Release build、产物 resource/Info/signature 终检 |
| framework install name / Release packaging | `otool -L/-D/-l`、严格资源与签名审计、`./install.sh` 首次和重复安装、安装后 cold-launch survival |
| `install.sh` | `bash -n`、`--help`、危险路径负向测试、stage/backup/rollback 范围审计、首次与重复真实安装 |
| README / ABSTRACT | 检查命令、字段、优先级和实际代码一致；`git diff --check` |

## 通过标准与失败处理

- 所有必测命令退出码必须为 0，XCTest/XCUITest 失败数必须为 0，Release 必须 `BUILD SUCCEEDED`。
- Release 还必须通过 installed bundle audit 与真实 cold-launch survival；不得只凭构建成功或签名一致性声明可运行。
- 任何 bundle/Info、配置回滚、重启确认、surface/target、adapter 恢复、隐私或性能门禁失败都阻止交付。
- live 失败时先区分“应用未带 CDP”“Runtime.evaluate 协议错误”“revision supersession”“exact target 不唯一”“surface 锚点变化”“adapter 异常”“清理未恢复”，不得直接放宽选择器或恢复 legacy fallback。
