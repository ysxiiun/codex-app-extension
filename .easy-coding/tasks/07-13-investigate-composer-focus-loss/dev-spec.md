## 技术方案：排查全屏切换后对话输入框光标丢失

### 项目模式
迭代项目

### 任务类型
只读故障分析（analysis）

### 需求解析
- **目标**：定位 ChatGPT Codex 在 macOS 全屏状态下频繁丢失对话输入框光标的真实原因，并给出不破坏应用数据与签名的可执行解决方案。
- **输入**：用户提供的稳定复现路径（关闭再开启 macOS 全屏，多次切换后恢复）、当前 ChatGPT/Codex 运行实例、扩展配置与源码、应用持久化窗口状态、官方公开问题记录。
- **输出**：出文档；交付一份只读诊断报告，明确根因归属、证据强度、立即恢复方法、稳定规避方案、扩展侧可选加固与上游反馈建议，不修改真实项目代码或应用数据。
- **边界**：不修改 ChatGPT.app 包体、签名资源、账号数据、历史会话或 `~/.codex/.codex-global-state.json`；不在未授权情况下自动关闭宠物浮窗、切换全屏或写入扩展配置；不把相关但未精确匹配的公开问题当成当前故障的直接证明。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：扩展在 `inject-wide-layout.mjs:1971-2088` 监听视口尺寸并更新全屏/布局状态，在 `inject-wide-layout.mjs:2527-2642`、`inject-wide-layout.mjs:2814-2897` 安装输入键盘增强；官方应用同时运行主工作区 `app://-/index.html` 与独立宠物浮窗 `app://-/index.html?initialRoute=%2Favatar-overlay`。
- **当前实现方式**：全屏切换只触发 `resize`、布局刷新和根节点数据属性更新（`inject-wide-layout.mjs:1971-2088`）；扩展对输入框的显式 `focus()` 仅发生在用户触发换行或 Tab 插入时（`inject-wide-layout.mjs:2429-2524`），没有全屏、窗口 `focus`/`blur` 或 `visibilitychange` 恢复逻辑。
- **现有问题 / 缺口**：在线 CDP 探针曾同时观测到 avatar overlay 为 `document.hasFocus() = true`，主工作区为 `document.hasFocus() = false`；主工作区的 `activeElement` 与折叠选区仍保留在 ProseMirror，但 `.ProseMirror-focused` 消失，因此表现为“光标丢失”。本机持久化状态还显示 `electron-avatar-overlay-open = true`，浮窗尺寸固定为 `356x320`（`~/.codex/.codex-global-state.json:1`）。
- **证据**：① 当前 App 为 `26.707.62119`、bundle id `com.openai.codex`，且 `127.0.0.1:9229` 可读；② 主工作区 composer 存在且 DOM/选区未销毁；③ avatar overlay 曾独占文档焦点；④ overlay 页面没有扩展 surface 属性、IME guard、Tab handler 或布局 observer，符合扩展表面双门禁（`inject-wide-layout.mjs:941-965`、`inject-wide-layout.mjs:224-232`）；⑤ `layoutFocusRingFix` 只隐藏顶层布局壳的 outline/box-shadow，不匹配 ProseMirror（`inject-wide-layout.mjs:3123-3143`）。

### 冲突摘要
- 需求 vs RULES：无冲突；本任务保持只读，不修改应用包体或用户数据，并以在线 CDP 与真实源码为证据。
- 需求 vs ABSTRACT：无冲突；诊断沿用现有 CDP surface 门禁和 `--diagnose` 链路，架构说明见 `.easy-coding/ABSTRACT.md:12-37`。
- 需求 vs 现有代码：根因不在扩展现有全屏 CSS/输入事件路径；现有诊断输出未直接暴露 `document.hasFocus()`、`visibilityState`、`activeElement` 和 overlay 抢焦点关系（`inject-wide-layout.mjs:1168-1233`），导致常规 `--diagnose` 不足以一次说明问题。
- Dev-Spec vs 现有代码：无冲突；本轮只交付诊断报告，不规划代码变更。

