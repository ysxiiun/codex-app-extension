### 修订摘要
- 用户补充“右侧栏打开后稳定复现”，使验收环境从宽窗口猜测收敛为 `data-app-shell-main-content-layout` 宽约 `696.81px` 的真实分栏状态。
- 用户补充“同样有问题的还有其他组件，比如文件打开方式”，因此修复对象从模型二级菜单扩展为所有真实 `fixed/absolute/sticky wrapper > role=menu/listbox` 通用下拉浮层；交付仍为一次通用分类修复，不逐组件打补丁。
- 2026-07-24 实时 CDP 已复现文件打开方式菜单导致 composer 从 `564px` 缩到 `303px`，推翻此前“当前窗口无法复现”的判断，并确认根因不是原生菜单动画。

## 技术方案：修复通用菜单定位 wrapper 被误判为右侧 rail 导致的 composer 宽度闪烁

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：修复上一版瞬态浮层分类漏掉“定位 wrapper 的后代是 `role="menu"`”的缺陷，消除右侧栏打开时模型二级选择框、文件打开方式及同结构下拉菜单触发的底部 composer 宽度闪烁。
- **输入**：用户对上一版交付的失败验收、右侧栏稳定复现条件、文件打开方式截图，以及 2026-07-24 主工作区实时 CDP 逐帧宽度证据。
- **输出**：交付形态为改代码；围绕统一 menu/listbox selector 对菜单自身、菜单内部节点和包裹菜单的定位 wrapper 做对称语义排除，补齐真实 DOM 行为回归、诊断候选和 README 契约。
- **边界**：不修改 ChatGPT/Codex 应用包体、账号或会话数据；不改原生菜单的尺寸、位置、动画和交互；不针对模型或文件卡片写组件专属选择器；不撤销 composer 顶部任务/Git 组件对齐；不改变真实 `thread-floating-content` 右侧 rail 的避让能力；不新增配置项、依赖或构建系统。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`inject-wide-layout.mjs` 的 `isTransientInteractiveOverlay()` 负责瞬态菜单语义识别（`inject-wide-layout.mjs:1474`），`findRightFloatingRail()` 在几何测量前调用该判定（`inject-wide-layout.mjs:1765`、`inject-wide-layout.mjs:1774`）；`buildDiagnoseSource()` 生成 `transientInteractiveOverlayCandidates`（`inject-wide-layout.mjs:1113`）；`verify.sh` 为该判定提供生成源码回归（`verify.sh:2030`）。
- **当前实现方式**：判定函数只覆盖“元素自身是 menu/listbox”“元素位于 menu 内部”和“元素后代含 listbox”三条路径（`inject-wide-layout.mjs:1474-1480`）；未命中的定位 wrapper 会继续进入尺寸、位置、右侧锚定和最靠左候选筛选（`inject-wide-layout.mjs:1781-1809`），一旦入选就以 wrapper 的左边界缩小可用宽度（`inject-wide-layout.mjs:1962-1990`）。
- **现有问题 / 缺口**：模型二级菜单和文件打开方式菜单都采用 `position:fixed wrapper > role="menu"`；wrapper 自身无 role、不位于 menu 内部、后代也没有 listbox，只有后代 menu，因此当前判定返回 false。诊断注释和 README 声称候选包含定位 wrapper，但诊断实际只枚举 role 元素（`inject-wide-layout.mjs:1113-1120`、`README.md:392`）；回归也只检查“后代 listbox”，没有真实“后代 menu”结构（`verify.sh:2034-2044`）。
- **实时复现证据**：右侧栏打开后，主内容 scope 为 `left=268.96/right=965.77/width=696.81`。实际文件打开方式菜单的 fixed wrapper 为 `left=704/right=926/width=222/height=236`，满足 `startsInsideReference`、`rightAnchored`、`narrowEnough` 和最小高度条件（对应 `inject-wide-layout.mjs:1770-1805`）；菜单打开约 `100ms` 后布局刷新 `runCount 1802 → 1803`，composer 从 `left=335.37/right=899.37/width=564` 变为 `left=335.87/right=638.87/width=303`。菜单本体和 wrapper 的 `animationDuration`、`transitionDuration` 均为 `0s`，因此闪烁来自扩展宽度回写，不是原生菜单动画。
- **模型结构证据**：模型一级和二级菜单的 fixed wrapper 分别约为 `226×136` 与 `282×220`，两者同样只有 `descendantMenu=true`；二级菜单高度超过当前 rail 最小高度并位于分栏 scope 右侧锚定区。模型触发器自身存在原生 `115px → 224px` 展开过渡，但它不改变上述“wrapper 被误判后 composer 整体缩窄”的根因，本次不覆盖原生交互动画。

