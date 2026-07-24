## 技术方案：修复模型菜单闪烁与 composer 上方组件错位

### 修订摘要
- 保留原需求：修复一级/二级模型选择菜单被误判为 right rail 后触发的 composer 宽度反馈闪烁。
- 新增需求：运行任务时，composer 上方的任务列表与 Git 差异组件必须跟随增强后的 composer 中心线，而不是继续按增强前中心对齐。
- 方案影响：浮层分类从“原生 / 非原生”细化为“瞬态菜单、composer 附着组件、持久 right rail”三类；新增附着组件对齐偏移、诊断与回归验收。文件编码要求不变。

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：同时消除模型选择菜单打开后的 composer 宽度闪屏，并让运行态任务列表 / Git 差异顶部组件与增强后的 composer 使用同一中心线；真正右侧 floating rail 仍正常避让。
- **输入**：用户提供的模型菜单两帧截图与新增对齐反馈；触发条件分别为右侧一级/二级模型菜单打开，以及任务执行期间 composer 上方出现 `bottom-full` 顶部组件。
- **输出**：交付形态为改代码；建立三类浮层语义，修正菜单 rail 误判，为 composer 附着组件应用独立且可诊断的对齐偏移，补充回归验证并同步用户文档与架构摘要。
- **边界**：不修改 ChatGPT/Codex 应用包体、账号或会话数据；不改模型菜单或任务/Git 组件的原生尺寸、内容、动画与交互；不让持久右侧状态/来源/子 agent panel 跟随 composer 左移；不关闭宽屏增强，不新增配置项、依赖或构建系统。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：核心在 `inject-wide-layout.mjs` 的 `buildInstallerSource()`、原生浮层标记、right rail 检测、宽度/偏移变量回写与观察器刷新链（`inject-wide-layout.mjs:1238`、`inject-wide-layout.mjs:1283-1306`、`inject-wide-layout.mjs:1431-1537`、`inject-wide-layout.mjs:1658-1711`、`inject-wide-layout.mjs:1938-1967`、`inject-wide-layout.mjs:2091-2163`）；CSS 在原生浮层子树内把宽度变量改为 `100vw` 并把内容偏移清零（`inject-wide-layout.mjs:3082-3097`）。
- **当前实现方式**：`findRightFloatingRail()` 对所有 `absolute/fixed/sticky` 元素做通用几何筛选并选择最靠左候选（`inject-wide-layout.mjs:1658-1711`）；`NATIVE_FLOATING_STRUCTURAL_SELECTOR` 又把所有 class 含 `bottom-full` 的结构都标为原生浮层（`inject-wide-layout.mjs:1285-1298`、`inject-wide-layout.mjs:1488-1537`）。该标记统一隔离 thread/composer 宽度并把 `--codex-app-extension-content-offset-x` 重置为 `0px`（`inject-wide-layout.mjs:3082-3097`），没有区分持久右侧 panel 与跟随 composer 的顶部附着组件。
- **现有问题 / 缺口**：第一，模型 `menu/listbox` 定位 wrapper 没有语义排除，靠近右边界时可在 rail 阈值内外往返，触发“宽度回写—菜单重定位—再测量”反馈环（`inject-wide-layout.mjs:1663-1695`、`inject-wide-layout.mjs:2024-2067`、`inject-wide-layout.mjs:2129-2163`）。第二，运行态顶部组件的 `absolute left-0 right-0 bottom-full` wrapper 被统一清零偏移，内部虽然避免了宽度变量污染，外层却不再跟随 composer 的左移。
- **证据**：模型菜单两帧中 composer 和菜单在两个横向位置间同步切换。2026-07-23 在线诊断确认主 reference 为 2291px、常驻 rail 为 316px、composer 偏移为 `-158px`；运行态只读 DOM 探针同时捕获顶部组件 wrapper 宽 1768px、位置 `left=530/right=2298`、`contentOffsetX=0px`、`nativeFloatingPanel=true`，而 composer 为 `left=372/right=2140`、`contentOffsetX=-158px`，两条中心线恰好相差 158px。现有诊断只记录原生 floating reset target 和最终 rail，没有单列瞬态菜单或 composer 附着组件（`inject-wide-layout.mjs:1095-1111`、`inject-wide-layout.mjs:1165-1192`）。

