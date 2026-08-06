# 测试策略：Codex App Extension macOS 菜单栏运行时 V2

## 目标

用分层自动化和当前 ChatGPT live gate 证明原生菜单栏、Swift 运行时、页面 adapters、配置迁移、失败回滚、隐私和旧链路切换同时可靠。静态 `app.asar` 锚点只能作为辅助证据，不能替代真实页面行为。

## 环境基线

- macOS 当前主机，目标最低版本 macOS 13。
- Xcode `26.6`、Swift `6.3.3`。
- 当前目标 `/Applications/ChatGPT.app` `26.727.51351`，build `6119`，bundle id `com.openai.codex`。
- 当前 Codex 页面 target `app://-/index.html`；现有实例的 CDP `127.0.0.1:9229` 仅作迁移前取证，V2 必须使用随机回环高位端口。
- 新项目不依赖第三方 Swift package、npm 或系统 Node。

## 标准命令

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Release -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
plutil -lint CodexAppExtension/Supporting/Info.plist
git diff --check
```

在实现目标可单独运行时，定向命令为：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test -only-testing:ExtensionCoreTests
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test -only-testing:PageRuntimeTests
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -destination 'platform=macOS' test -only-testing:CodexAppExtensionUITests
```

## 分层测试

### U1 原生基础与配置

- `AppConfiguration` 默认值、值域、`Codable` 往返和未知 schema 拒绝。
- V1 有效字段到 V2 分组字段的精确映射。
- 缺失 `horizontalGutter` 等字段使用 V2 安全默认值。
- `longTextSendEnhancement` 进入 `nativeReplacement`，不生成页面 adapter。
- 未知/废弃/无效字段只进入迁移报告。
- 同目录临时文件、同步、原子替换和 `last-known-good` 回滚。
- V1 文件备份、重复迁移幂等、迁移失败不覆盖源文件。
- `Info.plist` 包含 `LSUIElement=true`，bundle id 为 `com.ysxiiun.codexappextension`。

### U2 生命周期与 CDP

- App 未运行、运行无 CDP、等待确认、用户取消、用户确认、连接、探针、活动、降级、断线和重连状态。
- 只识别 bundle id `com.openai.codex` 的 `ChatGPT.app` 主进程，不命中 helper 或旧 `Codex.app`。
- 随机高位端口冲突重选，HTTP readiness 只接受回环端点。
- 未确认前不执行 terminate/forceTerminate/open。
- `URLSessionWebSocketTask` 文本/数据帧、请求超时、取消、close、ping、重连、connection generation 和迟到响应。
- Browser `Target.*` 事件驱动 target 创建、销毁和 reload。
- 只接纳 `app://-/index.html` 且通过 Codex surface 指纹的 target。

### U3 PageRuntime 与 adapters

- runtime 版本握手、adapter id 唯一、JSON envelope、异常隔离。
- 每个 adapter 的 `probe/install/update/diagnose/uninstall`。
- 重复安装不重复注册 handler/observer/style。
- 未知 DOM、歧义按钮、未知编辑器协议失败开放。
- 禁止 `body *` 全扫和本地化文本识别的源码/行为负向检查。
- 布局：主根、thread、composer、right rail、header、窗口变化、菜单排除、卸载恢复。
- Markdown：标题、strong、行内代码、代码块排除、顶层和嵌套引用。
- IME：composition start/end、229、grace window、request input 原生行为。
- Tab：编辑器状态同步、普通 Tab、带 modifier、未知编辑器回退焦点导航。
- focus-ring：问题可复现才保留；不能证明精确作用域时测试必须推动移除。

### U4 菜单栏与设置窗口

