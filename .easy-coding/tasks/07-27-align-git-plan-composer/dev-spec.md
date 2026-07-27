## 技术方案：修复 Git Diff 与 Plan 顶部组件未跟随增强对话框居中

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：让运行任务时出现在 composer 上方的 Git Diff / Plan 组件与增强后的输入框共用同一中心线，不再沿用原生内容中心或重复应用宽屏偏移。
- **输入**：用户截图；当前 ChatGPT Codex 运行态 Git Diff 组件；宽屏增强开启且右侧 `thread-floating-content` rail 触发 `contentOffsetX=-158px` 的布局。
- **输出**：交付形态为改代码；修正 composer 顶部 slot 的识别和动态横向对齐，保留旧 DOM 兼容、右侧 rail 避让、菜单防闪和原生动画，并补齐离线与在线验证。
- **边界**：不修改 ChatGPT/Codex 应用包体、账号或会话数据；不改变 Git Diff / Plan 的内容、宽度、交互和纵向位置；不整体移动右侧 rail、普通会话正文或菜单；不新增配置项、依赖或构建系统；不覆盖当前工作树中 harness 升级与 `data/author-config.json` 的既有修改。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：核心为 `inject-wide-layout.mjs` 的 composer 附着组件分类、属性标记、宽度变量回写和 CSS；回归基线为 `verify.sh`，用户契约为 `README.md`。
- **当前实现方式**：`isComposerAttachedOverlay()` 只接受同时具备 `bottom-full` 锚点和 `composer-home-top-menu` 关联信号的旧版 wrapper（`inject-wide-layout.mjs:1509-1517`）；扫描也只遍历 `[class*='bottom-full']`（`inject-wide-layout.mjs:1628-1639`）。命中后统一使用根或 scope 的 `contentOffsetX` 作为 `--codex-app-extension-aligned-overlay-offset-x`（`inject-wide-layout.mjs:2074-2104`），CSS 再把该值写到 `translate`（`inject-wide-layout.mjs:3240-3244`）。
- **现有问题 / 缺口**：当前官方 DOM 已移除上述旧信号。Git Diff / Plan 位于 composer 同一宿主的顶部 slot，slot 内的 `max-w-(--thread-content-max-width)` wrapper 本来已经和 composer 同中心，却被通用宽屏 CSS 再应用一次 `contentOffsetX`（`inject-wide-layout.mjs:3151-3159`），因此向左重复偏移；旧分类候选为空，专用规则无法接管并归零这个重复位移。
- **证据**：2026-07-27 当前 9229 CDP 只读诊断返回 `composerAttachedOverlayCandidates=[]`；composer shell 为 `left=276/right=1568`，中心 `922px`。Git Diff 的宽度 wrapper class 为 `flex w-full max-w-(--thread-content-max-width) min-w-0 justify-center`，当前 `translate=-158px`、`left=131/right=1397`、中心 `764px`；去掉当前 translate 后自然中心恰为 `922px`。其父级顶部 slot 为 `absolute inset-x-0 bottom-1 ...`，位于同一 composer 宿主内；这证明问题是 `-158px` 被重复应用，而不是缺少一次同方向偏移。当前 diff chip `left=617/right=912`，与 wrapper 共用偏左中心。

### 冲突摘要
- 需求 vs RULES：无冲突；方案保持 UTF-8 / US-ASCII 编码、中文兼容注释、surface guard、失败开放和 `./verify.sh` 基线。
- 需求 vs ABSTRACT：现有摘要仍描述固定继承 `contentOffsetX` 的旧版 `bottom-full` 方案，需要在实现后同步为“旧结构兼容 + 新版 composer 宿主几何对齐”。
- 需求 vs 现有代码：存在冲突；旧分类依赖已消失的类名，且专用偏移被定义为根 `contentOffsetX`，无法区分“需要左移的旧 wrapper”和“已经自然对齐、应归零的新版 wrapper”。
- Dev-Spec vs 现有代码：无未决冲突；保留旧信号为兼容分支，新增 composer 同宿主顶部 slot 分支，并把专用变量语义改为目标相对未应用 CSS translate 时的绝对横向位移。

### 影响面分析
- **涉及模块**：页面运行时注入、composer 顶部组件分类与生命周期、宽屏 CSS、只读诊断、Shell/Node 回归、用户文档。
- **核心类 / 页面 / 接口**：`isComposerAttachedOverlay()`、`getComposerAttachedOverlayTargets()`、`markComposerAttachedOverlays()`、`applyVariables()`、`buildDiagnoseSource()`、`buildCss()` 及 `verify.sh` overlay 回归。
- **数据库变更**：无。
- **接口变更**：有，只增强 `--diagnose` 的只读 `composerAttachedOverlayCandidates` 条目，增加结构类型、当前 translate、自然中心、composer 中心和最终偏移等字段；CLI、配置和既有顶层字段不变。
- **关联历史任务**：`SM-019f8ec0-b3d2-7bb3-8327-54be49bbebf7`（模型菜单与顶部组件对齐修复）；本次以当前运行态 DOM 证据修正其“固定 `bottom-full` + 根偏移”假设。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8；依据：`file -I inject-wide-layout.mjs` | 兼容识别旧版 wrapper 和新版 composer 同宿主顶部 slot；按自然中心计算每个目标的绝对 translate；补充幂等清理与诊断。 |
| `verify.sh` | 修改 | 保持原编码 US-ASCII；依据：`file -I verify.sh` | 增加新旧 DOM 分类、重复偏移归零、旧偏移保留、负例、清理和生成源码回归。 |
| `README.md` | 修改 | 保持原编码 UTF-8；依据：`file -I README.md` | 更新 Git Diff / Plan 动态中心线、旧版兼容、失败开放和诊断字段说明。 |