### 冲突摘要
- 需求 vs RULES：无冲突；方案沿用现有运行时注入和失败开放边界，不新增依赖，保持文件编码，并用 `--diagnose` 暴露分类结果。
- 需求 vs ABSTRACT：无冲突；保留页面侧“按真实工作区计算宽度 + 避让持久 right rail + 隔离原生浮层”的数据流，细化浮层角色与偏移传播。
- 需求 vs 现有代码：存在两处实现冲突；通用 rail 几何启发式会吸收瞬态菜单，统一 native-floating reset 又会清除 composer 附着组件所需的对齐偏移。
- Dev-Spec vs 现有代码：无未决冲突；菜单在几何候选入口排除，composer 附着组件保留内部宽度隔离，但外层使用独立、不会被 native reset 清零的对齐变量；持久 rail 维持 `0px` 局部偏移。

### 影响面分析
- **涉及模块**：页面运行时注入、宽屏布局 right rail 分类、只读诊断、离线验证、用户文档。
- **核心类 / 页面 / 接口**：`buildInstallerSource()`、`getNativeFloatingPanelTargets()`、新增 composer 附着组件识别/标记、`findRightFloatingRail()`、宽度变量集合及 `applyVariables()`、`buildCss()`、`buildDiagnoseSource()`、`./verify.sh` 的内嵌 Node 回归。
- **数据库变更**：无。
- **接口变更**：有，仅在 `--diagnose` JSON 中新增只读的瞬态交互浮层候选与 composer 附着组件字段；CLI、配置文件、环境变量和既有诊断字段不变。
- **关联历史任务**：`SM-20260708-002`（原生 git 浮层兼容）、`SM-20260708-003`（左侧栏布局修复）、`SM-20260713-005`（CDP target 与主工作区诊断经验）。

### 背景数据应用
- `.easy-coding/SOUL.md` 与 `.easy-coding/RULES.md` 将运行时低侵入、surface guard、失败开放、可诊断和 `./verify.sh` 设为硬边界，因此方案只调整注入页面内的分类，不触碰应用包体，也不新增并行实现链路。
- 长期技术记忆“运行时注入架构”“配置化增强链路”“输入与布局增强边界”要求复用现有注入/观察框架并暴露诊断；短期记忆 `SM-20260708-002` 要求原生 Git/Diff 浮层继续隔离宽度变量，本次因此不撤销 native reset，而是单独恢复 composer 附着 wrapper 的位置对齐。
- 当前代码与 2026-07-23 在线探针优先于旧记忆；方案保留 316px 常驻 `thread-floating-content` rail 和既有 Git/Diff 内部隔离，只改变两类被误处理的菜单/附着组件。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8；依据：`file -I inject-wide-layout.mjs` | 建立瞬态菜单 / composer 附着组件 / 持久 rail 三类判定；新增附着组件属性与独立对齐偏移变量，补充诊断。 |
| `verify.sh` | 修改 | 保持原编码 US-ASCII；依据：`file -I verify.sh` | 回归菜单排除、附着组件识别、偏移变量传播、native reset 保留、持久 rail 不跟随及 diagnose/installer 生成源码。 |
| `README.md` | 修改 | 保持原编码 UTF-8；依据：`file -I README.md` | 说明菜单不参与 rail、顶部任务/Git 组件跟随 composer 中心线，以及新增诊断字段。 |

### 修改方案
- **总体改法**：把浮层处理拆为三条互斥职责：`menu/listbox` 瞬态浮层不参与 rail；包含 `composer-home-top-menu`、锚定在 composer 上方的 `bottom-full` wrapper 继续隔离内部宽度变量，但外层跟随 composer 对齐；`thread-floating-content` 等持久 rail 保持现有避让和 `0px` 局部偏移。
- **后端改动**：不涉及。
- **前端改动**：新增可回归的瞬态菜单与 composer 附着组件判定；`findRightFloatingRail()` 在几何测量前排除两者。新增例如 `--codex-app-extension-aligned-overlay-offset-x` 的布局偏移变量，由 root/scope 写入但不在 native-floating 子树清零；仅给经确认的 composer 附着 wrapper 应用该横向位移。`buildDiagnoseSource()` 输出两类目标、computed offset 与坐标。
- **兼容处理**：保留 native-floating 的 `100vw` 宽度隔离和内部 `contentOffsetX=0px`，避免旧 Git/Diff 压窄问题回归；保留真实 right rail 的几何计算、`useAsLayoutScope` 与局部零偏移。附着组件以 `bottom-full` + `composer-home-top-menu` / composer 关联信号识别，信号不完整时不强制移动。同步 `README.md` 与 `.easy-coding/ABSTRACT.md`；后者是 harness 知识资产，不计入真实项目代码改动范围表。
- **风险点**：附着 wrapper 若已有原生 `translate/transform` 动画，直接覆盖可能破坏纵向动画；实现需只作用于已验证的无原生位移 wrapper，或用不会覆盖原生 transform 的定位方式。官方若变更 ARIA 或 `composer-home-top-menu` 信号，诊断应能暴露未命中。

