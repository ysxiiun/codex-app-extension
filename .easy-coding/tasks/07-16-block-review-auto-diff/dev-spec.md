## 技术方案：为内置代码审查命令增加自动 Diff 门禁

### 修订摘要
- REVIEW 三轮修复后的最终复审确认：当前 `choose-branch` 已能绑定同根/新根 picker，但键盘回退仍把已绑定的 picker 根当作全局 document 查询，导致根本身为 `listbox` / `menu` / `cmdk-list` 且选中分支是直接子项时无法命中（`inject-wide-layout.mjs:3523-3540`）。
- 本次重规划不改变用户确认的功能范围、配置键、默认值或作者启用方式；只把“全局命令菜单选中项查询”和“已绑定分支 picker 内选中项查询”拆为两条明确协议，并把真实 ARIA 键盘结构加入可执行 fixture（`verify.sh:580-631`）。

### 项目模式
迭代项目

### 任务类型
新功能

### 需求解析
- **目标**：为截图中的内置 `/review`「代码审查」命令增加可配置门禁；开启后，审查仍正常启动，但不再自动拉起右侧“审阅”栏或把已有右栏切换到 Diff。
- **输入**：用户从命令面板选择 `review-mode`，再选择“审查未提交的更改”或基础分支；配置键 `reviewAutoDiffGuard` 决定是否保持命令执行前的右栏状态。
- **输出**：改代码；新增完整配置链、页面侧命令状态跟踪与右栏状态恢复、诊断信息、自动验证和文档，并在 `data/author-config.json` 中为作者开启该能力。
- **边界**：不修改 `/Applications/ChatGPT.app`、官方 `app.asar`、账号数据或会话历史；不阻止审查请求、不改变审查 prompt / 分支选择 / delivery；不屏蔽用户手动打开“审阅”或其他 Diff 入口；不把普通“变更”按钮、摘要浮层或所有右栏开合都当成目标。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：项目通过 Node/CDP 生成并注入页面脚本；`reviewAutoDiffGuard` 已接入默认值、CLI、JSON、环境变量、`buildMeta` 和安装/诊断结果（`inject-wide-layout.mjs:49-65`、`inject-wide-layout.mjs:115-118`、`inject-wide-layout.mjs:301-318`、`inject-wide-layout.mjs:591-596`、`inject-wide-layout.mjs:2998-3038`）。页面行为集中在 `buildInstallerSource` 的 review 命令状态机、branch picker 绑定和右栏恢复 observer 中（`inject-wide-layout.mjs:3160-3462`、`inject-wide-layout.mjs:3463-3569`）。
- **当前实现方式**：ChatGPT `26.707.91948` 的内置命令注册对象 ID 为 `review-mode`，成功启动内联 review 后依次设置 Diff 过滤条件、登记会话分支信息、调用右栏打开函数；该函数创建 `id="diff"`、标题为 `thread.sidePanel.diffTab` 的“审阅”标签并主动激活右栏（`/Applications/ChatGPT.app/Contents/Resources/app.asar::webview/assets/app-initial~app-main~new-thread-panel-page~appgen-library-page~hotkey-window-thread-page~ho~iufn7mg3-DtuASjaM.js:1`、`/Applications/ChatGPT.app/Contents/Resources/app.asar::webview/assets/review-mode-content-BJ7BYvex.js:1`、`/Applications/ChatGPT.app/Contents/Resources/app.asar::webview/assets/app-initial~app-main~onboarding-page-Bye92EOT.js:1`）。右栏 DOM 暴露稳定结构 `data-tab-id="diff"`、`role="tabpanel"`、`data-app-shell-tab-panel-controller="right"` 和顶部 `aria-pressed` 开关（`/Applications/ChatGPT.app/Contents/Resources/app.asar::webview/assets/app-initial~app-main~hotkey-window-thread-page~chatgpt-conversation-page~thread-app-shell-c~cref7t2u-DhfMyBiQ.js:1`、`/Applications/ChatGPT.app/Contents/Resources/app.asar::webview/assets/thread-app-shell-chrome-UXmBYO_I.js:1`）。
- **现有问题 / 缺口**：`findUniqueSelectedReviewMenuItem` 在 `choose-branch` 阶段把 `controller.branchPickerRoot` 作为 `selectionRoot`，随后仍查询 `[role='listbox'] [role='option'][aria-selected='true']` 等带父级前缀的 selector；`Element.querySelectorAll` 不会让根自身参与祖先匹配，因此 picker 根下的直接选中分支项无法命中（`inject-wide-layout.mjs:3523-3540`）。当焦点由 picker 外部、通过 `aria-controls` / `aria-activedescendant` 关联的输入框持有时，直接 `readSignal(activeElement)` 也无法替代该回退，基础分支键盘路径不会进入 `await-auto-diff`。
- **证据**：现有 fixture 已覆盖同一 review 菜单根从目标项切换到分支项并成功绑定（`verify.sh:580-616`），但 selected fallback 只检查源码片段和顺序，没有执行 picker 根自身为 `listbox/cmdk-list`、直接 selected 子项与外部 ARIA 焦点组合（`verify.sh:618-631`），所以 `./verify.sh` 会漏过该缺陷。

