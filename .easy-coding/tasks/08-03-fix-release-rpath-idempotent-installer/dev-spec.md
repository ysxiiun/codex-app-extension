## 技术方案：修复 Release 安装、Runtime 稳定性与宽屏布局合同

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：修复 `Codex App Extension.app` 安装、CDP/runtime 与 target health 问题，并收口用户视觉验收中新发现的宽屏反馈闪烁、侧边距覆盖不完整、最大宽度越过可用区域以及菜单快速开关对齐问题。
- **输入**：用户运行已安装 App 后无菜单栏反应；后续截图依次暴露 dyld、`Runtime.evaluate`、stale revision、target health 竞态；最新两张截图显示同一菜单弹层中的“合格 Target”在具体 ID 与“无”之间跳变，用户只能关闭增强，并明确提出三项布局/UI 行为修正。
- **输出**：改代码；保留已完成的 rpath、幂等安装器与 generation-aware health 修复，新增 target 元数据事件稳定刷新、稳定布局身份与瞬态编辑器能力解耦、wide-layout 幂等写入和完整 thread 内容宽度合同、菜单开关左右对齐，同步文档并重新构建、签名、安装和人工验收。
- **边界**：不安装 framework 到 `/Library/Frameworks`；不引入 Developer ID、公证或自动更新；不模糊 kill 进程；不重启 ChatGPT；不读取页面正文或用户数据；不改变输入框、右侧栏或浮层宽度；不动态改写用户保存的最大宽度数值；不提交或推送 Git；不回滚当前工作树的其他改动。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：已完成的 Xcode/installer/CDP/HealthCenter 修复；`Resources/Adapters/wide-layout.js` 的 CSS 与 observer reconcile；`Resources/PageRuntime/bootstrap.js` 的全局 MutationObserver；`CDPRuntimePipeline.handle` 的 target event 策略；`StatusMenuView.quickToggle` 与布局设置说明；对应 JS fixture、runtime reliability 和 XCUITest。
- **当前实现方式**：wide-layout 在 `.thread-scroll-container` 上设置固定像素 `--thread-content-max-width` / `--markdown-wide-block-max-width`，注入 CSS 只命中 `[data-selected-text-overlay-target]`；每次 reconcile 都重写 style 文本、marker 和三个属性。Pipeline 对每个 `Target.targetInfoChanged` 都先 invalidate、将 active target 清空，再重新 probe/apply。菜单快速开关直接使用带 label 的原生 `Toggle`，没有显式左右列布局。
- **现有问题 / 缺口**：全 document child-list observer 能观察到 adapter 自己重写 `<style>` 产生的 DOM 变化，而 reconcile 没有 no-op 判断，形成自激刷新；同 ID、同 URL 的标题/元数据变化也被当成 reload，菜单 active target 短暂变成 nil。侧边距 CSS 只覆盖 Markdown/selected overlay 内容，原生 thread width consumer 未统一受约束；最大宽度未与两侧最小边距共同夹取。菜单开关的 label 和 switch 跟随 intrinsic size，视觉列不齐。
- **证据**：`wide-layout.js:43-59` 无条件写 `style.textContent`，`:86-106` 每轮都写 marker/变量且恒报 `changed=true`；`bootstrap.js` 旧 surface 资格把 layout、scroller、editor 三者绑定；live CDP 显示当前 `layout=1`、contained scroller=1，但唯一全局 ProseMirror 位于主布局外的 floating surface，因此编辑器挂载变化会错误撤销整个 Target；`RuntimeController.swift:284-288` 对所有 targetInfoChanged 无条件 invalidate/clear/reactivate；`StatusMenuView.swift:35-40,96-100` 没有显式 HStack 两端对齐。用户选择“最大宽度作为上限”，实际值取 `min(配置上限, 可用宽度−两侧最小边距)`，保存值不随窗口改写。

