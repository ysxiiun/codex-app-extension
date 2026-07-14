[阶段：ANALYSIS]

## 技术方案：复核侧边栏白色竖条并保护原生状态指示

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：重新判定侧边栏项目行右侧白色竖条的原生语义；若它是 Codex 用于表达项目行状态或操作的原生能力，则撤销扩展对该能力的误伤，同时保留项目名不过早截断的既有修复。
- **输入**：用户指定的历史记忆 `.easy-coding/memory/short/003_20260708_左侧栏项目行布局修复.md`、当前 `inject-wide-layout.mjs` 中针对项目行 overflow 与尾部操作容器的覆盖、当前 ChatGPT Codex 页面可获得的 DOM / computed style 证据。
- **输出**：改代码；白条被证实不是功能后不做恢复，改为增强真实注入诊断与回归保护，明确区分 scrollbar 伪影和原生加载/未读状态指示，并提供静态验证、诊断证据和人工验收项。
- **边界**：不修改 ChatGPT/Codex 应用包体、账号或历史数据；不移除侧边栏宽屏变量隔离；不改变主会话宽屏、右侧 floating rail、git/diff 浮层和输入增强；若运行时无法连接，不把仅凭 class 名或颜色的推测写成确定结论。

### 背景数据应用
- `.easy-coding/RULES.md` 要求页面注入失败开放、选择器受 Codex surface 约束、用户可见诊断字段同步 README，并在修改后执行 `./verify.sh`；因此方案只扩展现有诊断链路，不把诊断结果接入布局决策。
- `.easy-coding/memory/long/TECHNICAL.md` 的“当前实例重注入流程”和“输入与布局增强边界”要求先静态验证、再按条件执行在线 CDP；本次已用当前 9229 端口完成原生/增强对照。
- `SM-20260708-003` 当时把白条归因为项目行 scrollbar 并实施隐藏；本次用 `clientWidth/scrollHeight` 和折叠活动项目探针复核后，确认“白条是 scrollbar 伪影”仍成立，但补充了“真正的加载/未读状态指示未被隐藏”的证据。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`buildDiagnoseSource` 负责抽样左侧栏项目行，`buildCss` 负责隔离侧栏宽屏变量、隐藏项目行纵向 overflow，并把尾部菜单/状态容器改为绝对定位；README 将 `leftSidebar` 与 `sidebarProjectRows` 定义为相关诊断字段（`inject-wide-layout.mjs:1113-1130`、`inject-wide-layout.mjs:2998-3080`、`README.md:381-382`）。
- **当前实现方式**：扩展启用时，项目行保持 `overflow-x:hidden`，同时被覆盖为 `overflow-y:hidden`；尾部容器从原生静态布局改为绝对定位，以释放项目标题宽度。当前实时 CDP 抽样中，行宽 240px、`clientWidth=240`、无竖向滚动条，内容宽度 240px；临时禁用扩展样式后，原生行仍宽 240px，但 `overflow-y:auto` 使 `clientWidth` 降到 225px，且 `scrollHeight === clientHeight === 30`，说明 15px 白色竖条没有任何滚动范围（`inject-wide-layout.mjs:3039-3048`、`inject-wide-layout.mjs:3050-3080`）。
- **现有问题 / 缺口**：白色竖条本身不是 Codex 状态功能，而是原生 `overflow-x:hidden` 在双轴 overflow 计算下产生的无滚动范围 scrollbar gutter；真正的原生状态功能是加载动画、未读点和未读数量。实时探针把当前项目折叠后，尾部状态容器出现 `animate-spin` SVG，随后恢复展开状态，证明现有 CSS 没有删除该功能。当前诊断只输出通用元素尺寸，未直接暴露 `clientWidth/scrollHeight`、滚动范围和原生状态节点，容易再次把两者混淆（`inject-wide-layout.mjs:1114-1129`、`README.md:421`）。
- **证据**：项目行诊断构造见 `inject-wide-layout.mjs:1113-1130`；白条抑制和标题宽度释放规则见 `inject-wide-layout.mjs:3030-3080`；现有生成 CSS 校验只覆盖表面作用域，未断言侧栏滚动条/状态诊断语义，见 `verify.sh:98-108`；诊断字段说明见 `README.md:381-382`，兼容说明见 `README.md:421`。补充运行时证据：2026-07-10 本机 ChatGPT Codex CDP 对照为原生 `offsetWidth=240/clientWidth=225/scrollHeight=clientHeight=30`，扩展启用后 `offsetWidth=clientWidth=240`；折叠活动项目时原生 `animate-spin` 状态节点在当前 CSS 下仍存在。

