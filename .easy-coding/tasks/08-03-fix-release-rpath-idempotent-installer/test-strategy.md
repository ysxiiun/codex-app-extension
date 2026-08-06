# 测试策略：Release 安装、Runtime 稳定性与宽屏布局

## 目标

证明 Release App 在脱离 Xcode 构建目录并安装到 `/Applications` 后，可以从自身 `Contents/Frameworks` 加载 `ExtensionCore`、保持有效本地签名并真实冷启动；同时证明 `install.sh` 可重复执行、失败可恢复且不会扩大 sudo 或清理范围。

## 分层门禁

### 1. 静态与脚本合同

- `/bin/bash -n install.sh`。
- `./install.sh --help` 退出 0，usage 与 README 一致。
- 未知参数、空路径、非 `.app` 安装目标、根目录/`/Applications` 级危险目标必须在 build/install 前拒绝。
- `plutil -lint CodexAppExtension/Supporting/Info.plist`、`plutil -lint CodexAppExtension.xcodeproj/project.pbxproj`、`git diff --check`。

### 2. Core 回归

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-installer-tests \
  test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO
```

必须保持现有配置、生命周期、CDP、PageRuntime、隐私和性能用例全部通过。

### 3. Release package audit

脚本构建后必须逐项执行并返回 0：

- App executable `otool -L` 精确包含 `@rpath/ExtensionCore.framework/Versions/A/ExtensionCore`。
- embedded framework `otool -D` 的唯一 install id 为同一 `@rpath`。
- 两处均不得出现 `/Library/Frameworks/ExtensionCore.framework`。
- `codesign --verify --deep --strict --verbose=2` 通过。
- built Info 为 bundle `com.ysxiiun.codexappextension`、`LSUIElement=true`、最低 macOS 13。
- `Contents/Frameworks/ExtensionCore.framework` 存在，JavaScript resources 仍严格为 bootstrap + 五 adapters。

### 4. 安装事务与幂等

首次 `./install.sh`：

- 已运行旧 App 仅通过 bundle id 请求正常退出；超时应中止而不 kill。
- 新包先复制到目标同级 `.installing.<pid>` 并完成 audit。
- 已安装包移动到 `.backup.<pid>` 后再完成 swap；失败时 trap 恢复 backup。
- 成功后清理当前 PID 的 staging/backup，不匹配的陌生文件不删除。

第二次 `./install.sh`：

- Xcode 使用同一 DerivedData 增量构建。
- built 与 installed 完全一致时可跳过 swap；不一致时仍安全替换。
- 最终无当前脚本遗留的 staging/backup，已安装包继续通过全部 audit。

### 5. 真实冷启动

- 默认安装结束后用 exact bundle path 启动，不依赖 Xcode test runner。
- 最多等待 10 秒进入 running，随后再等待至少 3 秒并确认仍 running。
- 进程退出则输出最近 crash report 位置并失败。
- 冷启动成功后人工确认菜单栏图标/状态窗口；自动化不声称验证多显示器弹层位置。
- 本次修复后不得新增 `Library missing: /Library/Frameworks/ExtensionCore.framework` crash。

## 通过标准

- lint、typecheck、Core tests、Release build、package audit、首次安装、第二次幂等安装、installed audit 和 cold-launch survival 全绿。
- 安装脚本没有模糊 `pkill/kill`、没有以 sudo 运行构建、没有对未校验路径执行递归清理。
- README、ABSTRACT、TEST_STRATEGY 的命令和参数与脚本一致。
- 未解决的真实菜单栏视觉、多显示器定位、公证/跨机分发必须显式保留为人工或范围外项。

## 用户视觉验收失败后的增补门禁

### 1. same-target 生命周期稳定

- fake CDP 对同一个 target 连续发送同 ID、同 URL 的 `Target.targetInfoChanged`；事件处理期间和完成后 `activeTargetIdentifier()` 始终保持原 target，不得出现中间 `nil`。
- 同 ID、同 URL 允许重新 probe/apply，以覆盖页面 reload 后的新 JavaScript context；不得把清空 active target 或 bridge invalidate 当作刷新前置。
- 同一元数据事件 burst 不得留下 stale/degraded health，也不得让菜单摘要在 target ID 与“无”之间交替。
- URL 真实变化、target identity 真实变化仍必须 invalidate 旧 revision；原位刷新发生真实错误时仍需进入可见健康状态，不能为追求稳定而吞错。
- 新 ID 由 `Target.targetCreated` 到达时也必须先 probe/apply，成功后原子切 active 并 invalidate 旧 ID；覆盖随后只收到旧 target destroy、没有新 target info change 的顺序。
- pipeline event loop 捕获独立 runtime lifecycle generation；阻塞旧 refresh、并发 stop/reconnect、再释放旧结果后，HealthCenter 不得出现旧 target 的 runtime healthy/degraded 行。新 lifecycle 的状态不得被旧代 clear/remove 影响。
- 每个 target refresh 还必须捕获单独递增的 target revision；统一 invalidation 写入该 revision 的 tombstone。覆盖先产生 runtime degraded、再收到同 ID URL change 且没有 destroy 的路径，最终 active=nil 且旧 target 不含 runtime/adapter health；失效前启动的旧 refresh 释放后也不能复活。

定向命令：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-runtime-tests \
  test -only-testing:ExtensionCoreTests/RuntimeReliabilityTests CODE_SIGNING_ALLOWED=NO
```