### 冲突摘要
- 需求 vs RULES：无冲突；新增脚本是本地安装交付工具，不恢复已删除的 Shell/Node 运行时或第二配置链。需同步 README/ABSTRACT/TEST_STRATEGY，并执行完整 Core、Release、签名和冷启动验证。
- 需求 vs ABSTRACT：存在缺口；当前架构摘要把 Release build + codesign 作为终检，但没有 install-name 和安装后冷启动门禁，需要补齐。
- 需求 vs 现有代码：存在直接冲突；ExtensionCore 的绝对 install name 与 App 的嵌入式 framework 架构不一致。
- Dev-Spec vs 现有代码：无额外冲突；方案保留现有 targets、bundle id、App UI/runtime 和配置合同，只修复发布打包与安装交付层。

### 影响面分析
- **涉及模块**：既有 packaging/installer/CDP/health；新增 PageRuntime observer 与宽屏 CSS、target info event 生命周期、布局设置文案、菜单栏 SwiftUI 与 UI 测试。
- **核心类 / 页面 / 接口**：`CDPRuntimePipeline`、`wide-layout.js`、`bootstrap.js`、`StatusMenuView`、`LayoutSettingsView`；不改变配置 schema，`maximumContentWidth` 语义明确为运行时上限。
- **数据库变更**：无。
- **接口变更**：保留本地 CLI；不改变持久化 schema。宽屏配置的可观察合同改为“最大宽度是上限，实际宽度始终不超过当前 thread 可用宽度减去两侧最小边距”。
- **关联历史任务**：`SM-019fc76b-6b2c-745d-9c4b-d08639bd0a68`、`SM-019f8ec0-b3d2-7bb3-8327-54be49bbebf7`、`SM-019f9237-1a27-7dff-a9b8-557d911db38d`。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `install.sh` | 新增 | UTF-8 / ASCII 兼容，依据：macOS `/bin/bash` 脚本与现有文本规则 | 八步进度、参数解析、增量构建、本地签名、install-name/包体验证、可回滚替换、幂等跳过和冷启动存活探针 |
| `CodexAppExtension.xcodeproj/project.pbxproj` | 修改 | 保持原编码 us-ascii | Debug/Release ExtensionCore 使用 `@rpath` install-name base |
| `README.md` | 修改 | 保持原编码 utf-8 | 将一键脚本作为推荐安装方式，说明参数、幂等/回滚、权限、本地签名和手工回退命令 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 utf-8 | 增加发布打包、安装脚本和冷启动数据流/约束 |
| `.easy-coding/TEST_STRATEGY.md` | 修改 | 保持原编码 utf-8 | 增加 `otool`、实际安装、重复执行和冷启动存活门禁 |
| `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift` | 修改 | 保持原编码 utf-8 | 区分需要返回值的表达式与仅执行副作用的脚本；识别 `exceptionDetails`，接受合法 `undefined` 脚本结果但不放宽查询结果合同 |
| `CodexAppExtension/Core/CDP/TargetCoordinator.swift` | 修改 | 保持原编码 utf-8 | Target 身份只要求稳定 layout + contained thread scroller；composer 作为可选能力，不参与 Target 存亡 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js` | 修改 | 保持原编码 utf-8 | surface 将 editor 限定为 layout 内唯一且带原生 `data-codex-composer="true"` 信号的节点并允许缺失；observer 仅在 editor 存在时观察 |
| `CodexAppExtension/Resources/Adapters/focus-ring.js`、`ime-enter-guard.js` | 修改 | 保持原编码 utf-8 | editor 缺失时 focus ring 仅处理 layout；IME guard 精确降级并等待真实 editor 恢复 |
| `CodexAppExtension/Core/Runtime/RuntimeController.swift` | 修改 | 保持原编码 utf-8 | 将 stale revision 作为 target supersession 处理：轮询时重试、事件路径静默丢弃，不写入 degraded health |
| `CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | 修改 | 保持原编码 utf-8 | 覆盖合法 undefined、缺失查询 value 与 exceptionDetails 三类 CDP 返回 |
| `CodexAppExtensionTests/TargetCoordinatorTests.swift` | 修改 | 保持原编码 utf-8 | 覆盖 composer 缺失/歧义不影响稳定 Target 身份、scroller 缺失仍拒绝 |
| `CodexAppExtensionTests/RuntimeReliabilityTests.swift` | 修改 | 保持原编码 utf-8 | 覆盖轮询与事件路径 stale revision 不成为持久错误、最新 target 仍可激活 |
| `CodexAppExtension/Core/Health/HealthCenter.swift` | 修改 | 保持原编码 utf-8 | 为 target health 增加 generation/tombstone 原子顺序，阻止旧 update/remove 覆盖或删除新 revision 状态 |
| `CodexAppExtensionTests/PerformanceBudgetTests.swift` | 修改 | 保持原编码 utf-8 | 覆盖 generation 开始、乱序更新、同代删除 tombstone 和旧代清理不影响新代的顺序排列 |
| `CodexAppExtension/Resources/Adapters/wide-layout.js` | 修改 | 保持原编码 utf-8 | reconcile 改为差异写入；宽度变量同时夹取配置上限、100% 可用宽度和两侧最小边距；覆盖原生 thread width consumer 而非只覆盖 Markdown 内容 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持原编码 utf-8 | 覆盖重复 observer refresh 无额外写入、全部 thread 内容选择器、宽度/边距联合表达式和完整卸载恢复 |
| `PageRuntimeTests/PageRuntimeTests.swift` | 修改 | 保持原编码 utf-8 | 将宽屏变量的旧固定像素断言更新为“配置上限 + 两侧最小边距”的联合夹取表达式，并保留其余 PageRuntime 生命周期门禁 |
| `CodexAppExtension/App/StatusMenuView.swift` | 修改 | 保持原编码 utf-8 | 四个快速开关使用统一满宽 HStack：标题左对齐、switch 右对齐 |
| `CodexAppExtensionUITests/MenuBarUITests.swift` | 修改 | 保持原编码 utf-8 | 验证四个标题左边界与 switch 右边界一致 |
| `CodexAppExtension/App/Settings/LayoutSettingsView.swift` | 修改 | 保持原编码 utf-8 | 明确最大内容宽度是上限，实际宽度自动受当前可用区域与最小侧边距夹取 |