### 影响面分析
- **涉及模块**：ChatGPT/Codex Electron 主工作区窗口、宠物/avatar overlay 独立窗口、macOS 全屏/Space 焦点切换；扩展仅作为排除与诊断证据来源。
- **核心类 / 页面 / 接口**：`app://-/index.html`、`app://-/index.html?initialRoute=%2Favatar-overlay`、CDP `Runtime.evaluate`、`inject-wide-layout.mjs` 的 target/surface、全屏、焦点环与输入增强逻辑。
- **数据库变更**：无。
- **接口变更**：无。
- **关联历史任务**：`SM-20260710-004`（ChatGPT-Codex 兼容适配）；长期主题“输入与布局增强边界”；`SM-20260713-005` 中记录的 avatar-overlay CDP target 选择陷阱。

### 背景数据应用
- `.easy-coding/ABSTRACT.md:12-37` 明确扩展通过 CDP 只在 Codex surface 注入，支持把主工作区与 overlay 分开探测。
- `.easy-coding/memory/long/TECHNICAL.md:30-35` 约束 `layoutFocusRingFix` 不得影响真实输入控件，且输入增强应复用现有识别边界；据此把“CSS 隐藏 caret”列为已排除方向。
- `SM-20260713-005` 已记录 avatar-overlay 与主工作区同名 target 的事实，本次进一步用逐 target 焦点探针确认 overlay 可成为焦点拥有者。

### 改动范围
> 本任务由用户要求诊断原因与解决方案，明确采用无代码交付形态；不修改真实项目源码或配置。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|

### 修改方案
- **总体改法**：本轮不改代码；形成“先关闭/收起宠物浮窗恢复主窗口焦点，长期保持 overlay 关闭并等待官方修复，必要时再增强扩展诊断但不以扩展对抗系统焦点”的分层方案。
- **后端改动**：不涉及。
- **前端改动**：不涉及；报告会说明优先使用 `/pet` 的 tuck-away 行为或 Settings > Appearance/Personalization > Pets 收起宠物浮窗，避免继续依赖多次全屏切换。
- **兼容处理**：保留当前扩展全部功能与配置；不直接编辑 `electron-avatar-overlay-open`。如 `/pet` 在当前版本未被 slash command 接管，则改用设置页关闭宠物，或完整退出并重启应用后立即关闭宠物浮窗。
- **风险点**：在线探针会随审批浮层、窗口前后台变化而改变瞬时 `document.hasFocus()`；因此结论只依赖已抓到的“overlay 有焦点、主工作区无焦点且选区仍在”的同一时刻证据。公开 issue 仅证明 avatar overlay 是独立窗口且已有窗口管理缺陷，不能替代本机证据。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U1 | 汇总源码、在线 CDP、持久化窗口状态与官方公开记录，输出完整根因和分层解决方案 | analysis | 无（只读交付） | — |

**执行策略**：single
- 单一实施单元：U1 只读故障诊断报告。
- 不派生并行改动，不进入代码 REVIEW、VERIFICATION 或 MEMORY。

### 测试策略

不适用：只读报告任务不创建独立 `test-strategy.md`，不进入 VERIFICATION。

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 主工作区与 avatar overlay 的焦点归属、可见性、composer/选区存活状态 | 诊断证据 | U1 | 在线只读 CDP 探针 | `./inject-current.sh --port 9229 --diagnose`，并按 target 执行不读取输入内容的 `Runtime.evaluate` |
| overlay 是否被本扩展注入 | 诊断证据 | U1 | surface/handler 状态核验 | 检查 overlay 的 surface 属性、IME guard、Tab handler、layout observer 均未安装 |

- **人工验收**：收起宠物/avatar overlay 后，在全屏状态连续输入并切换其他应用/Space，确认输入框 caret 不再被活动通知浮窗抢走；必要时连续执行 10 次窗口/全屏切换验证。
- **无法验证项**：当前不擅自操作用户界面关闭宠物浮窗，因此“关闭 overlay 后连续复现次数归零”需由用户执行或后续明确授权自动化验收。

### 风险与注意事项
- 不建议直接修改 ChatGPT.app 的 `app.asar` 或 NSWindow 配置；这会破坏签名/升级路径，也超出本扩展安全边界。
- 不建议在扩展页面脚本里循环调用 `composer.focus()`；当主 BrowserWindow 不是 macOS key window 时，DOM focus 不能可靠夺回系统焦点，还可能与官方 overlay 形成抢焦点循环。
- 可选的扩展后续任务只应增强 target 排除与诊断字段（明确降权 `initialRoute=/avatar-overlay`，输出 `document.hasFocus()`/`visibilityState`/`activeElement`），不能宣称修复官方 Electron 窗口管理问题。