- 绿/黄/红/灰四态及 VoiceOver 标签。
- Xcode 26 多显示器坐标错投下，真实 `MenuBarExtra` 只做 `menuBar.status` 标识冒烟；内容和动作通过 Debug-only、复用同一 `StatusMenuView` 的可访问宿主窗口执行。该绿灯不替代真实状态项点击人工验收，宿主不得进入 Release。
- 状态相关动作只在合法状态可用。
- 菜单快速开关走配置事务且失败可见。
- 布局数值、auto/custom 顶部避让、颜色和预设的输入边界。
- 草稿、预览、应用、失败回滚、重置。
- `SMAppService.mainApp` 的 enabled/requiresApproval/notRegistered/error 状态。
- 确认重启对话框明确未发送内容风险，取消不改变 ChatGPT。
- `codex://settings` 原生设置入口。

### U5 诊断、隐私与性能

- `DiagnosticEvent` 仅允许版本、状态、错误码、计数和耗时字段。
- 对话文本、输入、Cookie、完整 DOM、CDP payload 和 WebSocket 内容不能进入日志或导出包。
- 1 MiB 单文件、5 文件轮转；并发写、磁盘失败和导出失败可解释。
- 一次 DOM burst 最多一轮 RAF 加一轮 settle。
- 超预算 adapter 自动停止布局写入并转为 degraded，不终止 ChatGPT。
- 事件环容量有界，target reload 不累计 observer/timer。

### U6 切换与文档

- 只有 U1-U5 与 live gate 全绿后删除旧产品链。
- 删除后仓库不再引用 Node、`cua_node`、`./verify.sh`、固定 `9229` 或旧 `CODEX_WIDE_*` 作为运行入口。
- README 中安装、打开、登录启动、迁移、诊断、卸载命令与真实产物一致。
- `.easy-coding/ABSTRACT.md` 只描述 Swift+JS V2。
- 当前任务外的 `.easy-coding` Harness 变更和用户工作树改动未被回滚。

## 当前 ChatGPT live gate

Live gate 必须绑定最终 Release 或等价 Debug 实现，并记录 App/build、配置指纹和 adapter 指纹。

1. ChatGPT 未运行：菜单灰色，不自动启动；菜单动作可启动受管实例。
2. ChatGPT 运行无 CDP：菜单黄色；取消确认零破坏；明确确认后才精确重启。
3. 正常 CDP：Browser target 连接、surface probe、全部保留 adapter 状态可见。
4. target reload：自动重新附着且不重复 handler/observer。
5. 配置损坏：红色状态、安全默认或 last-known-good 恢复，不覆盖损坏证据。
6. adapter 单项异常：只降级该项，ChatGPT 和其他 adapter 可用。
7. App/build 变化：能力缓存失效，重新 preflight，不按旧版本号盲注入。
8. 布局/顶部/Markdown：真实 computed style 与视觉布局符合配置，禁用后恢复原生。
9. IME/Tab/focus-ring：完成资格审查；不能稳定通过者必须从首版代码、配置和 UI 中删除。
10. 卸载：先清理页面资源并注销登录启动；保留或删除配置/日志按用户选择。

Live gate 不发送测试消息，不保存对话正文。真实重启、中文输入法和最终视觉观感需要用户参与确认，自动 fixture 不得冒充该证据。

## 通过门槛

- 所有标准命令退出 0。
- 全部必测项通过，无跳过的关键状态机、配置迁移、安全或隐私测试。
- live gate 有新鲜证据并绑定最终实现/config 指纹。
- IME、Tab、focus-ring 均有明确“保留且通过”或“移除且无残留”结论。
- 旧产品链删除后再次执行完整测试和 Release build 全绿。
- 无未说明的敏感日志、固定外网监听、静默重启或双实现 fallback。

## 无法在默认自动化中完成的项

- 用户真实中文输入法的完整组合体验。
- 菜单栏图标、布局宽度和主题色的最终审美判断。
- 未经用户确认的 ChatGPT 强制重启。
- 未来未知 ChatGPT 版本的兼容性；以 build 变化后的能力 preflight 和 degraded 状态覆盖。