### 修改方案
- **总体改法**：保留已经验证的 packaging/CDP/health 修复；对同 target/same URL 的 info change 原位幂等 probe/apply，不清空 active target；用稳定的 layout + contained thread scroller 识别 Target，把 editor 降为 layout 内可选能力；wide-layout 只在值真正变化时写 DOM，并把所有原生 thread width consumer 统一夹取到 `min(配置上限, 100%−2×最小侧边距)`；菜单快速开关建立显式左右列。
- **后端改动**：不涉及业务后端；修改 Xcode 动态链接打包设置。脚本使用固定 bundle id/产品名，构建永不提权；仅目标目录不可写时对同级 staging、backup、swap、cleanup 使用 `sudo`。已运行 App 通过 bundle id 请求正常退出，超时中止而不 kill。
- **前端改动**：菜单四行使用 `Text + Spacer + labelsHidden Toggle` 的满宽 HStack，保留原 action、disabled 与 accessibility identifier；布局设置文案说明上限/实际值关系。
- **兼容处理**：最大宽度保存范围与 schema 不变，窗口缩放只改变 CSS 的实际呈现值，不回写配置。same target/same URL 的 info change 保留 active target 并执行幂等刷新；URL/target 身份真实变化仍走 invalidate。宽屏不接管 composer、right rail、menu/listbox 或原生 floating panel。
- **并发顺序处理**：bridge session revision 作为 target health generation。`HealthCenter` 在自身 actor 内原子处理 begin/update/remove：更高 generation 开始时清除旧 adapter 状态；低 generation 更新一律拒绝；同 generation 删除留下 tombstone，使迟到同代 update 也不能复活；旧 generation remove 不得影响已开始的新 generation。无 generation 的既有 UI/runtime 调用保留原接口语义。
- **风险点**：CSS 百分比必须相对原生内容容器解析，不能把配置值回写成窗口值；observer no-op 不能妨碍真实 DOM replacement 重绑；同 URL info change 必须刷新 reload 后的新 JS context但不能清空 active target；宽屏选择器不能波及 composer/rail/浮层。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 修正 ExtensionCore 的 `@rpath` 合同 | platform-packaging | `CodexAppExtension.xcodeproj/project.pbxproj` | — | executable load command 与 embedded framework install id 均为精确 `@rpath/.../ExtensionCore`，不再引用 `/Library/Frameworks` | Release build、`otool -L/-D`、codesign | App runpath 与 framework install id 必须配对 |
| U2 | 实现幂等一键安装器 | installer | `install.sh` | U1 | 默认单命令完成八步流程；重复执行安全；失败恢复旧 App；只对安装目录提权；冷启动可验证 | `bash -n`、`--help`、实际安装两次、故障/残留检查 | 只接收 U1 通过 audit 的 App bundle；安装后再次执行同一 audit |
| U3 | 发布门禁与文档同步 | verification-docs | `README.md`、`.easy-coding/ABSTRACT.md`、`.easy-coding/TEST_STRATEGY.md` | U1, U2 | 文档与脚本参数/真实命令一致；当前安装修复并持续运行；验证不再允许 codesign-only 假绿 | 全 Core、Release、install 两次、存活/crash 审计、diff | 冷启动是 Release 的新增硬门禁，不替代原测试 |
| U4 | 规范 CDP Runtime.evaluate 返回合同 | runtime-compatibility | `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift`、`CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | U3 | bootstrap 与 adapter script 的合法 undefined 返回可继续握手/执行；查询表达式仍必须有 value；exceptionDetails 一律失败并保留明确上下文 | bridge 单测、Core 全量 | side-effect/value 两类调用必须显式，禁止全局把 missing value 映射为 null |
| U5 | 隔离旧 revision 的并发 supersession | runtime-reliability | `CodexAppExtension/Core/Runtime/RuntimeController.swift`、`CodexAppExtensionTests/RuntimeReliabilityTests.swift` | U4 | target 变化使旧 revision 失效时，轮询继续寻找最新 target，事件路径不写 degraded；真实 bridge/apply 错误仍进入健康状态 | pipeline 并发/事件回归、Core 全量 | 只抑制精确 `PageRuntimeBridgeError.staleRevision`，不得吞掉 CDP、probe、apply 或 adapter 真实失败 |
| U6 | 重新安装并执行 live smoke | verification-docs | `.easy-coding/ABSTRACT.md`、`.easy-coding/TEST_STRATEGY.md` | U4, U5 | 新 Release 重新构建、签名、安装、冷启动；菜单栏不再显示两条已知错误，能选出合格 target 并报告增强状态 | `./install.sh`、installed audit、诊断/用户截图 | live smoke 只观察扩展自身状态，不读取 ChatGPT 页面内容或用户数据 |
| U7 | generation-aware target health 原子顺序 | runtime-concurrency | `CodexAppExtension/Core/Health/HealthCenter.swift`、`CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift`、`CodexAppExtensionTests/PerformanceBudgetTests.swift`、`CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | U4, U5 | 旧 update/remove 在任何 actor 交错下都不能覆盖或删除新 generation；同代 remove 后迟到 update 不能复活；旧 invalidate cleanup 与新 apply 的真实 bridge 竞态有测试 | HealthCenter 排列测试、受控旧 uninstall/new apply 测试、bridge 全量 | generation 比较必须在 HealthCenter actor 内与状态变更原子完成，bridge 侧检查不能替代 |
| U8 | 最终文档与安装验证 | verification-docs | `.easy-coding/ABSTRACT.md`、`.easy-coding/TEST_STRATEGY.md` | U7 | 文档描述 generation/tombstone 合同；Core 全量、Release、一键安装、冷启动与 allowlist smoke 重跑 | 相关定向、Core 全量、`./install.sh`、诊断尾部 | 最终 review/verification 必须绑定包含 U7 的新实现指纹 |
| U9 | 稳定 target 事件与 runtime health 生命周期 | runtime-reliability | `CodexAppExtension/Core/Runtime/RuntimeController.swift`、`CodexAppExtension/Core/Health/HealthCenter.swift`、`CodexAppExtensionTests/RuntimeReliabilityTests.swift`、`CodexAppExtensionTests/PerformanceBudgetTests.swift` | U7 | 同 ID/同 URL 的 info change 原位幂等刷新且 active target 始终非 nil；合格的新 ID 无论由 created 还是 info changed 到达，都先安装再切换并只 invalidate 旧 ID；所有 destroy、URL dequalification、replacement 与 stop 通过统一 target invalidation 入口；runtime health 同时受 lifecycle generation 与 per-target revision/tombstone 原子约束 | 同 URL单次/burst/unqualified/recovery、degraded→URL change 无 destroy、created-new→destroyed-old、旧 refresh 与 stop/reconnect/target invalidation 交错、HealthCenter 双层 generation 排列 | runtime 临时健康与 bridge session generation 分离；每次 probe/refresh 捕获 target revision，统一 invalidation 先 tombstone runtime target 再清 bridge/known/active，旧操作不能复活 |
| U10 | 修复宽屏自激与宽度合同 | page-runtime-layout | `CodexAppExtension/Resources/Adapters/wide-layout.js`、`PageRuntimeTests/AdapterFixtureTests.swift`、`PageRuntimeTests/PageRuntimeTests.swift` | — | observer refresh 在 DOM/配置未变时零额外 style/property 写；全部原生 thread width consumer 同时受最大宽度与最小侧边距约束；任意 canonical/Markdown/selected 嵌套顺序每个分支只有最外层一个 clamp owner；composer/rail/menu 不受影响；uninstall 恢复原值；既有 PageRuntime 宽度断言与新合同一致 | write-count/no-op、全部正反向嵌套、CSS selector/公式、surface replacement、卸载恢复、observer 队列收敛、相邻 PageRuntime 回归 | 实际宽度=`min(配置上限, 100%−2×最小侧边距)`；三类候选统一执行“无候选祖先”门禁；reconcile 返回真实 changed |
| U11 | 菜单快速开关双列对齐 | frontend-ui | `CodexAppExtension/App/StatusMenuView.swift`、`CodexAppExtensionUITests/MenuBarUITests.swift`、`CodexAppExtension/App/Settings/LayoutSettingsView.swift` | — | 四个标题共享左边界、四个 switch 共享右边界，交互/禁用/无障碍标识不变；设置页明确“最大宽度是上限” | XCUITest frame 对齐、控件存在与切换、设置文案 | UI 不直接操作配置/CDP；仍通过 AppModel action 提交 |
| U12 | 文档、全量验证与重装验收 | verification-docs | `README.md`、`.easy-coding/ABSTRACT.md`、`.easy-coding/TEST_STRATEGY.md` | U9, U10, U11 | 稳定 target、宽度/边距与菜单布局合同文档化；双审、全量 Core/PageRuntime/UI、Release 安装和用户视觉 smoke 全绿 | lint/typecheck/full tests/UI/`./install.sh`/菜单截图 | 最终证据绑定包含 U9-U11 的新指纹；不读取页面正文或 payload |
| U15 | 稳定 Target 身份与编辑器能力解耦 | runtime-qualification | `bootstrap.js`、`CDPPageRuntimeBridge.swift`、`TargetCoordinator.swift`、`focus-ring.js`、`ime-enter-guard.js` 及对应测试 | U9, U10 | layout + contained scroller 稳定时 Target 与宽屏不受 composer 挂载/浮层 editor 影响；IME 仅对 layout 内唯一且带原生 composer 信号的 editor 生效并可恢复 | live 结构 probe、无 editor/双 editor、0→1 editor fixture、TargetCoordinator 与 bridge probe 测试 | Target 身份是 layout 能力；composer 是可选输入能力，不得反向撤销布局增强 |

