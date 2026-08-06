# Codex App Extension

Codex App Extension 是一个面向 ChatGPT Codex 工作区的原生 macOS 菜单栏应用。它通过仅绑定回环地址的 Chrome DevTools Protocol（CDP）连接 ChatGPT，在确认目标页面和原生界面锚点唯一后，安装可独立卸载的页面增强。

当前发布树只有 SwiftUI + ExtensionCore + PageRuntime V2；旧 Shell/Node 注入链路已经移除，不存在 legacy fallback。本项目不会修改 `/Applications/ChatGPT.app`、账号数据或会话文件，也没有公开更新器、预构建安装包或已公证分发。

## 功能

- 菜单栏常驻状态：运行正常、连接中/等待确认、增强降级、ChatGPT 未运行或扩展停用。
- 宽屏布局：调整会话内容最大宽度与最小侧边距。
- 顶部栏避让：自动读取原生工具栏 offset，或使用自定义像素值；只作用于通过资格审查的唯一布局根，避免嵌套根重复偏移。
- 中文输入保护：在 ProseMirror 输入法组合态、`keyCode=229` 或组合结束后的 `120 ms` 有界宽限期拦截 Enter；宽限期后的普通 Enter 保持 ChatGPT 原生行为。
- Markdown 语义外观：只在合格会话滚动区中增强标题、强调文本、行内代码和引用块；代码块保持原生样式。
- 五页原生设置：通用、布局、输入、外观、兼容与诊断。
- 配置事务：有合格 target 时只预应用发生变化的 adapter；离线时先持久化并在后续连接时安装，在线预应用或持久化失败只回滚相同 adapter，并保留最后可用配置。扩展总开关变化仍应用全部 adapter。
- 脱敏诊断：复制固定字段摘要，或导出 allowlist 配置摘要、健康摘要、诊断事件和 manifest。

PageRuntime 只注册四个 adapter：`wide-layout`、`header-offset`、`ime-enter-guard` 和 `markdown-semantic-theme`。焦点着色没有配置模型、注册项或产品资源。

## 系统要求

- macOS 13 或更高版本。
- Xcode（项目当前使用 Xcode 26.6 验证）。
- `/Applications/ChatGPT.app`，bundle id 为 `com.openai.codex`。

Codex App Extension 自身的 bundle id 是 `com.ysxiiun.codexappextension`，并以 `LSUIElement=true` 运行，因此正常情况下不会显示 Dock 图标。

## 构建与安装

推荐在仓库根目录直接运行一键安装器：

```bash
./install.sh
```

脚本按八个可见阶段完成预检、增量 Release 构建、本地 ad-hoc 签名、构建包审计、同级暂存/替换、安装包审计、启动和存活检查。默认安装到 `/Applications/Codex App Extension.app`，并复用 `/tmp/codex-app-extension-release`，因此中断后重跑会继续使用 Xcode 增量产物。已安装包与新包一致时跳过替换，但仍重新审计并检查运行状态；替换失败或新包冷启动失败时自动恢复旧 App。

可用参数：

```bash
./install.sh --help
./install.sh --clean
./install.sh --no-launch
./install.sh --derived-data /tmp/codex-app-extension-release-custom
./install.sh --install-path '/Applications/Codex App Extension.app'
./install.sh --audit-only '/tmp/codex-app-extension-release/Build/Products/Release/Codex App Extension.app'
```

`--clean` 只清理经过校验且属于当前 Xcode 工程的 DerivedData；`--no-launch` 仍完成安装后包体审计，但明确不提供冷启动证据；`--audit-only` 只审计指定 App 的包体、签名、固定五个 JavaScript 资源以及已废弃键盘焦点标记，不构建、不安装、不启动。不要用 `sudo ./install.sh`：构建和签名始终以当前用户运行，只有安装父目录不可写时，脚本才对同级暂存、替换、回滚和清理命令请求 `sudo`。

需要手工排查时，可只构建并检查产物：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
codesign --force --sign - --timestamp=none \
  '/tmp/codex-app-extension-release/Build/Products/Release/Codex App Extension.app/Contents/Frameworks/ExtensionCore.framework'
codesign --force --sign - --timestamp=none \
  '/tmp/codex-app-extension-release/Build/Products/Release/Codex App Extension.app'
