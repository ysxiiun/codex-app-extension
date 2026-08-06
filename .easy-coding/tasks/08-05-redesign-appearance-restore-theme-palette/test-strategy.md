# 测试策略：外观重设计、Markdown 恢复、焦点退役与菜单运行时修复

## 1. 可测试性分类

| 变更 | 类型 | 结论 | 原因 |
|---|---|---|---|
| 迁移前经典 Markdown palette 与独立重置 | 配置模型 | [must-test] | 用户要求恢复具体数据，必须逐字段锁定且证明不会覆盖布局/输入等无关草稿 |
| 焦点着色完整退役与旧配置兼容 | 配置/迁移/UI/资源 | [must-test] | 用户明确要求永远不由扩展着色，不能仅隐藏 UI；旧 JSON 必须可读且再保存不写出 focus 字段 |
| Markdown adapter 完整视觉合同 | 页面运行时 | [must-test] | 本次回归根因是值正确但 CSS 几何/优先级缺失，必须执行 production adapter 的 fixture 回归 |
| 颜色值预览与语义状态 | SwiftUI | [must-test] | `rgba/inherit` 没有预览是明确缺陷，需用可访问标识覆盖所有字段 |
| 响应式设置布局和滚动可达性 | SwiftUI | [must-test] | 遮挡属于明确可用性缺陷，必须验证默认/最小窗口和底部栏关系 |
| MenuBarExtra 重启二次确认 | AppKit/SwiftUI 生命周期 | [must-test] | 这是破坏性操作的显式确认边界，且现有独立测试 window 无法复现真实 popover 自动关闭 |
| 新聊天空态的 adapter waiting | JS/Swift 跨层状态协议 | [must-test] | 当前实况证明 observer 最终健康但菜单曾报四项降级；必须区分可恢复等待与硬失败，并验证自动收敛 |
| changed-adapter 配置事务 | Swift/JS 内部接口 | [must-test] | 最大内容宽度更新被无关 `ime-enter-guard` 阻断是明确现场缺陷，必须锁定精确派发和对称回滚 |
| 旧 PageRuntime 热升级与焦点副作用清理 | JS 生命周期/发布 | [must-test] | 只重装菜单栏 App 时 ChatGPT 页面可能保留旧 runtime；必须证明无需重启页面也删除 marker/style/variable/observer |
| waiting 状态的诊断隐私 | 固定健康摘要 | [must-test] | 新状态只能导出计数，禁止引入 DOM、target id、reason 自由文本或正文 |
| 当前 Codex 页面最终样式与无焦点侵入 | 集成 | [must-test] | fixture 不能替代升级后的真实宿主 computed style；使用隐私安全只读 CDP 样式/负向探针 |
| 与迁移前“主观观感完全一致” | 视觉感受 | [depends] | 自动化锁定值、规则和 computed style，最终审美感受仍由用户肉眼验收 |

## 2. 单元与 fixture 测试