**执行策略**：parallel
- 已完成批次：U1 修复动态链接打包，U2 实现安装器，U3 同步文档并完成安装/冷启动验证。
- 新增第一批：U4 修正 CDP 求值合同并 shift-left 测试。
- 新增第二批：U5 修正 supersession 传播并补并发回归。
- 新增第三批：U6 更新知识文档，重新执行完整 Core、Release、安装、冷启动与 live smoke。
- 审查修复批次：U7 将跨 actor 健康顺序下沉到 `HealthCenter` 原子 generation API；完成后 U8 再跑完整交付链。
- 用户验收失败后新增并行批次：U9 target 生命周期稳定化 ｜ U10 wide-layout 自激与宽度合同 ｜ U11 菜单双列布局；三组生产代码与测试文件互不重叠。
- 最后：U15 修复 live CDP 暴露的身份耦合，再由 U12 双审、严格验证、一键重装与用户视觉验收。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| ExtensionCore install/load commands | 必测 | U1 | Release 包体静态审计 | `otool -L '<app>/Contents/MacOS/Codex App Extension'`；`otool -D '<app>/Contents/Frameworks/ExtensionCore.framework/Versions/A/ExtensionCore'` |
| Release bundle 可签名且嵌入完整 | 必测 | U1 | 构建/签名/Info/资源 | `xcodebuild ... -configuration Release ... build CODE_SIGNING_ALLOWED=NO`；`codesign --verify --deep --strict`；`plutil`；resource inventory |
| 安装器语法和命令合同 | 必测 | U2 | Shell 静态/帮助 | `/bin/bash -n install.sh`；`./install.sh --help`；危险路径/未知参数负向调用 |
| 首次安装、回滚目标和冷启动 | 必测 | U2/U3 | 当前主机集成 | `./install.sh`；安装后 `otool/codesign/plutil`；启动后进程至少存活 3 秒 |
| 重复安装幂等 | 必测 | U2/U3 | 当前主机集成 | 连续第二次 `./install.sh`，验证同包跳过或安全替换、无 `.installing.*`/`.backup.*` 残留 |
| 核心回归 | 必测 | U3 | XCTest | `xcodebuild ... test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO` |
| 工作树与文档一致性 | 必测 | U3 | 静态 | `plutil -lint`、`git diff --check`、README 参数与脚本 usage 对照 |
| 合法 undefined 脚本求值 | 必测 | U4 | XCTest fake CDP 返回 `result.type=undefined` 且无 `value` | `xcodebuild ... test -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests` |
| 查询值与异常严格性 | 必测 | U4 | XCTest 分别返回 missing value 与 `exceptionDetails` | 同上 |
| stale revision supersession | 必测 | U5 | pipeline fake bridge 在旧 target 抛 stale，随后最新 target 成功 | `xcodebuild ... test -only-testing:ExtensionCoreTests/RuntimeReliabilityTests` |
| live Runtime smoke | 必测 | U6 | 一键重装并观察扩展自身诊断状态 | `./install.sh`；菜单栏“运行健康检查”；不得读取页面 payload |
| Health generation 排列 | 必测 | U7 | XCTest 枚举 begin/update/remove 的旧代、同代、新代顺序 | `xcodebuild ... test -only-testing:ExtensionCoreTests/PerformanceBudgetTests` |
| 旧 cleanup 与新 revision 交错 | 必测 | U7 | 真实 bridge 阻塞旧 uninstall、完成新 apply、释放旧 invalidate | `xcodebuild ... test -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests` |
| target 事件与 runtime health 稳定 | 必测 | U9 | fake CDP 覆盖同 ID/同 URL、created-new→destroyed-old、info-changed 新 ID、unqualified/recovery；阻塞旧 refresh 后并发 stop/reconnect，释放后不得复活旧 runtime health | `xcodebuild ... test -only-testing:ExtensionCoreTests/RuntimeReliabilityTests`；`.../PerformanceBudgetTests` |
| target 真实身份变化 | 必测 | U9 | URL 改变仍 invalidate；新 ID 候选不被提前 invalidate；原位刷新失败仍可见且不得伪绿 | 同上 |
| 稳定 Target 身份与可选 editor | 必测 | U15 | layout + contained scroller 唯一时 composer 为 0/2 仍保留 Target；scroller 缺失拒绝；无原生 composer 标记或 floating editor 不进入 surface.editor；0→1 恢复不观察 null 且监听器只绑定一次 | `TargetCoordinatorTests`、`PageRuntimeTests/testSurfaceUsesStableLayoutIdentityAndTreatsEditorAsOptionalCapability`、`AdapterFixtureTests/testMissingComposerKeepsLayoutAdaptersHealthyAndRebindsFreshNativeComposer`、bridge probe 合同测试 |
| wide-layout observer 收敛 | 必测 | U10 | FakeStyle write-count + mutation burst；首次写入后相同 surface/config 的 RAF/settle 不再写 DOM | `xcodebuild ... test -only-testing:ExtensionCoreTests/AdapterFixtureTests` |
| 最大宽度与最小边距联合夹取 | 必测 | U10 | fixture 同时含 selected overlay 与原生 thread width consumer，断言 CSS 公式/选择器、composer/rail/menu 排除和卸载恢复 | 同上 |
| 菜单四开关双列对齐 | 必测 | U11 | XCUITest 比较四个 title 的 minX 和 switch 的 maxX，并执行一个 toggle | `xcodebuild ... test -only-testing:CodexAppExtensionUITests/MenuBarUITests` |

