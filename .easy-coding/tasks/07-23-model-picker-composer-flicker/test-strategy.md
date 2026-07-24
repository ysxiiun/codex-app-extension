# 测试策略：模型菜单闪烁与 composer 顶部组件错位

## 变更可测性

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| 瞬态交互浮层判定源码 | pure predicate | [must-test] | 输入元素语义关系，输出是否排除；可用最小 fake element 确定性验证 |
| composer 附着组件判定 | layout classification | [must-test] | 必须只命中 composer 上方 `bottom-full` 目标，不误移持久右侧 rail |
| 独立附着组件偏移变量及 CSS 映射 | layout state / style | [must-test] | 必须证明 native width reset 保留、对齐偏移不被清零且只作用于附着 wrapper |
| `findRightFloatingRail()` 的菜单/附着组件候选过滤 | layout classification | [must-test] | 两类非 rail 目标都必须在几何候选入列之前排除 |
| 新增两类诊断投影 | diagnose projection | [should-test] | 只读 JSON 字段需要保证生成源码可编译、字段存在且不影响既有字段 |
| `README.md` 菜单/rail 边界说明 | documentation | [no-test] | 无运行时行为，用内容契约和 diff 检查验证 |
| `.easy-coding/ABSTRACT.md` 架构知识同步 | documentation | [no-test] | harness 知识资产，无运行时行为 |

## 测试点

| ID | 测试点 | 归属单元 | 验证方式 | 验证命令 |
|---|---|---|---|---|
| T1 | 元素自身匹配 `role="menu"` 时判定为瞬态浮层 | U1 | 内嵌 Node 纯函数回归 | `./verify.sh` |
| T2 | 定位 wrapper 的祖先为 `menu` 或后代包含 `listbox` 时判定为瞬态浮层 | U1 | 内嵌 Node 纯函数回归 | `./verify.sh` |
| T3 | `bottom-full` wrapper 包含 composer top menu 时判定为附着组件；普通 `thread-floating-content` 和无 composer 关联的浮层为 false | U1 | 内嵌 Node 正负例回归 | `./verify.sh` |
| T4 | root/scope 写入独立 overlay 对齐偏移，native reset 不覆盖它，附着 wrapper 使用它且内部 width/content offset reset 仍存在 | U1 | 生成 installer/CSS 契约断言 | `./verify.sh` |
| T5 | installer 在 rail 几何测量前排除瞬态菜单和 composer 附着组件，真实 rail 路径保留 | U1 | 生成源码契约断言 | `./verify.sh` |
| T6 | diagnose 生成源码可编译并输出两类新增字段，既有 `layoutWidthState` / `layoutWidthScopes` / native floating 字段保留 | U1 | 生成源码契约断言 | `./verify.sh` |
| T7 | JavaScript/Shell 语法、surface guard、CSS scope、启动链、app.asar 锚点和 `git diff --check` 全部通过 | U1 | 项目统一验证 | `./verify.sh` |
| T8 | 当前 9229 CDP 主工作区只读诊断成功，真实 rail 仍进入 `layoutWidthState.rightFloatingRail`；运行态组件中心与 composer 中心差不超过 2px | U1 | 在线诊断与坐标探针 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |

## No-test 原因

- `README.md` 与 `.easy-coding/ABSTRACT.md` 只同步行为边界和诊断字段，不执行逻辑；通过人工内容核对、编码检查及 `git diff --check` 验证。

## 人工验收

- 执行重注入后打开一级设置菜单，保持至少 5 秒，composer 左右边界不应持续变化。
- 继续打开二级模型菜单，保持至少 5 秒，composer 与两级菜单均不应横向往返或闪屏。
- 选择一个模型并关闭菜单，原生交互应正常，composer 不应出现关闭后的额外宽度跳变。
- 运行任务时，任务列表 / Git 差异顶部组件应与 composer 中心线一致，左右中心差不超过肉眼可见范围；组件宽度、内容滚动和点击行为不变。
- 打开真实右侧来源、状态或子 agent 面板，主聊天内容仍应避让，不与面板重叠。
- 菜单或顶部组件保持打开时运行只读诊断：瞬态菜单不应成为 `rightFloatingRail`，composer 附着组件应命中专用字段并使用与 layout state 一致的对齐偏移。

## 无法自动验证项

- 当前自动化不在承载任务的 ChatGPT 会话中合成模型选择点击，因此“肉眼无闪屏”和真实菜单 DOM 是否继续提供 `menu/listbox` 语义需要用户操作验收。
- 任务列表 / Git 差异组件只在任务运行窗口短暂存在，离线验证只能覆盖分类、变量和 CSS 契约；最终中心线需在线窗口或用户验收。
- 若验收时官方升级已移除标准 ARIA 角色，新增诊断会提供结构证据，但需回到 IMPLEMENT 扩充稳定信号后重新验证。