### 修改方案
- **总体改法**：保留旧版 `bottom-full` 分支，同时从主 composer 定位同一非 layout-shell 宿主中的顶部宽度 slot；对每个目标用“当前矩形中心 - 当前 CSS translate”恢复自然中心，再计算“composer 中心 - 自然中心”作为专用绝对 translate。
- **后端改动**：不涉及。
- **前端改动**：新增稳定的主 composer 查询与最近公共宿主/垂直邻接判定；新版候选必须消费 thread/composer 宽度变量、位于 composer 上方、与 composer 共享非 layout-shell 宿主且不属于瞬态菜单或持久 rail。标记阶段为每个目标写入 `--codex-app-extension-aligned-overlay-offset-x`，CSS 专用规则覆盖通用宽度容器 translate。当前新 DOM 的最终值应为 `0px`；旧 DOM 自然中心右偏 158px 时仍为 `-158px`。
- **兼容处理**：旧 `bottom-full + composer-home-top-menu` 继续支持；既有 `transform` 位移目标继续跳过，避免覆盖原生动画；目标退出、增强关闭或离开 Codex surface 时同时移除属性和行内专用变量。菜单排除、native width reset 和真实右侧 rail 避让保持不变。同步 `.easy-coding/ABSTRACT.md`，但该 harness 知识资产不列入真实项目改动范围表。
- **风险点**：新版几何判定过宽会误命中正文宽度容器；读取 computed `translate` 后若直接基于已偏移矩形计算，可能形成每轮累计。实现必须明确恢复自然中心，并用正负例证明刷新幂等。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 按 composer 宿主与实时几何修复 Git Diff / Plan 顶部组件居中 | frontend/test/docs | `inject-wide-layout.mjs`、`verify.sh`、`README.md`；同步 `.easy-coding/ABSTRACT.md` | — | 新版和旧版顶部组件均与 composer 中心差不超过 2px；普通内容、菜单和右侧 rail 不误标；生命周期清理完整 | 新旧结构正负例、`-158px -> 0px`、`0px -> -158px`、幂等清理、统一回归与在线坐标 | 专用变量表示目标绝对 translate；原生 transform 不覆盖；过期目标移除属性和行内变量 |

**执行策略**：single
- 单一实施单元：分类、几何计算、生命周期、诊断、回归和文档属于同一布局契约，由一个实现单元连续完成，避免平行规则漂移。
（single：按 Standard Workflow Mode 执行一个完整实现单元）

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 新版同宿主顶部 slot、旧版 `bottom-full` 命中，正文/菜单/rail 负例不命中 | 必测 | U1 | 内嵌 Node DOM stub 与生成源码回归 | `./verify.sh` |
| 当前通用 translate 为 `-158px` 且自然中心已对齐时结果为 `0px`；旧版自然中心右偏时结果为 `-158px` | 必测 | U1 | 纯几何函数回归 | `./verify.sh` |
| 原生 transform 跳过、重复刷新不累计、目标退出时清理属性与行内变量 | 必测 | U1 | installer 生命周期契约 | `./verify.sh` |
| JavaScript/Shell 语法、surface guard、菜单排除、rail 避让、app.asar 锚点和补丁格式 | 必测 | U1 | 项目统一回归 | `node --check inject-wide-layout.mjs && bash -n verify.sh && ./verify.sh && git diff --check` |
| 重注入后 Git Diff / Plan 与 composer 中心差不超过 2px | 应测 | U1 | 当前 9229 CDP 在线坐标验收 | `./inject-current.sh && ./inject-current.sh --diagnose` |

- **人工验收**：运行任务观察 Git Diff 与 Plan 顶部组件，确认它们与输入框同中心且点击/展开正常；打开右侧 rail 和模型菜单，确认避让与防闪未回归。
- **无法验证项**：Plan 组件若在最终验证窗口未出现，只能以同一顶部 slot 结构回归和 Git Diff 在线坐标作为自动证据，Plan 视觉留作人工验收。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：standard
- **推荐并选择**：standard
- **选择原因**：状态 API 因 `multi-file-impact` 给出 Standard 下限；虽然只有一个实现单元，但涉及运行时 DOM 分类、几何状态、CSS 生命周期、诊断与多文件契约，且需要保留旧结构和现有 rail/menu 行为。
- **状态内执行差异**：IMPLEMENT 完成单一完整单元并做定向回归；REVIEW 检查分类误判、偏移幂等、清理和兼容边界；VERIFICATION 运行受影响的完整 `./verify.sh`、语法、编码、diff-check 与在线 CDP 坐标；MEMORY 记录官方 DOM 演进和动态中心线算法。

### 风险与注意事项
- 不再把 `--codex-app-extension-aligned-overlay-offset-x` 简单等同于根 `contentOffsetX`；它是目标相对自然位置的绝对 translate。
- 新版 slot 识别必须要求与主 composer 共享非 layout-shell 宿主并位于其上方，不能只凭 `max-w` 或 `justify-center` 类名。
- 任何已有原生 `transform` 的目标保持失败开放；不通过覆盖动画来换取静态居中。
- 当前工作树已有 harness 升级和 `data/author-config.json` 修改，实施仅触碰本任务列明的代码/文档及 task/knowledge 资产。
