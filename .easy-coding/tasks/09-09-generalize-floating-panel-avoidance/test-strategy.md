# 右上角浮窗通用避让测试策略

归属单元 U1；验证层级包括真实 DOM、模拟生命周期、完整 Core 与安装后真实宿主。

## 当前失败证据

2026-09-09 只读 CDP：ChatGPT 26.903.61454 build 8378，唯一 exact page target、唯一 layout/scroller，运行 revision 15。右栏 2244..2560，透明占位 2244..2544、58.5..340.5，只含 data-pip-obstacle；data-pip-home-surface 全页计数为 0。实际 painted sibling 位于同一栏，正文与 composer 右边界 2421.82、offset 0，横向重叠 177.82px。探针未读取正文/草稿/Cookie。

## 必测矩阵

| 编号 | 用例 | 结果要求 |
|---|---|---|
| T1 | 真实 WKWebView 执行完整 bootstrap 与 wide-layout，顶部单属性透明占位、底部水平 reference | 旧实现失败，新实现正文、Markdown和composer保持配置侧边距且不重叠 |
| T2 | 改变占位值、移除home、删除旧shell class、调整包装层 | 通用语义路径仍成立，不依赖固定组件名或原class |
| T3 | 已有无语义属性painted panel、旧双属性、短空态 | 使用统一可见会话纵向区域正确占位 |
| T4 | header/composer/正文/布局外候选、menu/listbox/dialog及包裹瞬态的节点 | 不错误缩窄；正常面板内展开菜单不撤销面板占位 |
| T5 | 原节点新增/删除占位属性，隐藏/显示；祖先opacity/display改变；替换/移除 | 自动发现与恢复，不依赖重注入，旧节点解绑 |
| T6 | 同时命中语义与原生shell、两面板、窄窗口、原生transform | 无重复偏移，选择最左有效边界，现有宽度公式与native补偿保持 |
| T7 | 200次正文mutation、候选属性burst、resize与motion | 维持原有快路径与8ms/3 strikes约束，稳定后零额外写入 |
| T8 | update/uninstall与挂起RAF/observer | 原属性/样式恢复、监听与调度清零，其他adapter不受影响 |
| T9 | revision16与正式安装资源 | JS、bridge、测试、README与ABSTRACT一致，安装资源hash匹配 |

真实HTML内联至 AdapterFixtureTests.swift；直接从测试Bundle加载bootstrap/adapter，不用FakeDOM selector注册字典代替。先建立T1的失败证据，再修复。FakeDOM仅承担离散生命周期与计数断言，旧“单属性必拒绝”用例按新的实际语义合同更新。

## 验证命令

定向检查：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-rail-tests test -only-testing:ExtensionCoreTests/AdapterFixtureTests -only-testing:ExtensionCoreTests/AdapterPerformanceTests -only-testing:ExtensionCoreTests/PageRuntimeTests -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests CODE_SIGNING_ALLOWED=NO
```

完整 Core：

```bash
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/codex-app-extension-rail-tests test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO
```

静态检查：

```bash
node --check CodexAppExtension/Resources/Adapters/wide-layout.js
node --check CodexAppExtension/Resources/PageRuntime/bootstrap.js
plutil -lint CodexAppExtension/Supporting/Info.plist
git diff --check
```

## 构建安装与真实验收

通过代码与测试检查后执行 `./install.sh`，完成Release构建、签名、安装前后资源/rpath/Info审计、原子安装和冷启动存活检查。随后只读CDP核对唯一 exact target、revision16、实际浮窗左边界、正文/composer/Markdown右边界与最小间距，结果必须 nonOverlap=true，资源hash须与仓库候选一致。端口按精确进程回环调试参数重新获取，不固定进产品。

人工视觉验收保留真实浮窗开合、窗口缩放、滚动与无闪烁；本任务不调用Computer Use/Chrome插件或自动点击。真实交互不由fixture结果代替。若宿主窗口未呈现某状态，明确该状态的实时验证范围，以真实WebKit动态测试提供自动化证据。

## 审查与证据

QUALITY独立审查正确性、误识别/漏识别、observer性能与隐私；验证结果绑定最终实现和配置指纹。保留已有Harness升级改动，不提交推送Git。