### 冲突摘要
- 需求 vs RULES：无冲突；采用正向布尔能力名 `reviewAutoDiffGuard`，保持“默认值 < 配置文件 < 环境变量 < CLI”，同步诊断、README 与架构摘要，不修改官方应用包体。
- 需求 vs ABSTRACT：无冲突；沿用既有 Node/CDP 页面注入、Codex surface 双门禁、当前实例重注入和零依赖验证链（`.easy-coding/ABSTRACT.md:11-17`、`.easy-coding/ABSTRACT.md:32-50`）。
- 需求 vs 现有代码：配置、命令入口、右栏恢复、失败开放和清理链已具备；仅基础分支键盘 selected fallback 与真实根结构不一致，属于当前方案内的实现缺陷，不需要改变产品范围。
- Dev-Spec vs 现有代码：原方案把 pointer 与 keyboard 归为同一分类函数是正确方向，但没有区分“document 下查找已选命令”和“已绑定 picker 根内查找已选分支”的 selector 语义；本次修订明确拆分该协议并要求可执行 DOM fixture。

### 影响面分析
- **涉及模块**：核心注入、配置、诊断、验证、README 用户契约、作者推荐配置和架构摘要。
- **核心类 / 页面 / 接口**：`DEFAULT_CONFIG`、`parseCliArgs`、`ensureConfig`、`configureConfig`、`buildCompleteConfig`、`buildOptions`、`buildDiagnoseSource`、`buildInstallerSource`、`buildMeta`；页面侧命令菜单事件、右栏 tab/panel DOM 协议和 `window.__codexAppExtensionReviewAutoDiffGuard` 运行状态。
- **数据库变更**：无。
- **接口变更**：新增 JSON 键 `reviewAutoDiffGuard`、环境变量 `CODEX_APP_EXTENSION_REVIEW_AUTO_DIFF_GUARD`、CLI 参数 `--enable-review-auto-diff-guard` / `--disable-review-auto-diff-guard`，以及诊断字段 `reviewAutoDiffGuardEnabled`、`reviewAutoDiffGuardInstalled`、`reviewAutoDiffGuardState`。
- **关联历史任务**：`SM-20260528-001`（右侧栏 observer 与可回退边界）、`SM-20260710-004`（ChatGPT/Codex surface 和 `app.asar` 协议验证）；长期技术记忆“运行时注入架构”“配置化增强链路”“输入与布局增强边界”。

### 背景数据应用
- `.easy-coding/ABSTRACT.md:32-38` 决定把功能放入现有核心注入器，并通过 JSON 可序列化状态跨越 Node/CDP 页面边界。
- `.easy-coding/memory/long/TECHNICAL.md:19-28` 决定使用保守默认值、完整四级配置链、`--diagnose` 状态和当前实例重注入验证。
- `.easy-coding/memory/short/1_2026-05-28_侧边栏开合布局抖动修复.md:58-62` 决定复用 observer 调度并保持可诊断、可回退，而不是改官方包体。
- `.easy-coding/memory/short/004_20260710_ChatGPT-Codex兼容适配.md:64-68` 决定继续使用 surface 门禁、生成源码编译和 `app.asar` 稳定锚点断言。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8（`file -I`） | 新增配置链、可测试的 review 选择/恢复决策函数、页面侧一次性门禁、清理逻辑、安装结果和诊断状态。 |
| `verify.sh` | 修改 | 保持原编码 US-ASCII（`file -I`） | 覆盖默认值/配置变体、纯状态决策、生成源码、官方 bundle 锚点和文档/作者配置一致性。 |
| `README.md` | 修改 | 保持原编码 UTF-8（`file -I`） | 说明功能语义、默认关闭、作者开启、配置优先级、环境变量、CLI、诊断字段和已知兼容边界。 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8（`file -I`） | 更新核心注入、配置、诊断和验证数据流，记录 review 自动 Diff 门禁。 |
| `data/author-config.json` | 修改 | 保持原编码 US-ASCII（`file -I`） | 写入 `"reviewAutoDiffGuard": true`；本机配置当前软链接至该文件，重注入后直接为作者生效。 |

### 修改方案
- **总体改法**：在 `/review` 命令入口建立短生命周期状态机，启动审查前记录右栏开合与活动 tab；仅当随后由同一次 review 自动激活 `data-tab-id="diff"` 时恢复快照，同时把完整开关接入配置/诊断/验证链。
- **后端改动**：不涉及后端；Node 侧仅扩展本地配置解析、参数合并、生成源码和验证辅助函数。
- **前端改动**：保留现有 pointer/keyboard 命令状态机与同根/新根 branch picker 绑定；新增独立的已选项收集 helper：全局 `document` 路径继续使用带菜单祖先约束的 selector，已绑定 `branchPickerRoot` 路径则只在该根后代中查询直接/嵌套的 `[role='option'|'menuitem'][aria-selected='true'|data-selected='true']` 与 cmdk `data-selected` 项，再复用 `readSignal` 和 `classifyReviewMenuSignal`。外部输入框只有在 `aria-controls` 或 `aria-activedescendant` 明确指向该根/其中分支项时才允许键盘回退。
- **兼容处理**：开关默认 `false`，禁用时只清理旧 handler/observer，不改变现有行为；开启时仍受 Codex surface 门禁保护。无法唯一识别命令项、右栏开关或原 tab 时失败开放；Escape、路由变化、超时、用户在等待期内可信手动操作右栏都会取消本次门禁。重复注入先 dispose 旧实例，避免多重监听。
- **风险点**：官方命令菜单文案或 DOM 属性会随版本变化；通过 `review-mode` 数据值优先、中英文回退、`app.asar` 锚点验证、短超时和失败开放降低误拦截。DOM 恢复发生在 React 提交后，可能存在单帧变化；不使用脆弱 CSS 强行隐藏整栏，避免误伤手动 UI。