- **人工验收**：开启宽屏后持续观察至少 10 秒，菜单“合格 Target”保持同一 ID、不再与“无”交替；缩放 ChatGPT 窗口并分别使用较大最大宽度/非零最小侧边距，全部对话内容不越界且两侧至少保留配置边距；四个菜单开关形成整齐左右两列。
- **无法验证项**：Developer ID、公证、跨机器 Gatekeeper 和无管理员权限账户的实际 sudo 交互不在当前本地签名范围；脚本保留明确错误与手工重试路径。

### Workflow Mode
- **项目配置**：adaptive。
- **Session 覆盖**：无。
- **机械最低模式**：由 state API 重算；预计 strict（target 生命周期 + PageRuntime observer 反馈环 + UI/Release 多层验收）。
- **推荐并选择**：strict。
- **选择原因**：除实际 `/Applications` 替换外，本轮还修改 target 生命周期与 DOM observer 反馈环；任何过度忽略事件或过宽 CSS 选择器都会造成假稳定、reload 失效或宿主布局污染，必须以严格并发/幂等/视觉门禁收口。
- **状态内执行差异**：IMPLEMENT 对 U9/U10/U11 分单元 shift-left；REVIEW 同时检查 event 分类、observer 收敛、CSS scope 与 SwiftUI accessibility；VERIFICATION 运行 lint、Debug build、完整 Core/PageRuntime、菜单 UI、Release 安装和 10 秒 live visual gate；MEMORY 记录 target 元数据事件与 adapter 自激防护经验。

