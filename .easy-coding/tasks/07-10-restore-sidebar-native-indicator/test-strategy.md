# 测试策略：复核侧边栏白色竖条并保护原生状态指示

## 可测试性分类

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| `summarizeSidebarFolderRow` 新增 scrollbar 尺寸、滚动范围和状态节点摘要 | 诊断数据构造 | [must-test] | 输出字段与判定关系明确，且本次问题源自错误视觉归因 |
| `buildCss` 保持项目行 `overflow-y:hidden` 且不隐藏原生状态层 | CSS 生成 | [must-test] | Bug 修复必须有回归断言，生成 CSS 可稳定检查 |
| `verify.sh` 新增诊断源码与 CSS 断言 | 验证脚本 | [must-test] | 项目统一验证入口必须以真实执行结果证明新增断言有效 |
| README 诊断字段与视觉语义说明 | 文档 | [no-test] | 无独立行为；通过字段静态一致性检查和人工审阅覆盖 |
| 活动项目折叠/展开时加载指示位置变化 | UI 交互 | [depends] | 依赖正在运行且存在活动任务的 ChatGPT Codex 实例 |
| 未读点与未读数量状态 | UI 状态 | [depends] | 依赖真实未读状态，当前环境无法安全制造该业务状态 |

## 测试点

| ID | 归属单元 | 测试点 | 预期结果 | 验证命令 |
|---|---|---|---|---|
| T1 | U1、U2 | 编译生成后的 diagnose source | 新增字段存在，生成源码可由 `new Function` 编译 | `./verify.sh` |
| T2 | U1、U2 | 项目行 CSS 回归 | CSS 含受 surface guard 约束的 `overflow-y:hidden`；不含针对状态节点的 `display:none` / `visibility:hidden` | `./verify.sh` |
| T3 | U2 | 全量项目静态验证 | ESM 语法、Bash 语法、JSON、生成源码、target/surface/request-input 既有断言全部通过 | `./verify.sh` |
| T4 | U3 | README 与诊断字段一致性 | 文档列出的字段名与 `buildDiagnoseSource` 生成结果一致 | `./verify.sh` |
| T5 | U1 | 在线侧栏状态验收 | 普通项目无白色 scrollbar；折叠活动项目时项目行显示加载动画；恢复展开后任务行显示加载动画 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh`、`./inject-current.sh --diagnose`、人工观察 |

## No-test 理由

- README 是说明性文本，不新增可执行行为；字段拼写纳入 T4，语义准确性由评审与人工验收确认。

## 人工验收

- 普通项目行右侧不出现成排白色竖条。
- 运行中任务仍显示圆形加载动画；将活动项目折叠后，加载动画出现在项目行右侧。
- 项目行 hover 后，新建任务与项目菜单仍可交互。
- 长项目名的可用宽度不低于当前增强版本。

## 无法验证项

- 未读数量徽标与未读圆点：当前实例没有对应未读状态；不通过修改账号数据或任务数据制造状态，待自然出现时人工确认。
- 旧版独立 `Codex.app` 在线 UI：当前机器运行的是 `ChatGPT.app`；通过保留选择器、生成源码验证和失败开放策略覆盖静态兼容。