### 冲突摘要
- 需求 vs RULES：无冲突；结论来自实时 CDP 与真实源码，保持应用包体和用户数据只读。
- 需求 vs ABSTRACT：无冲突；继续复用现有 CDP 诊断和单一 CSS 注入链路，不新增依赖或旁路实现。
- 需求 vs 现有代码：存在前提冲突。用户要求“若是功能则恢复”，但白色竖条没有滚动范围，实际状态指示功能在现有修复下仍正常；直接恢复白条会重新吞掉每行 15px 标题宽度并制造无意义 scrollbar。
- Dev-Spec vs 现有代码：无冲突；方案不恢复白条、不改变当前视觉行为，只补足可机械判定的诊断字段、回归断言和说明，保护真正的原生状态指示。

### 待用户决策
- 是否接受推荐方案：不恢复无功能的白色 scrollbar，只实施“区分 scrollbar 伪影与原生状态指示”的诊断增强和回归保护。若你只需要本次分析结论、不希望产生任何项目代码改动，应明确选择修订计划并无代码关闭本任务。

### 影响面分析
- **涉及模块**：运行时诊断源码生成、侧边栏项目行 CSS 回归保护、项目统一验证脚本、诊断文档。
- **核心类 / 页面 / 接口**：`buildDiagnoseSource`、`summarizeSidebarFolderRow`、`buildCss`、`./verify.sh` 生成源码断言、README 的 `sidebarProjectRows` 说明。
- **数据库变更**：无。
- **接口变更**：有；仅向 `--diagnose` 的 `sidebarProjectRows` 条目追加兼容字段，不删除或改名现有字段。
- **关联历史任务**：`SM-20260708-003`（左侧栏项目行布局修复）、`SM-20260710-004`（ChatGPT Codex 兼容适配）。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8；依据：`file -I inject-wide-layout.mjs` | 为项目行诊断追加 client/scroll 尺寸、scrollbar gutter、可滚动范围与原生状态节点摘要；保留当前隐藏无功能白条和尾部状态可见的 CSS。 |
| `verify.sh` | 修改 | 保持原编码 US-ASCII；依据：`file -I verify.sh` | 在现有 Node 生成源码验证中增加侧栏诊断字段与 CSS 保护断言，错误文本保持 ASCII。 |
| `README.md` | 修改 | 保持原编码 UTF-8；依据：`file -I README.md` | 明确区分无滚动范围的白色 scrollbar 与加载/未读原生状态指示，并记录新增诊断字段。 |

### 修改方案
- **总体改法**：不恢复白色 scrollbar；在现有 `sidebarProjectRows` 诊断中同时输出“是否有 scrollbar gutter / 是否存在真实滚动范围 / 是否存在原生状态节点”，并用验证脚本锁定当前 CSS 仍隐藏伪影、仍不隐藏状态指示。
- **后端改动**：不涉及。
- **前端改动**：扩展 `summarizeSidebarFolderRow`：记录 `offsetWidth/clientWidth/clientHeight/scrollWidth/scrollHeight`，计算 `verticalScrollbarWidth` 与 `hasVerticalScrollRange`；识别项目行尾部 grid 的直接 `div` 状态层并输出 `nativeStatusIndicator` 摘要，不依赖文案或应用私有状态对象。CSS 视觉规则不做恢复性改动。
- **兼容处理**：只新增诊断 JSON 字段，保留 `row/title/directChildren`；状态节点识别失败时返回 `null`，不影响注入；ChatGPT 与旧 Codex 仍使用同一 `group/folder-row` 兼容选择器。验证脚本以生成源码和 CSS 内容断言为主，不依赖正在运行的应用。
- **风险点**：Codex 升级可能调整尾部 grid 的直接子节点结构；因此诊断必须失败开放且不得参与运行时布局决策。不要把 `verticalScrollbarWidth > 0` 单独解释为可滚动，必须同时检查 `hasVerticalScrollRange`。