| 测试点 | 归属单元 | 验证方式 | 通过条件 |
|---|---|---|---|
| 标题/强调/代码/引用值精确等于迁移前最终 `author-config` | U1 | `ConfigurationTests` 逐字段断言 | `#F2C94C`、800、`#df3079`、三组 rgba、`inherit` 全部一致 |
| `resetMarkdown` 不改其他配置 | U1 | 先构造全分区自定义草稿再调用 mutation | 仅 `features.markdownAppearance` 恢复 |
| 默认/高对比/自定义预设匹配稳定 | U1 | preset round-trip | 经典默认与高对比可识别，修改任一 Markdown 字段后为 custom |
| 标题和强调规则有受限作用域与 `!important` | U1 | 加载 production `markdown-semantic-theme.js` | 只命中 marker + qualified candidate，开关关闭时对应规则不存在 |
| 行内代码视觉合同 | U1 | fixture 检查生成规则 | 支持 candidate 与 `.inline-markdown`；文字/背景/1px 边框/6px 圆角/.08em×.36em padding；`pre code` 被排除并复位 |
| 引用块视觉合同 | U1 | fixture 检查生成规则 | 一级引用 3px 左边线、0 6px 6px 0 圆角、0 inline margin、.65em×.9em padding；嵌套引用不重复边框/背景/间距 |
| adapter 差异写入、资格失效与卸载 | U1 | 既有 runtime lifecycle harness | 重复 reconcile 不产生额外写入；失效/uninstall 恢复宿主 marker、变量、style 与 observer |
| focus 配置字段和 legacy key 退役 | U2 | decode 含 `focusRing` 的 schema-2 JSON，再 encode；迁移含 `layoutFocusRingFix` 的 legacy JSON | 读取不失败；新配置无 focus 字段；再保存不写出 focus；迁移报告标为 retired/ignored，不写运行配置 |
| focus 产品源码负向合同 | U2/U5 | `rg` 扫配置/UI/Registry/adapter/bundle/文档 | 不存在 `FocusRing`、`features.focusRing`、`data-cae-focus-ring`、`--cae-focus-ring-color`、`:focus-visible` 或 `focus-ring.js`；只允许 bootstrap 中 retired id tombstone |
| adapter 显式 recoverable 合同 | U4 | 四个 production adapter + bootstrap fixture | surface/editor/Markdown candidate 暂缺返回 `qualified=false/recoverable=true`；持久不兼容返回 false；未知缺省不可恢复 |
| 新聊天空态到完整页面 | U4 | 同 target SPA fixture 移除/恢复 layout、scroller、editor、candidate | observer 保留稳定 document-root 监听；waiting 后自动重新安装并全部 healthy；observer/RAF/timer 有界 |
| Bridge 初次 install/update 分类 | U4 | `CDPPageRuntimeBridgeTests` | recoverable waiting 不生成 error、不进入 failedAdapters、不阻断 update；hard unqualified/exception 仍 degraded 并按原规则阻断 update |
| adapter 选择集精确派发 | U4 | RuntimeController/Bridge doubles | wide-layout 变化只执行 `wide-layout`；header/IME/Markdown 各自只执行对应 id；global 变化和 nil 选择集执行全部四项；appearance-only 不执行 PageRuntime |
| 局部失败与对称回滚 | U4 | 注入未选 IME hard failure、已选 wide-layout success/failure | 未选 IME 失败不阻断宽度保存；wide-layout 自身失败阻断且 rollback 仍只执行 wide-layout；recoverable waiting 不阻断 |
| performance poll 三态收敛 | U4 | `PerformanceBudgetTests` + Runtime monitor | recoverable unqualified→waiting、恢复→healthy、三次超 8ms→degraded；waiting 不记 performanceBudgetExceeded |
| runtime-only 可靠性 helper 穷举 | U4 | `RuntimeReliabilityTests` 编译与既有回归 | 新 waiting case 显式覆盖；adapterIdentifier=runtime 的 helper 语义不变，runtime adapter 不产生 waiting |
| 诊断摘要和隐私 | U4 | `DiagnosticPrivacyTests` | healthy/waiting/degraded 分别计数；序列化结果无敏感 sentinel 和自由文本 |
| runtime implementation revision 热升级 | U5 | 先装旧五-adapter runtime/focus 副作用，再加载新 bootstrap | 旧 focus uninstall 被调用；marker/variable/style/observer/timer 清空；API 替换为新 revision；注册表只含四项；同 revision 再加载无额外写入/observer |

定向命令：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test \
  -only-testing:ExtensionCoreTests/ConfigurationTests \
  -only-testing:ExtensionCoreTests/AdapterFixtureTests \
  CODE_SIGNING_ALLOWED=NO