### 前端实现映射
- **命令入口**：内置 `review-mode` 菜单项；pointer 选择与键盘 Enter 都进入同一分类函数，普通 skill、普通消息发送和其他 slash 命令不进入状态机。
- **目标选择**：`unstaged` 直接进入“等待自动 Diff”；`base-branch` 进入“等待分支”，绑定同根内容替换或唯一新根 picker。鼠标从事件目标读取分支；键盘从已绑定根内收集唯一选中项，根自身是 `listbox/menu/cmdk-list` 时仍能命中直接子项，且外部焦点必须通过 ARIA 明确归属。取消或异常退出清空状态。
- **自动结果识别**：右侧活动 panel/tab 必须同时满足 `data-app-shell-tab-panel-controller="right"`、`data-tab-id="diff"` 与可见/选中条件，且处于本次 review 的有限等待窗口内。
- **状态恢复**：关闭态恢复关闭；打开其他 tab 恢复原 tab；已打开 Diff 保持不动；恢复动作完成后立即销毁本次 pending，后续手动操作完全交还原生 Codex。
- **诊断映射**：记录 `phase`、最近命令/目标信号、启动前快照、最近恢复动作、取消原因与时间戳，不记录 prompt、分支列表、会话正文或账号数据。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U1 | 完成 review 自动 Diff 门禁并修正基础分支键盘选中项协议、回归验证、文档与作者启用 | frontend | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md`、`data/author-config.json` | — |

**执行策略**：single
- 单一实施单元：U1；配置 schema、注入状态机、自动验证、文档和作者配置共享同一契约，必须由 1 个子代理连续完成并统一校验。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| `reviewAutoDiffGuard` 默认关闭、作者配置开启，CLI / 环境变量 / 配置优先级与完整配置补齐一致 | 必测 | U1 | Node 断言 + JSON 静态检查 | `./verify.sh` |
| review 命令、未提交变更、基础分支与分支选择的状态迁移；关闭态/其他 tab/已在 Diff 的恢复决策 | 必测 | U1 | 纯函数回归断言 | `./verify.sh` |
| 已绑定 picker 根内的基础分支键盘回退 | 必测 | U1 | 可执行 DOM fixture：根自身为 `listbox` 与 `cmdk-list`、selected 分支为直接子项、焦点位于 ARIA 关联的外部控件；断言唯一分支进入 `launch-review`，原目标项/多个选中项/无 ARIA 归属均失败开放 | `./verify.sh` |
| 生成后的 installer/diagnose 在开关开闭两种变体下可编译，包含清理、surface 门禁和诊断字段 | 必测 | U1 | 生成源码编译与静态断言 | `./verify.sh` |
| 当前 ChatGPT bundle 仍包含 `review-mode`、`thread.sidePanel.diffTab`、`data-app-shell-tab-panel-controller` 与 `data-tab-id` | 必测 | U1 | `app.asar` 锚点检查 | `./verify.sh` |
| 当前实例重注入后诊断显示开关已启用、门禁已安装且无异常 | 应测 | U1 | 在线 CDP 诊断 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |

- **人工验收**：用户执行截图中的“代码审查”并选择未提交更改或基础分支，确认审查任务正常开始而右侧栏保持执行前状态；随后手动打开“审阅”，确认仍可正常查看 Diff。
- **无法验证项**：自动化不会代替用户真正发起一次模型代码审查，以免额外消耗额度或改变当前任务状态；该端到端交互保留为人工验收。

### 风险与注意事项
- 官方 `app.asar` 是只读分析证据而非改动对象；应用升级后若锚点变化，`verify.sh` 应失败并提示适配，运行时本身必须失败开放，不得猜测点击。
- 已绑定 picker 根查询不得复用依赖“根外祖先”的全局 selector；回归 fixture 必须让 picker 根自身承担 `listbox/menu/cmdk-list` 角色，防止再次出现只靠源码字符串顺序却无法命中真实 DOM 的假阳性。
- 只对本次 `/review` 启动产生的一次自动 Diff 恢复状态；不得把 observer 扩展成全局“看到 diff 就关闭”，否则会破坏用户手动查看 Diff。
- 本机 `~/.codex-app-extension/config.json` 当前软链接到 `data/author-config.json`；作者配置改为 `true` 后仍需对当前实例执行重注入才能安装新行为。