```

重要签名说明：仓库没有 Developer ID、公证或公开分发流程。`install.sh` 生成的是供本机运行的 ad-hoc 签名产物；包体审计和冷启动成功不代表 Apple 公证，也不保证复制到另一台 Mac 后能通过 Gatekeeper。本项目不声称提供自动更新能力。

## 启动与日常使用

安装后启动：

```bash
open -a 'Codex App Extension'
```

应用出现在菜单栏。状态窗口提供：

- ChatGPT、CDP、合格 Target 和 adapter 健康状态；
- 扩展总开关、宽屏布局、中文输入保护、Markdown 外观快速开关；
- 启动 ChatGPT、重新连接、重新注入、健康检查和打开设置；
- 当 ChatGPT 已运行但没有 CDP 时，显示“确认重启 ChatGPT…”动作。

Codex App Extension 只匹配 `/Applications/ChatGPT.app` 的有效主进程，不匹配 Renderer/Helper。若 ChatGPT 尚未运行，扩展会使用随机 `49152...65535` 高位端口启动它，并传入：

```text
--remote-debugging-address=127.0.0.1
--remote-debugging-port=<动态端口>
```

只有进程参数同时且唯一包含 `--remote-debugging-address=127.0.0.1` 与有效动态端口时，扩展才会复用现有 CDP；缺失地址、`0.0.0.0`、`::1`、`localhost`、其他地址或重复参数均进入确认式重启路径。若正在运行的 ChatGPT 没有可复用 CDP，扩展不会自行终止它；只有用户在独立的 App-modal `NSAlert` 中再次确认后，才会请求 ChatGPT 正常退出并以动态回环端口重新启动。确认框不依附菜单栏 popover，因此点击取消或重启不会因菜单自动收起而失效。重启可能丢失尚未发送的输入或运行状态，请先自行确认页面安全。

Target 需要同时满足 `app://-/index.html` 和两个唯一原生身份锚点：布局根及其内部的会话滚动区。主编辑器是可选能力，只有布局内唯一且带 `data-codex-composer="true"` 原生信号的 ProseMirror 才会启用输入相关 adapter；它缺失、歧义或仅存在于布局外浮层时，不撤销 Target 与宽屏布局。同一 target 内 SPA 替换这些节点时，稳定 document-root observer 会自动重新资格审查并让相关 adapter 重新绑定。adapter 健康采用三态：已满足资格为正常；新页面暂时没有锚点、Markdown candidate 或宽度 owner 等可恢复情况为等待；结构冲突、执行错误或性能预算超限才是降级。等待中的 adapter 会在 DOM 就绪后自动恢复，不触发配置事务回滚。同 ID、同 URL 的 target 元数据变化会原位刷新 runtime，期间菜单继续保留当前“合格 Target”；`targetCreated` 或 `targetInfoChanged` 带来的合格新 ID 会先完成 probe/install，再原子切换 active target 并清理旧 ID。event loop 的临时 runtime 健康状态同时携带 lifecycle generation 与 per-target revision；destroy、URL 失格、replacement 和 stop 统一先写 target tombstone，再清 bridge/known/active，因此同连接或 reconnect 后迟到的旧事件都不能复活状态或抢回 active target。任何 selector 不唯一、目标 reload、adapter 异常或超出性能预算时，扩展失败开放或只影响对应 adapter，不终止 ChatGPT，也不强行接管未知页面；target 失效、pipeline stop 和 App 退出均先有界卸载全部 adapter 再 detach。

PageRuntime V2 当前固定实现 revision 为 `6`。同 revision 重复注入直接复用现有 runtime，不新增 observer、RAF 或 timer；检测到 revision 5 或更旧/缺失 revision 时，先通过旧 runtime API 尽力卸载历史增强（包括已经退役的焦点着色），再原位替换不可配置的全局 runtime 对象。若配置更新只涉及部分 adapter，新 runtime 会先以当前完整配置补水四个 adapter，再执行所选 adapter 的事务更新；补水中无关 adapter 的降级不会误判为所选更新失败。显式 install/update 抛错后，失败签名不会与旧配置命中幂等快路；observer 健康恢复也不会覆盖该签名，必须由后续成功的显式 install/update 写入正式配置签名。

## 设置

### 通用

- 启用/停用整个扩展。
- 登录时启动。
- 启动扩展后自动打开设置。

“登录时启动”使用 macOS `SMAppService.mainApp`。若界面显示需要批准，请前往“系统设置 > 通用 > 登录项”批准；扩展不会把 `requiresApproval` 或失败状态伪装成已启用。

### 布局