### 风险与注意事项
- 不能把 `/Library/Frameworks` 创建为 workaround；正确边界是 App 自带 framework + `@rpath`。
- 安装脚本中的清理和替换只允许作用于经过校验的明确 staging/backup/DerivedData 路径；任何空变量、根目录、`/Applications` 本身或不以 `.app` 结尾的目标必须拒绝。
- 构建、签名与安装可能多次运行；每一步必须从当前状态重新验证，不得仅凭进度文件假定成功。
- 当前工作树包含上一轮大规模未提交重构和 Harness 资产，本任务只追加上述十一个真实文件的差异，不回滚其他内容。
- `staleRevision` 只在 revision 已被新 target 生命周期推进时属于预期 supersession；实现必须精确分类，不能用宽泛 catch 静默真实故障。
- 禁止为 live 验证读取 ChatGPT 页面内容、对话 payload、cookie 或输入值；只检查扩展公开的连接、target、adapter 健康摘要。
- 不能依赖 Swift actor 的跨 actor 调用时序来推断先后；target health 的 generation 判断和写/删必须在同一个 `HealthCenter` actor 操作内完成。
- 同 ID/同 URL 的 targetInfoChanged 不能先把 active target 置空；原位刷新必须可幂等，失败时保持真实错误可见。
- wide-layout 自己管理的 marker/style/property 写入必须差异化；MutationObserver 覆盖 document 子树时，任何无条件写都可能形成反馈环。
- created/info-changed 的新 ID 采用同一 replacement 流程；runtime 临时健康写入必须携带 event loop 捕获的 lifecycle generation。
- target invalidation 是唯一语义入口：先以 lifecycle generation + target revision 写 runtime tombstone，再 invalidate bridge，并收敛 known/active；destroy、URL dequalification、replacement、stop 不得自行拼装清理步骤。
- canonical、Markdown 与 selected overlay 是统一候选集合；只允许每个分支最外层候选拥有 clamp，不能依赖某一种固定嵌套顺序。
- “最小侧边距”通过压缩并居中全部 thread width consumer 实现，不能只给 Markdown/主题节点增加 padding；最大宽度是上限而不是强制宽度。