```

## 3. UI 测试

| 测试点 | 归属单元 | 验证方式 | 通过条件 |
|---|---|---|---|
| Markdown 实时预览完整 | U2 | XCUITest identifiers | 标题、正文/强调、行内代码、一级/嵌套引用和明暗预览切换均存在 |
| 所有保留颜色字段有预览 | U2 | 遍历 swatch identifiers | heading、strong、3 个 inline code、3 个 blockquote 共 8 个字段都有色块或语义状态 |
| `rgba(...)` alpha 与 `inherit/currentColor` 语义明确 | U2 | 默认状态与字段编辑 | rgba 显示透明色块；引用文字显示“继承正文”；非法值显示错误而非静默无预览 |
| 恢复迁移前经典配色 | U2 | 修改字段后点击恢复 | Markdown 预览和字段回到经典值，布局/输入等其他草稿保持修改值 |
| 外观页无焦点功能 | U2 | 查询旧 accessibility identifiers 和可见文案 | 不存在“键盘焦点”、`settings.appearance.focusRing/focusColor`、焦点预览或重置入口 |
| 无遮挡与可滚动 | U2 | 默认 900×640 和测试最小 760×540 | 当前可见控件不与底部 action bar 相交；最末引用背景字段可滚动到达且 hittable |
| 响应式排列 | U2 | 调整设置窗口宽度 | 宽模式编辑/预览并排，窄模式单列；不存在横向裁切 |
| 真实菜单栏取消重启 | U3 | 启动 `--ui-test-real-menu --ui-status=waiting`，点击 status item、确认入口和独立 alert 的取消 | popover 可自动关闭，alert 仍可点击；重新打开菜单仍显示“等待重启确认” |
| 真实菜单栏确认重启 | U3 | 同一路径点击 destructive“重启” | alert 响应成功；重新打开菜单不再显示待确认入口；fake runtime 仅收到一次确认 |
| 新聊天等待状态菜单 | U4 | UI fake runtime + 状态解析单测 | 标题为“等待页面就绪”，增强行为“X 项等待”，不出现“增强降级”；恢复快照后回到“运行正常” |

命令：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests build-for-testing

xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests test-without-building \
  -only-testing:CodexAppExtensionUITests/SettingsUITests \
  -only-testing:CodexAppExtensionUITests/MenuBarUITests
```

若 Xcode 26.6 runner 缺少 `lib_TestingInterop.dylib`，只按 README 修补并重签临时 DerivedData runner，不把 dylib 写入产品或工程。

## 4. 全量、Release 与在线验证

| 测试点 | 方式 | 通过条件 |
|---|---|---|
| 全量 Core/PageRuntime 回归 | README 的 `ExtensionCoreTests` xcodebuild 命令 | 全部通过，无既有 adapter/配置回归 |
| 编码、范围和文档 | `file -I`、`git diff --check`、工作树审计 | 编码保持；无空白错误；不覆盖用户既有改动 |
| Release 构建/签名/安装 | `./install.sh` | 静态审计、签名、幂等 swap、安装后审计和冷启动存活全部通过 |
| 当前 ChatGPT 页面 computed style（严格只读） | 只读 count/style-only CDP 探针 | 不执行配置写入、install/update/diagnose/uninstall；palette 变量与经典值一致；strong=800；inline code 有 1px 边框/6px 圆角；一级 quote 有 3px 左边线/目标圆角和 padding；嵌套 quote 已复位 |
| 当前 ChatGPT 新聊天 surface/observer 健康（严格只读） | 只读 count/style/status-only CDP 探针 + 菜单状态 | 不改变页面或运行配置；过渡期最多为 waiting，不记 degraded；layout/scroller/editor 出现后 observer `qualified=true/degraded=false`，菜单自动回到正常 |
| 宽度局部应用（隔离 fixture/专用测试 target） | 在隔离环境修改最大内容宽度并应用，保留一个未选 IME degraded fixture | 保存成功且只派发 wide-layout；未选择的 IME 不参与失败集合；wide-layout 自身失败仍回滚；禁止对当前 ChatGPT 页面执行此写入验证 |
| 焦点侵入负向现场 | 只读 selector/style/observer 探针 | 页面无 `data-cae-focus-ring`、`--cae-focus-ring-color`、`#cae-focus-ring-style`、focus observer；扩展不新增 `:focus-visible` 规则 |
| 卸载恢复与隐私（隔离 fixture/专用测试 target） | 仅在隔离环境执行临时 adapter diagnose/uninstall | 不读取正文、草稿、URL、Cookie、target id；宿主 marker/style/observer 恢复；禁止对当前 ChatGPT 页面执行 diagnose/uninstall |

## 5. 人工验收