- 宽屏布局开关。
- 最大内容宽度：`480...4096 px`，默认 `1800 px`；保存值是上限，不会随窗口缩放改写。
- 最小侧边距：`0...160 px`，默认 `24 px`；对全部 thread 主内容生效，而非只对 Markdown 外观增强内容生效。
- 顶部栏避让：自动或自定义。
- 自定义顶部 offset：`0...200 px`，默认值 `46 px`。

实际 thread 内容宽度按 `min(配置的最大内容宽度, 当前可用宽度 - 2 × 最小侧边距)` 计算，并在左侧内容边界与持久右栏左边界之间居中。只有最外层原生 content/composer width owner 接受一次宽度夹取和整体位移；其自身原生纯平移 transform 与祖先原生位移计入 native offset，扩展拥有的 individual translate 则从测量中排除，避免 residual offset 自反馈。Markdown consumer、selected overlay 及其后代是严格负向范围，流式文本叶节点不接收宽度、边距、padding、translate 或对齐覆盖。输入框、右侧栏、菜单、对话框与浮层保持原生宽度。V2 只写入通过 surface probe 的唯一原生根。过去多层布局根导致 offset 累加、Markdown 根随升级变化的经验，已收敛为“唯一锚点 + adapter 自身 marker + 差异写入 + 完整卸载恢复”的合同；没有旧 selector 回退。

### 输入

- 中文输入保护拦截组合输入期间、`keyCode=229` 和组合结束后 `120 ms` 内的 Enter；之后普通 Enter 不拦截。

### 外观

- 经典、高对比度和自定义预设。
- Markdown 总开关。
- 标题与强调文本开关、颜色和强调字重。
- 行内代码文字/背景/边线颜色。
- 引用块边线/文字/背景颜色。

经典预设还原迁移前的作者配色：标题和强调文本为 `#F2C94C`（强调字重 `800`）；行内代码文字为 `#df3079`、背景为 `rgba(223, 48, 121, 0.10)`、边线为 `rgba(223, 48, 121, 0.18)`；引用边线为 `#df3079`、文字为 `inherit`、背景为 `rgba(223, 48, 121, 0.06)`。

外观页按窗口宽度响应式排版：宽窗口中编辑器与实时预览并排，窄窗口中预览在上、编辑器在下并统一滚动。预览可切换明暗背景，覆盖标题、正文、强调、行内代码以及嵌套引用；每个颜色字段都提供有效色块、语义色标签或无效提示，支持 `#RRGGBB`、带透明度的十六进制、`rgb/rgba` 及 `inherit/currentColor`。预设和字段编辑只更新草稿；点击“应用”后才会预应用并保存。可以重置 Markdown、恢复经典外观或放弃草稿。扩展不再提供键盘焦点着色，页面保持 ChatGPT/macOS 原生焦点表现。

### 兼容与诊断

- 查看版本、ChatGPT、CDP、Target、adapter 和迁移报告摘要。
- 重新连接、重新注入、运行健康检查。
- 复制诊断摘要或导出诊断包。
- 通过原生 URL `codex://settings` 打开 Codex 官方设置。

## 配置、迁移与备份

V2 配置由设置界面维护，不再通过环境变量、命令行参数或仓库作者配置覆盖。

配置目录：

```text
~/Library/Application Support/Codex App Extension/
```

主要文件：

```text
config.json
config.last-known-good.json
migration-report.json
Diagnostics/diagnostics-0.jsonl ... diagnostics-4.jsonl
```

`config.json` 使用 `schemaVersion=2`。保存采用原子写入；首次保存先建立 `config.last-known-good.json` 再提交 `config.json`，已有可用配置则在更新前把旧版本写入 LKG。任一 LKG 写入失败都不会提交新的 current。当前配置损坏时，运行时可以使用最后可用配置并保留损坏文件作为证据；只有显式恢复操作才覆盖当前配置。

首次启动且 V2 配置不存在时，扩展会检查旧位置：

```text
~/.codex-app-extension/config.json
```

迁移前会创建一次性备份：

```text
~/.codex-app-extension/config.v1.backup.json
```

可迁移内容包括宽屏开关/宽度、顶部 offset、IME 以及 Markdown 标题、强调和主题颜色。未知或无效字段只进入迁移报告，不进入 V2 运行配置。`longTextSendEnhancement` 记录为原生替代；旧焦点开关、固定 CDP 端口、DOM 调试快照、legacy selector override 和旧配色预览字段记录为废弃。V2 配置一旦存在，迁移不会重复覆盖它。

## 诊断与隐私

诊断事件采用固定类型模型，只能表示：

- 时间戳、App/Runtime 数字版本；
- 固定事件类型、状态和错误码；
- selector 数量、事件数量和耗时。

