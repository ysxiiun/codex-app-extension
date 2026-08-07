# 测试策略：Markdown 表格组件内水平滚动

## 冻结范围

- 任务：`08-07-markdown-table-horizontal-scroll`
- 单元：`U1`
- 目标：表格外壳受正文宽度约束，超宽内容仅在表格组件内部横向滚动，关闭/卸载恢复原生。

## 必测项

| ID | 归属 | 测试文件 | 验证内容 | 命令 |
|---|---|---|---|---|
| T1 | U1 | `PageRuntimeTests/AdapterFixtureTests.swift`、`PageRuntimeTests/Fixtures/current-surface.html` | `[data-markdown-table]` 外壳 containment、直接含 table 子树 overflow、窄表/正文负向 scope、幂等与卸载恢复 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-table-scroll test -only-testing:ExtensionCoreTests/AdapterFixtureTests CODE_SIGNING_ALLOWED=NO` |
| T2 | U1 | `PageRuntimeTests/PageRuntimeTests.swift`、`CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | runtime revision 11、同 revision 幂等与旧 revision 热升级 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-table-scroll test -only-testing:ExtensionCoreTests/PageRuntimeTests -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests CODE_SIGNING_ALLOWED=NO` |
| T3 | U1 | 全部 ExtensionCoreTests | 现有宽屏、Markdown、IME、target、恢复、隐私和性能回归 | `xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-table-scroll-full test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO` |
| T4 | U1 | Release bundle | JavaScript/Swift typecheck、Release 构建、签名、资源、原子安装与启动存活 | `node --check CodexAppExtension/Resources/Adapters/wide-layout.js`; `node --check CodexAppExtension/Resources/PageRuntime/bootstrap.js`; `./install.sh`; `codesign --verify --deep --strict --verbose=2 '/Applications/Codex App Extension.app'`; `git diff --check` |
| T5 | U1 | 当前 ChatGPT target | 只读表格组件 rect/clientWidth/scrollWidth/computed overflow 与扩展 marker/revision | privacy-safe CDP Runtime.evaluate；禁止读取 innerText/textContent/HTML/value/Cookie/payload |

## 负向合同

- 产品 selector 不包含当前 `_table*_<hash>_*` CSS module 类。
- 不对 `[data-selected-text-overlay-target]`、thread scroller 或页面根设置横向滚动。
- 不设置 `table` 的固定宽度、max width、white-space 或 word-break。
- Markdown 外观 adapter 的颜色与语义规则不承担本布局修复。
- 卸载后 adapter style node 被移除或恢复为宿主原内容，不留下 inline style/DOM wrapper/observer。

## 人工验收

- 超宽表格右边界不超过配置后的正文边界，底部水平滚动可达最右列。
- 窄表格无多余页面级横向滚动，正文、流式输出、输入框和右侧环境信息布局不跳动。
- 关闭宽屏后恢复 ChatGPT 原生表格 wide-block 行为。

## 当前限制

当前页面的截图表格已被虚拟列表卸载。若最终 live gate 中仍无表格节点，T1-T4 必须全绿，T5 记录为现场不可用，并由用户在安装版本上完成最终视觉验收。
