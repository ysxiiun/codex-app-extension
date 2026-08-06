# codex-app-extension 编码规则

> 由 ec-init 根据 SwiftUI App、ExtensionCore、PageRuntime、README 和 Xcode 验证提取；规则必须可机械检查。

## General

- 项目使用 Xcode project/scheme、Swift 6、SwiftUI、XCTest/XCUITest 和不依赖 npm 的页面 JavaScript；不得为单个增强引入第二套产品或测试链。
- 修改前用 `file -I` 核对编码并保持原编码；当前 Swift、JavaScript、Markdown、plist 和 pbxproj 均为 UTF-8/ASCII 可兼容文本。
- 现有源码注释超过 70% 为中文；新增注释使用简体中文，只解释兼容原因、协议边界、失败策略或非直观风险，不逐行解释语法。
- 用户可见配置、诊断字段、启动方式或兼容策略变化必须同步 `README.md`；模块或数据流变化同时同步 `.easy-coding/ABSTRACT.md`。
- `.easy-coding/config.yaml` 和平台 hook 配置由 CLI 管理，代码任务不得编辑；ec-init 只维护白名单结构的 `.easy-coding/project.yaml`。
- 不写入令牌、Cookie、账号数据、应用包体或调试响应快照；临时探针数据不得加入仓库。
- 提交前至少执行全部 `ExtensionCoreTests`、Release build、`plutil`、签名/资源扫描和 `git diff --check`；变更 PageRuntime/CDP 时再执行非破坏的 current ChatGPT live gate。

## Swift / SwiftUI / ExtensionCore

- Swift 6 并发边界使用 actor/`Sendable`；UI 状态只在 `@MainActor AppModel` 更新。
- `AppConfiguration` 是 UI、ConfigStore 和 FeatureRegistry 的唯一强类型配置源；禁止增加环境变量/CLI 第二配置链。
- UI 不直接访问 CDP 或文件系统；经 `RuntimeControlling` 接口调用 ExtensionCore。
- 配置先验证、页面预应用，再原子持久化；事务失败时恢复此前已持久化的 last-known-good，并回滚本次已经尝试的页面变更。
- 运行实例没有 CDP 时不得自动终止 ChatGPT；只有用户在原生警告框确认后才能正常 terminate 并以动态回环端口重启。
- 诊断必须从类型上仅允许版本、固定 enum、count、duration 和 timestamp；不得增加任意 payload/string 字段。

## PageRuntime JavaScript

- `bootstrap.js` 只暴露 `window.__codexAppExtensionV2`，envelope 固定为 `runtimeVersion/requestId/adapterId/operation/config/result/error`。
- target 必须同时通过 `app://-/index.html` 和 layout/thread/editor 唯一 surface probe；不得回退任意 page、全量 body 扫描或本地化文案。
- 每个 adapter 独立 probe/install/update/diagnose/uninstall，只接收自己的配置片段；失败不得阻塞 sibling。
- adapter 必须保存宿主 attribute、inline style value/priority、style node 内容和 handler/observer，卸载、reload 或 stop 时完整恢复。
- DOM burst 最多合并为一次 RAF 和一次 settle；不得放宽 8 ms/3 strikes、16 observers、32 events 的固定性能门禁而不更新测试。
- catch 若忽略错误，必须用注释说明该路径为何非关键；禁止记录 DOM、输入或 CDP 原始响应。

## plist、pbxproj 与 Markdown

- `Info.plist` 修改后运行 `plutil -lint`，并在 Release 产物复核 bundle id、macOS 13 和 `LSUIElement=true`。
- `project.pbxproj` 使用明确 PBX group/target membership；新文件必须注册到正确 target 并保持 shared scheme 可测。
- README 命令必须与真实 Xcode project/scheme/target 和产物路径一致，不得宣称公开更新器、公证或未实施的分发链。
- 当前产品入口只有 `Codex App Extension.app` 菜单栏/Settings UI；禁止把已移除的脚本、环境变量或 CLI 写成可用入口。