- 外观页没有“键盘焦点”分区、开关、颜色或重置入口；Tab/点击后的焦点表现完全由 macOS/ChatGPT 原生样式决定。
- 外观页在默认窗口和缩到最小窗口时，预览、编辑区和底部“恢复默认/放弃/应用”互不遮挡；所有保留字段都能滚动到并修改。
- 切换预览明暗背景，半透明代码/引用背景和“继承正文”都容易辨认。
- 点击“恢复迁移前经典配色”后再应用，当前 Codex 的标题与强调为迁移前金色，行内代码为迁移前粉色样式，引用块有单层粉色左边线和浅背景，嵌套引用不重复套框。
- ChatGPT 未启用 CDP 时，从真实菜单栏打开“确认重启 ChatGPT…”，popover 即使自动关闭，独立确认窗也保持可操作；“取消”不重启，“重启”只执行一次。
- 连续创建多个新聊天：空白欢迎页可以短暂显示“等待页面就绪”，但不得显示“增强降级”；页面结构稳定后无需“重新注入/健康检查”即可自动回到全部正常。
- 在 IME adapter 已降级的测试状态下只调整“最大内容宽度”：应用成功，宽屏立即更新；只有 wide-layout 自身硬失败才拒绝并回滚。

## 6. 不测试项及原因

- 不测试 `appearance.colorScheme/accentColor` 的运行时行为：当前产品尚未消费这两个字段，本任务不扩大到全局主题系统。
- 不测试 ChatGPT 正文内容或草稿：在线验证只读取 selector 数量、CSS 变量和 computed style，不获取文本。
- 不自动覆盖用户现有自定义 Markdown V2 配置；显式经典恢复由模型和 UI 测试覆盖。删除的 legacy focus key 只做兼容读取/丢弃测试，不迁移成任何替代功能。
- 不把所有 `qualified=false` 都视为 waiting；只有 adapter 明确返回固定 `recoverable=true` 的页面暂缺状态才允许等待，其他不合格继续走硬失败测试。

## 7. 追加变更：彻底清理 Tab 功能残留

用户已确认 Tab 缩进增强没有保留价值。本轮不增加开关，而是从插件产品树中删除 Tab 专属 UI、迁移特判、资格 tombstone、测试夹具与文档说明；ChatGPT/macOS 原生 Tab 行为保持不变。

| 测试点 | 归属单元 | 验证方式 | 通过条件 |
|---|---|---|---|
| 产品树无 Tab 专属残留 | U9 | 对源码、测试、README 与架构摘要做定向 `rg` | `tab-indent`、`tabIndentEnhancement`、`settings.input.nativeTab`、`Tab 缩进`、`Tab 键` 均无结果 |
| 输入设置只保留 IME | U9/U10 | SwiftUI 编译与 Settings UI 定向测试 | 输入页存在中文输入保护，不存在 Tab 分区、说明、图标、开关或 identifier |
| 迁移兼容收敛 | U9/U10 | `ConfigurationTests` | V1 fixture 不再携带 Tab 字段；真实未知旧字段仍走通用 unknown 路径且不写入 schema-2 |
| FeatureRegistry API 清理 | U9/U10 | 编译与 `PageRuntimeTests` | 删除无消费者的 qualification decision 类型/数组；四个现役 adapter 注册、资源与 revision 6 合同不变 |
| IME Enter 修复不回归 | U10 | `AdapterFixtureTests` 的 IME 定向用例 | composition/Skill Enter、普通 Enter、disabled/uninstall 合同继续通过 |
| 全量业务回归 | U10 | ExtensionCore 全量 XCTest | 现有 Core/PageRuntime 测试全部通过，测试总数允许因删除无意义 Tab 专属用例而减少 |
| Release 与安装 | U9/U10 | `./install.sh` | 构建、静态审计、签名、幂等安装、冷启动全部通过 |

定向验证命令：

```bash
rg -n 'tab-indent|tabIndentEnhancement|settings\.input\.nativeTab|Tab 缩进|Tab 键' \
  CodexAppExtension CodexAppExtensionTests PageRuntimeTests README.md .easy-coding/ABSTRACT.md

xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tab-cleanup \
  test \
  -only-testing:ExtensionCoreTests/ConfigurationTests \
  -only-testing:ExtensionCoreTests/PageRuntimeTests \
  -only-testing:ExtensionCoreTests/AdapterFixtureTests \
  CODE_SIGNING_ALLOWED=NO
```

人工验收：设置 > 输入仅显示“中文输入保护”；不出现任何 Tab 标题、说明或配置入口；原生 Tab 焦点导航由宿主负责。XCUITest 若仍被 macOS Accessibility runner 阻断，只记录为环境限制，不能冒充 green；Core、静态扫描、Release 安装仍是硬门禁。