### 2. wide-layout observer 收敛

- 首次安装 adapter 可以写 marker、style 与 CSS properties；相同 surface/config 的重复 reconcile 必须返回真实 no-op，`FakeStyle.writeCount` 不增加。
- adapter 自己创建或更新 style 后触发的全 document MutationObserver，经过 RAF/settle 后必须收敛；不得持续排队 timer/RAF 或重复写 DOM。
- surface 被真实替换时仍需重新绑定并应用配置；幂等不能退化成忽略新的宿主节点。
- uninstall 必须完整恢复 adapter 拥有的 marker、style 和属性，且重复卸载安全。
- `PageRuntimeTests.swift` 中既有默认配置断言必须期待 `min(1800px, max(1px, calc(100% - 64px)))`，并与 adapter fixture 的公式合同保持一致；不得保留固定 `1800px` 假设。

### 2.1 稳定 Target 身份与可选编辑器能力

- Target 身份只由唯一 `[data-app-shell-main-content-layout]` 与其内部唯一 `.thread-scroll-container` 构成；composer 数量为 0、全局仅存在主布局外 floating editor、或布局内 editor 暂时歧义时，不得撤销 Target 或宽屏布局。
- `surface.editor` 只能是主 layout 内唯一且带原生 `data-codex-composer="true"` 信号的 ProseMirror；缺失、无原生信号或歧义时为 `null`。MutationObserver 不得对 `null` 调用 observe。
- focus ring 在 editor 缺失时继续只处理 layout；IME guard 精确报告 `native-editor-not-unique`，真实 editor 恢复后重新绑定监听器。
- editor 0→1 生命周期必须证明旧 editor marker/监听器清理、新 editor 三类监听器各一次、uninstall 完整恢复。
- live CDP 结构门禁只读取 selector 数量、包含关系、几何和 adapter 元数据，不读取页面正文或用户 payload。

### 3. 最大宽度与最小侧边距联合合同

- 保存的 `maximumContentWidth` 只是上限，不随窗口缩放回写；实际 thread 内容宽度使用 `min(配置上限, 100% - 2 × minimumSidePadding)`。
- fixture 同时包含 selected overlay 与原生 thread width consumer；两类内容必须共享同一有效宽度合同，不能只命中 Markdown/增强主题内容。
- 当配置上限大于当前可用宽度时，不得横向溢出或越过最小侧边距；配置上限较小时仍按该上限居中显示。
- composer、right rail、menu/listbox 与浮层必须作为负向用例保持原生宽度；只有同时具备原生 top/bottom inset shell 信号的持久 right rail 可参与边界计算，真实 rail 内打开 menu/listbox/dialog 时仍保留同一边界，而 `pointer-events:none` 的临时浮层外壳不得入选。
- 原生 right rail shell 仅是候选容器，不代表当前响应式布局仍显示环境面板；只有 shell 内带实际背景、阴影或边框的面板实体与聊天视口存在当前渲染交集时才预留其边界。面板被 Codex 响应式移出视口后，即使 316px shell 仍留在 DOM，也必须立即释放宽度。
- rail shell 内的 menu/listbox/dialog 及其后代始终是临时浮层，哪怕自身带背景、阴影、边框且仍可见，也不得被当作环境面板实体或加入 panel-body ResizeObserver 目标；真实面板隐藏或移出视口后必须释放宽度。
- 宽度重算由当前 DOM 渲染几何驱动，不复制 Codex 的响应式阈值；`ResizeObserver` 必须动态绑定 layout/scroller、原生 rail shell 与当前具备绘制外观的面板实体，rail 子树的 class/style/visibility/child 变化还需由局部 `MutationObserver` 捕获；所有事件与 window resize 合并到单个 RAF，uninstall 时完整断开。
- 测试桩只允许实际 observe 了 rail shell/面板实体的 observer 收到对应 resize 回调，不能用广播所有 observer 的假事件掩盖漏绑。
- Codex 在部分分栏宽度会先对 thread 内容父层施加原生横移；扩展必须分别读取每个最外层 content/composer owner 到 scroller 之间的当前 transform/translate，只给该 owner 补足目标 rail 居中位移与原生位移的差值。原生 `-150px` 加目标 `-150px` 时该 owner 的扩展 offset 必须为 `0px`，原生过度左移时允许正向抵扣；没有实际渲染 rail 时所有扩展 offset 强制为 `0px`。相关父层只观察自身 class/style 等几何属性，不监听正文子树。
- 原生父层或 rail 实体进入 CSS transition/animation 后，扩展必须只在这些几何节点自己的 motion 生命周期内逐 RAF 重算，并在 end/cancel 后做最终收敛；子孙流式内容的 motion 事件不得启动此循环，uninstall 必须清理 motion listener 和尚未执行的 RAF。
- 尚未绘制或刚插入的真实 rail body 由持久 shell 委托接收冒泡 motion 事件，不能等到 painted qualification 后才直绑；menu/listbox/dialog 后代仍必须拒绝。观察集合 churn 只能删除已离场节点的 motion 状态，保留节点正在进行的 RAF 不能被清空。
- 祖先 `matrix()`、纯平移 `matrix3d()` 与独立 `translate` 可组合计入原生位移；带 scale/rotate/perspective 的矩阵不按局部 m41 猜测视口位移，必须忽略该矩阵分量并保持保守扩展位移。
- canonical、Markdown consumer、selected overlay 的所有正反向嵌套都必须验证：只有最外层原生 content/composer consumer 可以成为 width owner；Markdown consumer、selected overlay 及其后代必须保持 `0` 个增强 owner，并通过外层原生 owner 间接共享有效宽度，不能重复应用百分比夹取。

