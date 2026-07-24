# 测试策略：通用菜单 wrapper 的 rail 误判修复

## 1. 可测试性分类

| 变更 | 类型 | 结论 | 原因 |
|---|---|---|---|
| `isTransientInteractiveOverlay()` 对称 menu/listbox 语义闭包 | 页面侧分类函数 | [must-test] | Bug 根因是确定的 selector 方向遗漏，可用最小 HTMLElement stub 验证输入输出；Bug 修复必须有回归 |
| `findRightFloatingRail()` 在几何测量前排除 wrapper | 布局候选控制流 | [must-test] | 必须保证排除发生在 `getBoundingClientRect()` 与 `candidates.push()` 前，防止宽度回写再次形成反馈环 |
| `transientInteractiveOverlayCandidates` 补齐最近定位 wrapper | 只读诊断 | [should-test] | 诊断是运行时排障契约，需要验证 role 节点、定位 wrapper、去重和可见性过滤 |
| 模型二级菜单与文件打开方式菜单的 composer 宽度稳定性 | UI 交互 | [depends] | 可通过当前调试端口逐帧量化宽度；最终肉眼闪烁感仍需人工确认 |
| README 诊断字段说明 | 文档 | [no-test] | 无运行逻辑；通过文本契约检查和人工复核验证 |

## 2. 测试点

| 测试点 | 归属单元 | 验证方式 | 验证命令 |
|---|---|---|---|
| `role=menu` / `role=listbox` 自身命中 | U1 | 从生成 installer 源提取分类函数，以最小 HTMLElement stub 执行正例 | `./verify.sh` |
| menu/listbox 内部节点通过完整 selector 的 `closest()` 命中 | U1 | menu 与 listbox 各一组祖先正例 | `./verify.sh` |
| `fixed wrapper > role=menu` 与 `fixed wrapper > role=listbox` 通过完整 selector 的 `querySelector()` 命中 | U1 | 后代 menu/listbox 正例；旧实现的后代 menu 用例必须失败 | `./verify.sh` |
| 普通持久 rail 不命中瞬态分类 | U1 | 无匹配自身、祖先、后代的负例 | `./verify.sh` |
| rail 扫描先做瞬态/附着浮层排除，再读取几何并入列；真实 rail 逻辑保留 | U1 | 生成源码控制流顺序断言 | `./verify.sh` |
| 诊断候选同时包含可见 role 节点和最近 fixed/absolute/sticky wrapper，并去重 | U1 | 诊断生成源码结构断言 | `./verify.sh` |
| Node ESM、Shell 语法、生成 CSS/installer/diagnose 和既有回归全部通过 | U1 | 项目统一验证 | `node --check inject-wide-layout.mjs`；`bash -n verify.sh`；`./verify.sh` |
| 当前 Codex 主工作区可在线诊断 | U1 | 连接 `127.0.0.1:9229` 的受支持 surface | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |
| 右侧栏打开时，文件打开方式菜单开启前后 composer 保持基线宽度；模型二级菜单同样稳定 | U1 | 重注入后 CDP 在 `0/16/40/80/120/200/340/500ms` 采样左右边界、宽度、`runCount` 与 rail 候选 | 任务内 CDP 几何验收 |

## 3. 不测试项及原因

- README 不执行行为测试；只校验文字与实际诊断字段、分类语义一致。
- 不为 ChatGPT/Codex 原生模型触发器的 `115px → 224px` 展开动画加测试或覆盖样式；本任务只修复扩展把菜单 wrapper 误判为 rail 后造成的 composer 整体缩窄。

## 4. 人工验收

- 保持右侧栏打开，打开文件卡片的“打开方式”菜单并停留至少 5 秒，再关闭；底部 composer 左右边界不应变化，菜单选项仍可正常点击。
- 打开模型一级菜单，再打开“模型”二级菜单并停留至少 5 秒，再逐层关闭；底部 composer 不应在宽窄状态间切换，模型选择保持正常。
- 打开真实持久右侧 rail，确认正文和 composer 仍会合理避让，不与 rail 重叠。
- 检查 composer 顶部任务列表 / Git 差异组件仍与 composer 中心线对齐。

## 5. 当前无法完全自动验证项

- 自动化可以量化 DOM 几何、布局刷新和分类结果，但“肉眼完全无闪感”及连续操作手感需要用户最终视觉验收。
