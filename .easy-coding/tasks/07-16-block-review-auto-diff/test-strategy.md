# 测试策略：review 自动 Diff 门禁

## 1. 可测试性表

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| `reviewAutoDiffGuard` 默认值、配置补齐和四级优先级 | 配置与参数构建 | [must-test] | 输入输出明确，默认关闭是用户要求，优先级是项目硬约束。 |
| review 命令菜单信号分类与阶段迁移 | 纯函数 / 状态机 | [must-test] | `review-mode`、`unstaged`、`base-branch` 和分支选择可用确定输入断言。 |
| 已绑定 branch picker 根内的键盘 selected fallback | DOM helper / Bug 回归 | [must-test] | 最终复审已确认根自身为 `listbox/menu/cmdk-list` 时，带祖先前缀的 selector 无法命中直接 selected 子项；必须用可执行 fixture 锁定。 |
| 右栏快照到恢复动作的决策 | 纯函数 | [must-test] | 关闭、其他 tab、已在 Diff、未出现 Diff 均有确定结果。 |
| 页面事件捕获、MutationObserver、dispose 和超时取消 | UI 交互 | [should-test] | 可通过生成源码断言与当前 Codex DOM 锚点覆盖核心契约；仓库无浏览器测试框架。 |
| installer / diagnose 开关变体与诊断状态 | 生成代码 | [must-test] | 生成字符串必须在开关开闭两种情况下可编译且字段完整。 |
| `app.asar` 的 review / side-panel DOM 锚点 | 外部运行时契约 | [must-test] | 官方升级后应在离线验证阶段明确失败，避免运行时猜测点击。 |
| README、ABSTRACT 与作者配置同步 | 文档 / JSON | [should-test] | 可机械检查关键字段和合法 JSON，人工复核语义。 |
| 真正执行一次 `/review` 后的视觉与手动 Diff 行为 | UI 端到端 | [depends] | 会启动真实模型审查并改变当前任务状态，不应由自动验证擅自触发。 |

## 2. 测试点

| Test point | Verdict | Unit | Cases | Verify command |
|---|---|---|---|---|
| 配置默认值与优先级 | [must-test] | U1 | `DEFAULT_CONFIG.reviewAutoDiffGuard === false`；旧配置缺字段时补 `false`；配置 `true` 生效；环境变量覆盖配置；CLI 覆盖环境变量；非法布尔值报字段名。 | `./verify.sh` |
| 命令入口分类 | [must-test] | U1 | `review-mode` 进入选择目标；中英文标题+描述回退可识别；其他 slash 命令无状态变化。 | `./verify.sh` |
| review 目标迁移 | [must-test] | U1 | `unstaged` 直接等待 Diff；`base-branch` 等待分支；随后分支选择才等待 Diff；Escape/超时/非 Codex surface 取消。 | `./verify.sh` |
| 基础分支键盘 selected fallback | [must-test] | U1 | 已绑定根自身分别为 `role=listbox`、`role=menu`、`cmdk-list`；selected 分支为直接子项；焦点位于通过 `aria-controls` / `aria-activedescendant` 关联的外部输入控件；唯一分支进入 `launch-review`。原 review 目标阶段、多个 selected、无 ARIA 归属或 picker 外选项均不得启动门禁。 | `./verify.sh` |
| 恢复决策 | [must-test] | U1 | 原关闭+当前 Diff => close；原打开其他 tab+当前 Diff => restore-tab；原已在 Diff => none；当前未激活 Diff => wait/none。 | `./verify.sh` |
| 生成源码与清理 | [must-test] | U1 | 开关 `true` / `false` 都可编译；重复注入先 dispose；状态仅在 Codex surface 安装；诊断包含 enabled/installed/state。 | `./verify.sh` |
| 官方锚点 | [must-test] | U1 | `app.asar` 包含 `review-mode`、`thread.sidePanel.diffTab`、`data-app-shell-tab-panel-controller`、`data-tab-id`。 | `./verify.sh` |
| 当前实例状态 | [should-test] | U1 | 作者配置为 `true`；在线诊断显示 enabled/installed；状态对象无异常或敏感正文。 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |

## 3. No-test 原因

- 无纯样式变更；本任务所有行为和配置均纳入自动或人工验证。
- 不新增第三方 DOM 测试依赖：项目无 `package.json` 和浏览器测试框架，使用 `verify.sh` 内零依赖 fixture 执行已选项收集与 ARIA 归属 helper；真实 `/review` 请求仍保留人工验收。

## 4. 人工验收

1. 保持右侧栏关闭，从命令面板执行“代码审查”并选择“审查未提交的更改”，确认审查开始但右侧栏不自动出现。
2. 保持右侧栏打开且活动 tab 不是“审阅”，执行一次代码审查，确认原 tab 保持/恢复，不被留在 Diff。
3. 审查开始后手动打开“审阅”，确认 Diff 正常可用，不会被门禁再次关闭。
4. 临时用 CLI 或环境变量关闭 `reviewAutoDiffGuard` 并重注入，确认恢复 Codex 原生自动拉起行为。

## 5. 无法验证项

- 自动化不真正提交 `/review` 模型审查：该操作会消耗额度并改变当前 Codex 任务状态，保留给用户按上述步骤验收。
- 官方后续版本的 DOM 契约无法提前验证；当前版本通过 `app.asar` 锚点和在线诊断覆盖，升级漂移由 `verify.sh` 与运行时失败开放处理。