### 前端实现映射

| 用户可见对象 / 交互 | 当前事实 | 目标实现 |
|--------------------|---------|---------|
| 项目行右侧成排白色竖条 | `overflow-y:auto` 产生 15px scrollbar gutter，但没有竖向滚动范围 | 继续由现有 CSS 隐藏，不恢复 |
| 活动任务加载状态 | 展开项目时显示在任务行；折叠活动项目时显示在项目行尾部 grid | 保持原生 DOM、动画和 hover 隐藏逻辑，诊断仅识别并报告 |
| 未读点 / 未读数量 | 与加载状态共用原生状态层，当前现场没有未读样本 | 保持原生结构；诊断识别失败时返回 `null`，不影响交互 |
| 项目 hover 操作 | 尾部新建任务/菜单在 hover 或 focus-within 时恢复交互 | 保持现有绝对定位与 pointer-events 切换，并用人工验收防回归 |

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U1 | 增强项目行 scrollbar 与原生状态指示诊断 | frontend | `inject-wide-layout.mjs` | — |
| U2 | 增加生成源码与 CSS 回归断言 | test | `verify.sh` | U1 |
| U3 | 更新诊断字段和视觉语义说明 | docs | `README.md` | U1, U2 |

**执行策略**：sequential
- 第一批：U1 增强项目行 scrollbar 与原生状态指示诊断
- 第二批（等待 U1）：U2 增加生成源码与 CSS 回归断言
- 第三批（等待 U1、U2）：U3 更新诊断字段和视觉语义说明

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 生成的诊断源码包含 scrollbar 尺寸、真实滚动范围和原生状态节点字段，且可编译 | 必测 | U1、U2 | 生成源码回归断言 | `./verify.sh` |
| 生成 CSS 继续对项目行设置 `overflow-y:hidden`，且不对原生状态节点施加 `display:none` / `visibility:hidden` | 必测 | U1、U2 | CSS 内容回归断言 | `./verify.sh` |
| 现有 surface guard、target guard、request input 与全部既有增强无回归 | 必测 | U2 | 项目统一验证 | `./verify.sh` |
| README 字段名与实际诊断 JSON 一致 | 应测 | U3 | 静态检索 + 统一验证 | `./verify.sh` |
| 当前 ChatGPT Codex 中活动项目折叠后仍显示加载指示，展开后任务行继续显示加载指示 | 应测 | U1 | 在线 CDP 诊断 + 人工视觉验收 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh`、`./inject-current.sh --diagnose` |

- **人工验收**：确认普通项目行右侧不再出现成排白色竖条；有运行任务时，展开项目的任务行和折叠项目的项目行仍出现圆形加载动画；hover 时新建任务/项目操作按钮仍可点击；长项目名不比当前版本更早截断。
- **无法验证项**：当前运行时可验证 `loading` 指示；`unreadCount` 与 `unread` 圆点需要真实未读状态才能现场观察，本次以 Codex 打包源码语义、DOM 结构兼容和失败开放诊断覆盖，列入用户后续状态验收。

### 风险与注意事项
- 不应恢复白色竖条：实时数据表明它占用 15px，但 `scrollHeight === clientHeight`，没有可执行功能；恢复只会带回布局回归。
- 真正的原生状态指示位于尾部 grid 的直接状态层；诊断可识别它，但 CSS 不得根据诊断结果重排或隐藏它。
- `--diagnose` 字段是用户可见兼容面；只新增字段，不删除现有 `row/title/directChildren`，并同步 README。
- 在线 CDP 探针必须在同一动作内恢复临时折叠和样式状态，不把诊断状态留给用户。