定向命令：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-page-runtime-tests \
  test -only-testing:ExtensionCoreTests/AdapterFixtureTests \
       -only-testing:ExtensionCoreTests/PageRuntimeTests CODE_SIGNING_ALLOWED=NO
```

### 4. 菜单四开关双列对齐

- 四个标题的 `minX` 在 UI 测试容差内一致，四个 switch 的 `maxX` 在容差内一致。
- 四个 accessibility identifier、enabled/disabled 状态、点击后的 AppModel action 均保持可用。
- 设置页明确显示“最大内容宽度是上限，实际宽度受可用区域与最小侧边距限制”的说明。

定向命令：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests \
  build-for-testing
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests \
  test-without-building -only-testing:CodexAppExtensionUITests/MenuBarUITests
```

### 5. 最终严格验收

- 两个独立 review 维度同时通过，并绑定包含 target、wide-layout 与菜单 UI 修改的最终实现指纹。
- shell/plist/diff lint、Debug build、完整 `ExtensionCoreTests`、完整 `PageRuntimeTests`、菜单 XCUITest 全绿。
- 重新运行 `./install.sh`，验证 Release build、签名、安装包 audit、原子替换和冷启动存活。
- 安装后保持宽屏增强开启至少 10 秒，菜单“合格 Target”稳定为同一 ID；窗口缩放期间不闪烁，全部 thread 内容不越过两侧最小边距，最大宽度只作为上限。
- 最终菜单截图确认四行标题左对齐、switch 右对齐。自动化仍只读取扩展自身健康摘要，不读取 ChatGPT 页面正文或 raw CDP payload。

## 运行时兼容增补门禁

安装与冷启动门禁通过后，必须继续证明 live CDP 注入合同：

- bootstrap 和五个 adapter source 的 `Runtime.evaluate` 返回 `result: { type: "undefined" }` 且不含 `value` 时，视为合法 side-effect 完成，随后 handshake 与 envelope 必须继续执行。
- surface probe、handshake、adapter execute、performance snapshot 等 value-returning 表达式缺失 `result.value` 时仍必须失败，不能将缺失值泛化成 `.null`。
- 任意 `Runtime.evaluate` 响应包含 `exceptionDetails` 时必须失败；不能因为 remote object 存在或 side-effect 调用而吞掉 JavaScript 异常。
- 精确的 `PageRuntimeBridgeError.staleRevision` 表示旧 target 异步结果被新 revision 取代：target 轮询应继续，事件激活应静默丢弃，且不得写入 runtime degraded health；其他错误仍按原行为发布。
- 定向测试先运行 `CDPPageRuntimeBridgeTests` 与 `RuntimeReliabilityTests`，再运行 `ExtensionCoreTests` 全量。
- CDP 延迟错误测试桩按 `Runtime.evaluate` 方法边界阻塞 probe，不得依赖 probe JavaScript 的内部变量名或源码片段，否则 selector 重构会把失败覆盖退化为永久等待。
- 最终重新执行 `./install.sh`；用户可见 smoke 必须确认已知两条错误消失并出现合格 target。live 自动化只读取扩展自身健康摘要，不读取 ChatGPT 页面内容或用户数据。
- `HealthCenter` 必须以 generation/tombstone 原子处理 target 状态：低代 update 被拒绝；同代 remove 后迟到 update 被拒绝；新代 begin 清空旧 adapter 状态；旧代 remove 不影响新代。
- 必须增加真实 bridge 交错测试：阻塞旧 session uninstall，在其 await 期间让同 target 新 revision attach/apply 并写入健康状态，再释放旧 cleanup；最终只保留新 revision 健康状态。