### 冲突摘要
- 需求 vs RULES：无冲突；修复继续复用现有页面注入、surface guard、失败开放和 `./verify.sh` 验证链，不引入依赖。
- 需求 vs ABSTRACT：无冲突；`.easy-coding/ABSTRACT.md` 已声明 menu/listbox 瞬态浮层应整体排除，本次是让代码真正满足既有架构契约，不改变模块数据流。
- 需求 vs 现有代码：存在明确实现冲突；当前分类方向不对称，遗漏“定位 wrapper 包含 role=menu 后代”这一被模型、文件打开方式等组件共同使用的真实 DOM 结构。
- Dev-Spec vs 现有代码：无未决冲突；统一使用 `TRANSIENT_INTERACTIVE_OVERLAY_SELECTOR` 对自身、祖先和后代做对称检查，并让诊断与测试覆盖同一通用结构即可，无需按组件拆分方案。

### 影响面分析
- **涉及模块**：页面运行时浮层分类、right rail 几何候选、只读诊断、离线回归、用户文档。
- **核心类 / 页面 / 接口**：`buildInstallerSource()` 中的 `isTransientInteractiveOverlay()` / `findRightFloatingRail()`，`buildDiagnoseSource()` 中的 `transientInteractiveOverlayCandidates`，`verify.sh` 的 overlay regression。
- **数据库变更**：无。
- **接口变更**：无新增字段；既有 `transientInteractiveOverlayCandidates` 会补齐实际定位 wrapper，数组内容与 README 宣称的语义一致。
- **关联历史任务**：`SM-019f8ec0-b3d2-7bb3-8327-54be49bbebf7`（上一版模型菜单与顶部组件对齐修复，用户验收失败）；`SM-20260708-002`（原生 Git 浮层兼容）；`SM-20260708-003`（左侧栏布局修复）。

### 背景数据应用
- `.easy-coding/SOUL.md`、`.easy-coding/RULES.md` 要求运行时低侵入、可诊断、失败开放并以当前 DOM / CDP 证据优先，因此本次不再沿用上一版未经真实 wrapper 验证的推断。
- `.easy-coding/ABSTRACT.md` 和长期技术记忆“运行时注入架构”“配置化增强链路”“输入与布局增强边界”要求复用现有注入与诊断框架；本次只修正分类闭包和诊断内容，不新建并行实现链。
- 上一版短期记忆记录的“menu/listbox 已整体排除”与当前代码、实时 `564px → 303px` 复现及用户验收冲突，当前运行证据优先；本任务必须在右侧栏状态下同时验证模型二级菜单和文件打开方式菜单后才能宣称解决。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8；依据：`file -I inject-wide-layout.mjs` | 对称识别 menu/listbox 自身、内部节点和包裹它们的定位 wrapper；诊断同时列出 role 元素与最近的可见定位 wrapper。 |
| `verify.sh` | 修改 | 保持原编码 US-ASCII；依据：`file -I verify.sh` | 增加真实 `fixed wrapper > role=menu` 行为回归，覆盖模型/文件菜单的共同结构，并保留 listbox、内部节点与真实 rail 负例。 |
| `README.md` | 修改 | 保持原编码 UTF-8；依据：`file -I README.md` | 明确定位 wrapper 通过其 menu/listbox 后代识别，诊断字段会同时展示语义节点与外层定位节点，并列出模型/文件菜单示例。 |

### 修改方案
- **总体改法**：把瞬态交互浮层判定改为围绕同一个 `TRANSIENT_INTERACTIVE_OVERLAY_SELECTOR` 的对称闭包：元素匹配 selector、元素位于 selector 内部、元素包含 selector 后代，任一成立即从 rail 候选排除。
- **后端改动**：不涉及。
- **前端改动**：`isTransientInteractiveOverlay()` 的 `closest()` 与 `querySelector()` 都使用完整 menu/listbox selector，修复 fixed wrapper 包含 `role="menu"` 时的漏判；诊断从每个可见 role 节点出发，合并最近的可见 fixed/absolute/sticky 定位祖先并去重，使在线输出可同时证明菜单语义节点和真正参与几何扫描的 wrapper。
- **兼容处理**：真正的右侧 rail 没有 menu/listbox 自身、祖先或后代，继续进入原几何逻辑；composer 顶部附着组件仍走 `isComposerAttachedOverlay()` 和独立对齐变量；模型菜单 DOM、样式和事件不被修改。
- **风险点**：若某个持久右侧面板的最外层定位容器内部长期挂载可见 `role="menu"`，对称后代检查会把该定位容器视为瞬态菜单；实现保持逐元素判断，不向更高层布局 shell 扩散，并用普通持久 rail 负例与诊断输出约束。

