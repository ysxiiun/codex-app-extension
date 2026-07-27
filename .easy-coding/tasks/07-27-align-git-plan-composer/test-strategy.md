# 测试策略：Git Diff / Plan 顶部组件跟随增强 composer 居中

## 变更可测性

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| 新版 composer 顶部 slot 识别 | layout classification | [must-test] | 当前官方 DOM 已移除旧 `bottom-full` 信号，必须证明新结构命中且普通正文不命中 |
| 旧版 `bottom-full + composer-home-top-menu` 兼容 | layout classification | [must-test] | 已支持结构不能因本次修复回归 |
| 基于自然中心的绝对 translate 计算 | geometry calculation | [must-test] | 当前问题来自已有 `-158px` 被重复应用，需覆盖归零与保留旧偏移两种方向 |
| 属性、行内变量与跟踪目标清理 | lifecycle state | [must-test] | MutationObserver 会重复刷新，写入必须幂等且不能遗留过期偏移 |
| 诊断投影 | diagnose projection | [should-test] | 在线验收依赖目标类型、当前/自然/目标中心与最终偏移证据 |
| `README.md`、`.easy-coding/ABSTRACT.md` | documentation | [no-test] | 只同步行为契约，通过内容核对与 diff 检查验证 |

## 测试点

| ID | 测试点 | 归属单元 | 验证方式 | 验证命令 |
|---|---|---|---|---|
| T1 | 新版同一 composer 宿主内、位于输入框上方且消费 thread 宽度变量的居中 slot 被识别 | U1 | 内嵌 Node DOM stub / 生成源码行为回归 | `./verify.sh` |
| T2 | 旧版 `bottom-full + composer-home-top-menu` 继续命中 | U1 | 既有分类契约回归 | `./verify.sh` |
| T3 | 普通会话正文宽度容器、瞬态 `menu/listbox`、持久 `thread-floating-content` 与无共同 composer 宿主的元素不命中 | U1 | 正负例分类回归 | `./verify.sh` |
| T4 | 当前 wrapper 已受通用 `translate:-158px` 且自然中心等于 composer 时，专用绝对偏移计算为 `0px` | U1 | 纯几何函数回归 | `./verify.sh` |
| T5 | 旧版 wrapper 当前 translate 为 `0px`、自然中心比 composer 右偏 158px 时，专用绝对偏移为 `-158px` | U1 | 纯几何函数回归 | `./verify.sh` |
| T6 | 原生 `transform` 位移目标跳过；重复刷新不累计偏移；目标退出时属性和行内变量均清理 | U1 | 生成 installer 生命周期契约 | `./verify.sh` |
| T7 | CSS 只让已标记目标消费专用变量；native width reset、菜单排除和真实 rail 避让保持 | U1 | 生成 CSS / installer 契约断言 | `./verify.sh` |
| T8 | diagnose 输出目标结构类型、当前 translate、自然中心、composer 中心、最终偏移与坐标 | U1 | 生成 diagnose 源断言 | `./verify.sh` |
| T9 | JavaScript/Shell 语法、surface guard、启动链、app.asar 锚点和补丁格式均通过 | U1 | 项目统一验证 | `node --check inject-wide-layout.mjs && bash -n verify.sh && ./verify.sh && git diff --check` |
| T10 | 重注入后当前 Git Diff / Plan 顶部组件与 composer 中心差不超过 2px，右侧 rail 仍正常避让 | U1 | 在线诊断与坐标探针 | `./inject-current.sh && ./inject-current.sh --diagnose` |

## No-test 原因

- `README.md` 与 `.easy-coding/ABSTRACT.md` 不执行运行时逻辑；通过内容契约、编码和 `git diff --check` 核对。

## 人工验收

- 任务运行期间观察 Git Diff 组件，确认它与增强后的输入框共用中心线，点击与展开行为正常。
- Plan 组件出现时重复观察，确认同一顶部 slot 不再沿用原生旧中心。
- 打开真实右侧来源、状态或子 agent panel，确认主内容继续避让，顶部组件没有随右侧 rail 错误移动。
- 打开模型菜单保持至少 5 秒，确认既有菜单防闪修复未回归。

## 无法自动验证项

- Plan 组件只在特定任务阶段出现；如果最终验证窗口中未出现，只能以同一顶部 slot 的结构回归和 Git Diff 在线坐标作为自动证据，Plan 视觉留作人工验收。
