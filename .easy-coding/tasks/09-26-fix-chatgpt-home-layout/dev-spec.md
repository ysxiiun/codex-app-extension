<!-- easy-coding:compact -->
## 修复 ChatGPT 首页宽屏容器误判

### 决策闭环
decision_status: closed
用户以“执行刚才我们聊的任务吧”授权当前 Codex 按已讨论方案直接修复。沿用现有配置与增强功能，只修正宽度容器识别，无额外业务决策。实时 Codex 节点同时包含变量声明与 max-w-(--thread-body-max-width)，必须保留这种真实宽度约束。

Goal: ChatGPT 首页外层保持主区域全宽，标题与输入框基于正确区域居中；Codex 正文、输入框和浮窗避让维持现有行为。
Scope: 修改 wide-layout.js 的节点资格与 CSS，以已验证的完整宽度 class token 区分变量声明和真实宽度使用者。同步 bootstrap/Swift bridge revision 17、桥接断言、真实 WebKit 回归及 README；对 ABSTRACT 的版本和受影响合同做最小同步。一个单元，保持页面身份、输入事件、配置和浮窗算法。
Acceptance: 新回归覆盖首页声明层与嵌套真实 owner、当前 Codex body-width owner、class 变化恢复和卸载清理；全部 ExtensionCoreTests 通过。安装器完成 Release 构建、签名、资源审计、安装和启动存活；核对安装资源哈希，并通过回环 CDP 读取版本、计数和几何。fixture 不代替用户真实页面切换和 IME 验收。

### 实施与证据
- 根因：isWidthOwnerNode 与 CSS 按 class 子串命中 [--thread-content-max-width:42rem]，最外层祖先选择把整页限制为当前配置的 1200px。
- 修复：JS/CSS 共用原生宽度 token 集合；只有变量声明的节点不参与，同时声明变量和使用真实宽度的 owner 继续有效。
- 验证：既有内存反例已证明旧逻辑选错容器；QUALITY 使用真实 WebKit 回归检查修复版、现有布局、全部 Core 与安装产物，必要时在独立临时副本回放旧脚本。
- 基线：保留 IIFE、有限祖先路径、差异写入与完整恢复；沿用 XCTest、JSRuntimeHarness 和可见 WKWebView，不增加依赖。
- 风险：过窄匹配可能漏掉 Codex 的间接 body-width owner，已纳入实时节点证据和回归。未来宿主新增语法仍需重新验证。
- 交付：依 RULES 完成构建和增强 App 安装；保持 ChatGPT 进程及会话。Git 提交推送不在范围内。

### Workflow Mode
项目配置 Adaptive；状态接口计算并选择 Fast，原因 single-bounded-unit：单仓库单单元、局部布局修复和版本同步。Java unit_test_mode 为 none。
