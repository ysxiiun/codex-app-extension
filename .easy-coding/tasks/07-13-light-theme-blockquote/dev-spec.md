### 修订摘要
- **用户修订 1（核心目标澄清）**：真实目标是"引用块内的普通正文采用主题原生主要字体颜色渲染"。影响：**删除** codex 原方案的浅色琥珀金 `#8A6500` / 玫红 `#B4235A` 配色改造、标题/加粗/行内代码浅色层，以及 `resolveThemeVariant` 主题识别纯函数与 `data-codex-app-extension-theme-variant` 属性；改为把引用正文默认色改为 CSS `inherit`（深/浅色自动跟随原生正文色，无需主题识别）。
- **用户修订 2（范围锁定）**：确认范围 = 正文颜色 + 嵌套灰块。影响：**保留**嵌套 `blockquote blockquote` 视觉扁平化；改动文件由原 4 个（含 `strong-text-color-preview.html`）调整为 `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`data/author-config.json`；**移出**预览 HTML（浅色配色改造已取消，预览无需扩展）。
- **用户修订 3（验证前提更新）**：老大指出 ChatGPT 现已开放 CDP 端口。实测确认 `127.0.0.1:9229` 为有效 CDP 端点（`/json/version` 返回 Chrome/150，`/json/list` 含 2 个 `Codex` 页面 target）。影响：**撤销**“当前无 CDP 端口、只能静态/生成验证”的限制；VERIFICATION 在 `./verify.sh` 通过后追加 `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` 在线诊断与应用内视觉验收。**代码改动范围不变**。
- **编码**：无编码变更，各文件保持原编码。

## 技术方案：修复状态引用块正文颜色与嵌套引用显示

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：让 Markdown 主题增强的引用块正文使用当前主题的原生主要字体颜色（而非写死的半透明白色），修复浅色主题下引用正文对比不足、几乎看不清的问题；同时消除嵌套引用重复叠加背景/边框/间距形成的二层灰块。
- **输入**：用户浅色主题截图与口述目标（"引用块内普通文字用主题主要字体颜色"）；现有 `themeEnhancementColors` 配置与生成 CSS。
- **输出**：改代码。把引用正文默认色改为 `inherit`（保留可配置性），新增嵌套引用视觉扁平化规则，并补齐生成 CSS 回归断言、README 与作者推荐配置同步。
- **边界**：不做浅色专用琥珀金/玫红配色改造；不引入主题识别纯函数或主题变体属性；不改标题/加粗/行内代码配色；不改宽屏、输入、侧栏增强；不修改应用包体与用户数据；不改深色既有视觉。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：主题增强 CSS 由 `inject-wide-layout.mjs` 的 `buildCss` 生成并注入 `main.main-surface`；默认色板为 `DEFAULT_THEME_ENHANCEMENT_COLORS`；零依赖验证在 `verify.sh`；公开契约在 `README.md` 与 `data/author-config.json`。
- **当前实现方式**：`DEFAULT_THEME_ENHANCEMENT_COLORS.blockquoteText` 固定为 `rgba(252, 252, 252, 0.78)`（`inject-wide-layout.mjs:45`），经变量 `--codex-app-extension-theme-blockquote-text`（`inject-wide-layout.mjs:3113`）在 `:where(blockquote)` 规则（`inject-wide-layout.mjs:3171-3178`）以 `!important` 应用到所有层级引用块的 `color/background/border-left/border-radius/margin/padding`。
- **现有问题 / 缺口**：该半透明白色在浅色背景对比极低（约 `1.59:1`），引用正文几乎不可读；`:where(blockquote)` 不区分层级，嵌套 `blockquote` 再次获得背景、左边框和间距，形成二层灰块；`verify.sh` 当前只断言 surface guard 与未作用域选择器（`verify.sh:102-108`），没有任何引用块回归断言。
- **证据**：`inject-wide-layout.mjs:40-46`（默认色板与白色 blockquoteText）、`inject-wide-layout.mjs:3112-3114`（变量输出）、`inject-wide-layout.mjs:3171-3178`（全层级引用块规则）、`inject-wide-layout.mjs:741-745`（`assertCssValue` 仅禁止 `;{}<>` 与空值，允许 `inherit`）、`verify.sh:97-109`（生成 CSS 仅校验 surface）、`README.md:148,169,192`（默认值/字段说明）、`data/author-config.json:25`（作者配置同样写死白色）。

### 冲突摘要
- 需求 vs RULES：无冲突。保持 UTF-8/US-ASCII 编码，走既有配置/注入链，默认值变化同步 README，不新增依赖或 schema；`assertCssValue` 允许 `inherit`。
- 需求 vs ABSTRACT：无冲突。沿用单一 CDP/CSS 注入链，不新增平行主题实现。
- 需求 vs 现有代码：复用现有 blockquote 变量与 CSS 框架，仅改默认值并新增嵌套复位规则。
- Dev-Spec vs 现有代码：无冲突。保留六字段 `themeEnhancementColors` 结构与可配置性，不做配置 schema 迁移。

### 影响面分析
- **涉及模块**：核心注入、零依赖验证、文档、作者推荐配置。
- **核心类 / 页面 / 接口**：`DEFAULT_THEME_ENHANCEMENT_COLORS`、`buildCss`、主会话 Markdown `blockquote`。
- **数据库变更**：无。
- **接口变更**：无公开字段增删；`blockquoteText` 默认值由白色改为 `inherit`（字段语义不变，仍可被用户覆盖）。
- **关联历史任务**：`SM-20260708-002`、`SM-20260708-003`（引用/浮层与侧栏布局）；已关闭任务 `07-10-adjust-theme-reference-color`（深色紫色改造按用户要求回滚，本次不动深色）。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持 UTF-8，依据：RULES.md 与 `file -I` | 默认 `blockquoteText` 改为 `inherit`（:45）；在 :3178 后新增 `blockquote blockquote` 复位规则（背景/左边框/圆角/外边距/内边距归零） |
| `verify.sh` | 修改 | 保持 US-ASCII，依据：RULES.md 与 `file -I` | 新增生成 CSS 回归断言：引用文本变量解析为 `inherit`；嵌套 `blockquote blockquote` 复位背景/边框/圆角/间距 |
| `README.md` | 修改 | 保持 UTF-8，依据：RULES.md 与 `file -I` | 同步 `blockquoteText` 默认值为 `inherit`，补充"引用正文默认继承主题正文色"说明（:148、:169、:192） |
| `data/author-config.json` | 修改 | 保持原编码（预计 US-ASCII），实施时 `file -I` 核对 | 作者推荐配置 `blockquoteText` 同步为 `inherit`（:25），与新默认保持一致 |

### 修改方案
- **总体改法**：把引用正文默认色从写死白色改为 `inherit`（深/浅色自动跟随原生正文色），并对嵌套引用做视觉扁平化以消除二层灰块；全程不引入主题识别。
- **后端改动**：不涉及。
- **前端改动**：
  1. `inject-wide-layout.mjs:45` 将 `DEFAULT_THEME_ENHANCEMENT_COLORS.blockquoteText` 由 `"rgba(252, 252, 252, 0.78)"` 改为 `"inherit"`；变量输出（:3113）与消费（:3172）链不变，故 `blockquote` 的 `color` 解析为 `inherit`。
  2. 在 `inject-wide-layout.mjs:3178` 后新增受 `data-codex-app-extension-surface` + `data-codex-app-extension-theme-enhancement` 约束的 `... main.main-surface :where(blockquote) blockquote` 规则，将 `background: transparent`、`border-left: 0`、`border-radius: 0`、`margin-inline: 0`、`padding: 0` 全部 `!important` 复位；不改 `color`（继续 `inherit`）。顶层引用块保留现有背景与左边框。
- **兼容处理**：保留 `blockquoteText` 字段与可配置性（用户仍可覆盖为固定色），不静默删除；深色主题下 `inherit` 即原生浅色文字，视觉不回归；`inlineCode*`、`blockquoteBorder`、`blockquoteBackground` 配置不变；同步 `README.md` 默认值与 `data/author-config.json`。
- **风险点**：嵌套复位规则的 specificity 必须不低于基础 `:where(blockquote)` 规则才能压过其 `!important`——用 `:where(blockquote) blockquote`（尾部追加元素选择器）保证更高 specificity；`inherit` 依赖引用块祖先文字色为主题原生色，需确认祖先未被扩展改写正文色（当前仅 `strong`/`code` 有独立色，正文未改）。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U1 | 引用正文改 `inherit` + 嵌套引用扁平化 + 回归断言与文档/推荐配置同步 | frontend | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`data/author-config.json` | — |

**执行策略**：single
- 单一实施单元：默认色板、CSS 复位规则、生成 CSS 回归断言、README 与作者推荐配置必须同步改动，避免配置/样式/文档短暂不一致，派发 1 个子代理执行。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 默认色板下生成 CSS 中引用文本变量解析为 `inherit`（不再是白色） | 必测 | U1 | 生成 CSS 精确断言 | `./verify.sh` |
| 生成 CSS 含 `blockquote blockquote` 复位规则：背景透明、左边框 0、圆角 0、外边距 0、内边距 0 | 必测 | U1 | 生成 CSS 精确断言 | `./verify.sh` |
| installer/diagnose 源可编译，且 `themeEnhancementColors` 反映 `blockquoteText=inherit` | 应测 | U1 | 生成源编译断言 | `./verify.sh` |
| surface guard、未作用域选择器、target/表面签名与 `git diff --check` 保持通过 | 应测 | U1 | 项目统一验证 | `./verify.sh` |

- **人工验收**：浅色主题下引用正文为原生深色、清晰可读，引用内部无灰色二层块；深色主题引用与整体视觉无回归；浅/深切换后无需重启注入脚本。
- **在线验收能力**：ChatGPT 已开放回环 CDP 端口 `9229`（`/json/version` 返回 Chrome/150，`/json/list` 含 2 个 `Codex` 页面 target），实现后可直接连接做实时 DOM/computed-style 对比与免重启重注入验收；`./verify.sh` 通过后追加 `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` 在线诊断，仅主观“清晰可读”视觉判断需人工在应用内确认。

### 背景数据应用
- `.easy-coding/RULES.md`：要求走既有配置/注入链、保持编码、默认值与字段变化同步 README、提交前跑 `./verify.sh`——本方案据此改默认值而非新增配置，并同步 README 与作者推荐配置。
- `.easy-coding/ABSTRACT.md`：将 `inject-wide-layout.mjs`、`verify.sh`、`README.md` 分别定义为"核心注入""验证""文档与预览"模块，并要求配置经 JSON 可序列化值跨越 CDP 边界；`blockquoteText=inherit` 沿该链生效并由 `--diagnose` 暴露。
- `.easy-coding/memory/long/TECHNICAL.md`：「配置化增强链路」要求能力可诊断、可回退，以 `./verify.sh` 与条件式 `inject-current.sh --diagnose` 为验证链。

### 前端实现映射

| 视觉目标 | 配置 / 来源 | CSS 消费位置 | 目标结果 |
|----------|------------|--------------|----------|
| 引用块正文颜色 | 默认 `blockquoteText=inherit`（仍可配置） | `:where(blockquote)` 的 `color` | 深/浅色均继承主题原生主要字体色，不再写死白色 |
| 嵌套引用二层块 | 主题增强 scope | 新增 `:where(blockquote) blockquote` 复位 | 去掉重复背景/左边框/圆角/间距，仅保留文本层级，消除灰块 |
| 顶层引用块背景/边框 | 现有 `blockquoteBackground` / `blockquoteBorder` | `:where(blockquote)` 的 `background` / `border-left` | 维持现状，不改动 |

### 风险与注意事项
- `inherit` 依赖引用块祖先文字色为主题原生色；若未来应用改写引用容器正文色，需重新评估该继承结果。
- 嵌套复位仅作用于已启用主题增强的主会话引用树（受 surface + theme-enhancement 属性约束），不影响其他组件或普通页面。
- 仓库存在 harness 升级产生的未提交文件，本任务不清理、不覆盖这些既有改动。