它没有承载任意 payload、URL、target id 或自由文本的字段，因此不会记录对话正文、尚未发送的输入、Cookie、完整 DOM、CDP payload 或 WebSocket frame。日志存放在 Application Support 的 `Diagnostics` 目录，默认每个文件最多 `1 MiB`、最多 `5` 个文件。

“复制摘要”把固定字段文本写入剪贴板。“导出诊断”在系统临时目录创建一个目录并在 Finder 中显示，内容固定为：

```text
configuration-summary.json
health-summary.json
diagnostic-events.json
manifest.json
```

导出配置只是 allowlist 摘要，例如 schema、扩展开关、启用功能数量、登录启动和日志保留；不会复制完整配置、颜色值、迁移详情或原始日志文件。导出失败会在设置界面显示原因，不影响运行时。

## 测试

运行全部 ExtensionCore、PageRuntime fixture、隐私、性能和恢复单元测试：

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test \
  -only-testing:ExtensionCoreTests \
  CODE_SIGNING_ALLOWED=NO
```

编译 App、Core tests 和 UI tests：

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests \
  build-for-testing
```

运行 UI tests 时应保留默认本地签名，不要添加 `CODE_SIGNING_ALLOWED=NO`：

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests \
  test-without-building \
  -only-testing:CodexAppExtensionUITests
```

Xcode 26.6 在部分 macOS 环境会生成缺少 `@rpath/lib_TestingInterop.dylib` 的 UI test runner，runner 会在产品 App 启动前被 dyld 终止。这是测试 runner materialization 问题，不是产品崩溃。首选 workaround 是使用上面的默认本地签名重新 `build-for-testing`；若 Xcode 仍遗漏 dylib，验证时只能把：

```text
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/lib_TestingInterop.dylib
```

复制到临时 DerivedData 中生成的 `CodexAppExtensionUITests-Runner.app/Contents/Frameworks/`，再重签临时 runner 后执行。不要把该 dylib 加入产品 App、Xcode 工程或发布包。这个 workaround 只属于测试章节。

任何 current ChatGPT live probe 都必须严格只读且非破坏性：不能重启、发送消息、读取正文或草稿、保存配置，也不能临时 install、update、diagnose 或 uninstall adapter；只允许读取 exact target 数量、selector 数量、runtime handshake/hydration 与现有 adapter performance snapshot。

adapter install/diagnose/uninstall 生命周期门禁只能在隔离 fixture 或专用测试 target 中执行，并必须验证卸载后 DOM、样式、observer 与配置状态完全恢复；不得把当前用户正在使用的 ChatGPT 页面当作生命周期测试环境。

## 已移除的旧能力与入口

V2 不再提供：

- Shell 启动、当前实例重注入、交互配置和作者配置脚本；
- Node/cua_node 运行时与单文件注入器；
- 环境变量或 CLI 配置覆盖，包括旧 `CODEX_WIDE_*` alias；
- 固定调试端口 `9229`；
- 键盘焦点着色；
- 长文本发送注入（使用 ChatGPT/Codex 原生发送行为）；
- 仓库内的 strong text HTML 配色预览；
- 旧版独立 Codex App 路径和 selector fallback。

配置、健康检查和重新注入全部通过菜单栏 App 完成。官方 Codex 设置通过 `codex://settings` 打开。

## 卸载

1. 在“通用”设置中关闭“登录时启动”；若系统仍显示该登录项，在“系统设置 > 通用 > 登录项”中移除或禁用。
2. 退出 Codex App Extension。
3. 删除 `/Applications/Codex App Extension.app`。

删除 App 不会修改 ChatGPT 包体或会话。如果页面仍显示一次运行期样式，先保存未发送内容，再正常退出并重新打开 ChatGPT；页面增强不写入 ChatGPT 的持久数据。

如需同时清除 V2 配置、最后可用配置、迁移报告和诊断日志，可自行删除：

```text
~/Library/Application Support/Codex App Extension/
```

旧 V1 配置和 `config.v1.backup.json` 不会在卸载时自动删除，便于审计或手工恢复；是否清理 `~/.codex-app-extension/` 由用户自行决定。

## 项目边界

这是非官方本地增强项目。ChatGPT 的 DOM 和 CDP 行为不是公开稳定 API，升级后 adapter 可能降级。项目的安全边界是：精确 App/target 匹配、唯一原生 selector、失败开放、单 adapter 隔离、显式重启确认、回环地址、配置回滚、隐私 allowlist 和可验证卸载。
