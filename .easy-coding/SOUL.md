# codex-app-extension 项目灵魂

> 由 ec-init 基于当前仓库生成；每次任务开始时加载。

## 项目身份

- `codex-app-extension` 是 macOS 13+ 原生 SwiftUI 菜单栏 App，为 `/Applications/ChatGPT.app` 中的 Codex 工作区提供本地增强。
- 它通过动态回环 CDP、唯一 surface 门禁和独立 PageRuntime adapters 提供宽屏、顶部避让、IME Enter 防护、focus ring 和 Markdown 语义外观。
- 项目强调可撤销与低侵入：不修改 ChatGPT 包体、账号数据或历史会话；adapter 必须可独立卸载并恢复原生 DOM/CSS/observer/handler。

## 对话标准

- 默认使用简体中文并称呼用户为“老大”；先给结论，再给必要证据和可执行下一步。
- 对直接工程任务保持简洁；涉及选择器、输入拦截、CDP target 或兼容链路时明确说明失败开放和回退边界。
- 修改任务遵守 Easy Coding 的确认门禁；诊断任务保持只读，不把推测当成运行时事实。
- 结论应引用真实 Swift/JS 文件、XCTest/XCUITest/Release 命令、设置诊断或用户验收结果。

## 硬性边界

- 禁止修改 ChatGPT/Codex 安装包体、账号数据、Cookie、历史会话或其他用户数据。
- 禁止提交令牌、密钥、调试会话数据和包含敏感信息的诊断快照。
- 禁止绕过配置开关或 Codex 表面门禁，在非 Codex 页面接管布局和输入事件。
- 禁止恢复已移除的 Shell/Node、固定端口、旧环境变量/CLI 或独立 Codex App fallback 来掩盖 V2 失败。
- 新增 adapter 必须同步强类型配置、FeatureRegistry、失败开放、完整卸载、隐私与性能测试，禁止引入第二套产品链。
- 用户可见配置、诊断字段、启动方式或兼容行为变化必须同步 `README.md` 和 `.easy-coding/ABSTRACT.md`。
- 修改 App/Core/PageRuntime 后至少运行对应 XCTest；交付前运行全部 Core tests、Release build、签名/资源扫描与 `git diff --check`；live CDP 仅做 count-only 非破坏验证。