### 前端实现映射

| 交互 / 页面结构 | 当前行为 | 目标行为 | 验收映射 |
|----------------|---------|---------|---------|
| `position:fixed wrapper > 文件打开方式 role="menu"` | 约 100ms 后被选为 rail，composer `564px → 303px` | 通过后代 menu 提前排除，布局刷新前后宽度相同 | 打开 `VS Code / Finder / Terminal...` 菜单 5 秒，composer 左右边界稳定 |
| `position:fixed wrapper > 二级模型 role="menu"` | 贴近分栏 scope 右边时成为 rail，composer 整体缩窄 | 无论几何是否贴右都按菜单语义提前排除 | 一级菜单进入“模型”二级菜单并保持 5 秒，composer 左右边界稳定 |
| menu/listbox 自身与内部节点 | menu 内部节点已覆盖，listbox 内部节点未完整覆盖 | `closest(完整 selector)` 对两类角色一致生效 | 行为回归覆盖 menu/listbox 自身、内部节点和外层 wrapper |
| 其他通用 `fixed/absolute/sticky wrapper > menu/listbox` | 取决于角色类型，可能误进几何候选 | 统一按语义闭包排除，不写组件名特判 | 诊断同时列出 role 节点与最近定位 wrapper |
| `thread-floating-content` 持久右侧 rail | 继续参与宽度避让 | 保持原逻辑 | 在线诊断仍选择真实 rail，内容不与其重叠 |

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U1 | 修复通用瞬态菜单对称分类，补齐文件/模型共用 wrapper 的诊断、行为回归与文档 | frontend/test/docs | `inject-wide-layout.mjs`、`verify.sh`、`README.md` | — |

**执行策略**：single
- 单一实施单元：分类函数、诊断、回归与 README 必须使用同一 menu/listbox 语义，放在一个单元中可避免再次出现实现与测试脱节。
（single：单一实施单元，派发 1 个子代理执行）

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 真实 `position:fixed wrapper > role=menu` 被判为瞬态浮层；该用例在上一版实现上必须失败 | 必测 | U1 | 从生成 installer 提取分类函数，用最小 HTMLElement stub 执行行为回归 | `./verify.sh` |
| menu/listbox 自身、内部节点、外层定位 wrapper 均命中，普通持久 rail 不命中 | 必测 | U1 | 对称 selector 闭包正负例 | `./verify.sh` |
| rail 扫描在读取候选几何和 `candidates.push()` 前调用分类；composer 附着组件和既有 surface guard 不回归 | 必测 | U1 | 生成源码契约断言 | `./verify.sh` |
| `transientInteractiveOverlayCandidates` 同时包含可见 role 节点及最近定位 wrapper，diagnose/installer 源可编译 | 必测 | U1 | 诊断生成源码回归 | `./verify.sh` |
| 右侧栏状态下文件打开方式菜单开启前后 composer 保持 `564px`；模型二级菜单开启前后左右边界稳定 | 必测 | U1 | 重注入后本地 CDP 逐帧采样 + 在线诊断 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh`，并执行任务内 CDP 几何验收 |

- **人工验收**：保持右侧栏打开，依次打开文件“打开方式”和模型一级菜单中的“模型”二级菜单，各保持至少 5 秒；确认底部 composer 左右边界不再往返、菜单位置稳定且原生选择功能正常；关闭菜单后宽度不跳变；顶部任务/Git 组件仍与 composer 同中心。
- **无法验证项**：自动化可验证几何宽度、分类结果和在线注入状态；“肉眼完全无闪感”及连续操作手感仍需用户最终视觉验收。

### 风险与注意事项
- 回归必须包含“后代 role=menu”的真实失败结构，并明确映射文件打开方式和模型二级菜单，不能再用后代 listbox 代替。
- 诊断、实现和 README 必须共用“自身 / 祖先 / 后代完整 menu-listbox selector”语义，避免第三次出现文档声称已覆盖但代码漏判。
- 不用冻结 composer 宽度、延长 debounce 或关闭所有菜单动画掩盖问题；实时证据已证明菜单原生动画时长为 `0s`，应直接修复 rail 候选分类。
- 保留工作树中用户已有 `.qoder/settings.local.json` 改动，不纳入本任务；上一任务的未提交文件也只做增量修复，不回滚其顶部组件对齐实现。