### 前端实现映射

| 交互 / 页面结构 | 当前行为 | 目标行为 | 验收映射 |
|----------------|---------|---------|---------|
| 一级设置菜单与二级模型菜单的 `menu/listbox` 浮层及定位 wrapper | 被通用几何启发式当成 right rail，菜单重定位与 composer 宽度互相反馈 | 被诊断记录但在 rail 几何测量前排除，不改菜单自身 DOM/样式 | 菜单保持打开 5 秒，composer 和菜单横向位置稳定 |
| 运行态 `bottom-full` 任务列表 / Git 差异顶部组件 | native-floating reset 保住了内部尺寸，却把横向偏移清零，中心线比 composer 向右偏 `appliedLeftShiftPx` | 内部宽度隔离不变，外层使用独立对齐偏移与 composer 同中心 | 探针中两者中心差不超过 2px；组件宽度、内容和交互不变 |
| 常驻 `thread-floating-content`、来源/状态/子 agent 右侧区域 | 作为 right rail 收敛可用宽度，部分原生面板不作为独立 scope | 完全沿用现有识别、避让和 scope 隔离 | 在线诊断仍返回真实 rail，主内容不与右侧面板重叠 |
| MutationObserver / ResizeObserver 刷新链 | 菜单定位与扩展变量回写可形成非幂等循环，附着组件创建/销毁后统一 reset | observer 机制不变，刷新时重算三类目标并幂等更新属性/偏移 | 菜单和任务组件开合无持续跳变；真实 rail 变化仍能刷新 |

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U1 | 重构浮层三分类，修复菜单闪烁与顶部组件对齐并补齐回归/文档 | frontend/test/docs | `inject-wide-layout.mjs`、`verify.sh`、`README.md`；同时同步项目知识资产 `.easy-coding/ABSTRACT.md` | — |

**执行策略**：single
- 单一实施单元：U1 同时完成同一浮层分类链的运行时代码、CSS/变量传播、回归验证和契约文档，避免两项问题由不一致的平行规则处理。
（single：单一实施单元，派发 1 个子代理执行）

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 判定函数对自身为 `menu`、祖先为 `menu`、后代为 `listbox` 的定位 wrapper 均返回 true，对普通持久 rail 返回 false | 必测 | U1 | 内嵌 Node 纯函数回归 | `./verify.sh` |
| `bottom-full` + composer top menu 被识别为附着组件，普通 `thread-floating-content` 不被识别；附着组件仍保留 native width reset | 必测 | U1 | 内嵌 Node 分类与生成 CSS 回归 | `./verify.sh` |
| root/scope 写入独立对齐偏移，native reset 不清零该变量，只有附着 wrapper 使用它；菜单/附着组件均在 rail 几何测量前排除 | 必测 | U1 | 生成 installer/CSS 契约断言 | `./verify.sh` |
| diagnose/installer 源可编译且包含两类新增诊断；既有 surface guard、CSS scope、Shell 启动链和 app.asar 锚点不回归 | 必测 | U1 | 项目统一回归 | `./verify.sh` |
| 当前 CDP 主工作区只读诊断成功，常驻 `thread-floating-content` 继续作为 right rail；运行态顶部组件中心与 composer 中心差不超过 2px | 应测 | U1 | 在线只读诊断 + 坐标探针 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |

- **人工验收**：重注入后依次打开一级、二级模型菜单并保持至少 5 秒，确认 composer/菜单不横向往返且选择正常；运行一次任务，确认任务列表/Git 差异顶部组件与 composer 同中心、尺寸和交互不变；再打开真实右侧来源/状态/子 agent panel，确认其仍固定在右侧且主内容正常避让。
- **无法验证项**：自动验证不会在承载当前任务的 ChatGPT 会话中合成模型选择点击；运行态顶部组件也只在任务执行窗口短暂存在。最终视觉需用户操作，或在对应组件保持可见时运行诊断/坐标探针。

### 风险与注意事项
- 只排除标准 `menu/listbox` 语义，避免把所有 popover 一刀切；若官方 DOM 移除 ARIA 角色，需依据新增诊断再补充稳定信号。
- composer 附着组件只移动外层位置，不撤销其内部宽度隔离；不得把 `thread-floating-content` 右侧 rail 一并左移。
- 不通过延长 debounce、冻结宽度或全局移动所有 `bottom-full` 掩盖问题；这些方案会保留错误分类或破坏真实 panel。
- MutationObserver 仍会收到菜单定位与顶部组件创建/销毁事件；三分类修正后变量/属性写入必须幂等，不形成新的观察器反馈。
