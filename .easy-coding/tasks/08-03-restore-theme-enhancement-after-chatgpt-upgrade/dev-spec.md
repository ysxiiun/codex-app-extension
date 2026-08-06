## 技术方案：修复 ChatGPT 升级后 Markdown 主题增强失效

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：恢复 ChatGPT 升级后在 Codex 主工作区失效的 Markdown 标题、strong、行内代码和引用块主题增强，同时保持旧版 DOM 兼容。
- **输入**：用户反馈“最新的 ChatGPT 升级之后主题增强不生效”，当前 `/Applications/ChatGPT.app` 版本 `26.727.51351`（build `6119`），回环 CDP 端口 `9229` 已开放。
- **输出**：改代码；修复生产 CSS 的 Markdown 内容根作用域，补齐生成 CSS 回归、兼容说明和架构摘要，并在当前真实主工作区完成重注入与 computed-style 验证。
- **边界**：不修改 ChatGPT 应用包体、用户会话或账号数据；不改变配置 schema、色板、CLI、宽屏布局或输入增强；不覆盖工作树中已有的 Harness 升级和 `data/author-config.json` 用户改动；不为测试向当前会话发送消息。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`inject-wide-layout.mjs` 的 `buildCss` Markdown 增强规则、`verify.sh` 生成 CSS 回归、`README.md` 兼容说明和 `.easy-coding/ABSTRACT.md` 核心注入/验证摘要。
- **当前实现方式**：页面安装器已正确选中 `app://-/index.html`、通过 Codex surface 门禁、写入样式节点并把 heading/strong/theme 三个启用属性设为 `true`；但全部 Markdown 增强 CSS 都把 `main.main-surface` 写成唯一内容根。
- **现有问题 / 缺口**：ChatGPT `26.727.51351` 主工作区已经移除 `main.main-surface/.main-surface`，真实会话内容位于 `.thread-scroll-container`。因此配置与安装状态均显示已启用，CSS 却没有任何元素可匹配，形成静默失效。现有测试还把旧根写入正则，反而固化了过时选择器。
- **证据**：`inject-wide-layout.mjs:17-23` 已把 `.thread-scroll-container` 视为稳定 surface 锚点；`inject-wide-layout.mjs:3492-3534` 的六组 Markdown 增强规则仍只依赖 `main.main-surface`；`verify.sh:1952-1971` 只校验旧根。当前 CDP 取证：`mainSurfaceCount=0`、`threadScrollCount=1`、`injectedStyleExists=true`、三个增强属性均为 `true`，但真实 `strong` 和 `blockquote` 的 `matchedExtensionRules=[]`，引用块 computed style 为透明背景且无左边框。

### 冲突摘要
- 需求 vs RULES：无冲突；修复沿用现有 CDP/CSS 注入链、surface 门禁和零依赖验证，不新增依赖或配置。
- 需求 vs ABSTRACT：无冲突；属于“模块：核心注入”和“模块：验证”的升级兼容修复。
- 需求 vs 现有代码：有冲突；现有代码把已经消失的 `main.main-surface` 当作唯一 Markdown 根。
- Dev-Spec vs 现有代码：无额外冲突；方案保留旧根并增加当前稳定 `.thread-scroll-container`，不移除旧版兼容。

### 影响面分析
- **涉及模块**：核心注入、生成 CSS 验证、用户兼容文档、架构知识摘要。
- **核心类 / 页面 / 接口**：`buildCss(options)`、ChatGPT Codex 主 target `app://-/index.html`、`.thread-scroll-container`、`main.main-surface/.main-surface`。
- **数据库变更**：无。
- **接口变更**：无；配置 JSON、CLI、环境变量和诊断 JSON 字段不变。
- **关联历史任务**：`SM-20260710-004`（ChatGPT Codex 兼容适配）、`SM-20260713-005`（浅色主题引用块修复）。

### 改动范围
> 只列真实项目源码/配置文件以及仓库规则明确要求随兼容行为同步的项目知识摘要；不把本任务的 dev-spec、execution、test-strategy、记忆或报告计入产品改动范围。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8 | 将六组 Markdown 增强规则统一改为受 surface 门禁约束的兼容内容根 `:is(main.main-surface, .main-surface, .thread-scroll-container)` |
| `verify.sh` | 修改 | 保持原编码 US-ASCII | 断言所有主题相关选择器共享新旧兼容根，禁止回退为只依赖 `main.main-surface`，保留引用/代码块不变量 |
| `README.md` | 修改 | 保持原编码 UTF-8 | 记录新版主工作区以 `.thread-scroll-container` 作为 Markdown 兼容根及旧根保留策略 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8 | 同步核心注入和验证模块的 Markdown 兼容根契约 |

### 修改方案
- **总体改法**：把 `main.main-surface` 从唯一 Markdown 根升级为 `:is(main.main-surface, .main-surface, .thread-scroll-container)` 兼容根，并让 heading、strong、行内代码、代码块排除、顶层引用和嵌套引用六组规则统一复用该根。
- **后端改动**：不涉及。
- **前端改动**：修改运行时生成 CSS 的作用域；不改变颜色、字重、边框、背景、间距或开关语义。
- **兼容处理**：保留 `main.main-surface` 与 `.main-surface`，新增当前已由 surface probe 和布局 observer 使用的 `.thread-scroll-container`；根级 `data-codex-app-extension-surface="true"` 和各增强开关属性仍是硬门禁。
- **风险点**：`.thread-scroll-container` 比已消失的根更贴近当前会话滚动区；必须继续使用现有 Markdown-like 子选择器并验证代码块排除，避免把非 Markdown 控件误着色。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 恢复新版工作区 Markdown 增强作用域并完成回归/文档同步 | frontend | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md` | — | 当前主工作区真实 Markdown 元素重新命中增强规则；旧根与 surface guard 保持 | 生成 CSS 六组规则、离线基线、live diagnose、重注入后 computed style | 配置与诊断结构不变；统一兼容根字符串必须覆盖新旧三种根 |

**执行策略**：single
- 单一批次：U1 由一个实现单元原子修改生产选择器、回归断言和文档，避免 CSS/测试合同漂移。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 注入器与验证脚本语法 | 必测 | U1 | 静态语法 | `node --check inject-wide-layout.mjs && bash -n verify.sh` |
| 六组 Markdown 规则使用统一新旧兼容根且保留 surface guard | 必测 | U1 | 生成 CSS 回归 | `./verify.sh` |
| 当前 target/surface 在线诊断 | 必测 | U1 | Live CDP | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |
| 真实引用块与 strong 命中扩展规则、computed style 等于配置 | 必测 | U1 | 重注入 + 只读探针 | `./inject-current.sh` 后执行 CDP 样本探针 |
| 补丁范围与空白检查 | 必测 | U1 | Diff 审计 | `git diff --check` 与限定文件 diff |

- **人工验收**：当前深色主题下引用块恢复粉色左边框/淡色背景，strong 恢复黄色与 800 字重；若当前页面存在标题/行内代码/代码块，确认标题与行内代码恢复且代码块不被误着色。
- **无法验证项**：纯审美判断需用户肉眼确认；当前页面若没有现成标题或行内代码样本，不写入测试消息，对应行为由生成 CSS 回归覆盖。

### Workflow Mode
- **项目配置**：adaptive。
- **Session 覆盖**：无。
- **机械最低模式**：standard（状态 API 原因：`multi-file-impact`）。
- **推荐并选择**：standard。
- **选择原因**：生产 CSS、零依赖验证、README 和架构摘要构成普通多文件兼容修复；真实 CDP 已将根因与影响面限定在 Markdown 根选择器，无配置/schema、安全、数据或跨仓契约风险。
- **状态内执行差异**：IMPLEMENT 以单一单元完成代码、回归与文档；REVIEW 独立核查选择器正确性、旧版兼容、surface 约束和既有改动隔离；VERIFICATION 执行受影响全基线加当前 CDP live/computed-style 证据；MEMORY 生成 schema-v2 短期兼容记忆并评估长期沉淀。

### 风险与注意事项
- 当前工作树已有 `.easy-coding/config.yaml`、`.easy-coding/install-manifest.json` 与 `data/author-config.json` 改动，必须保留且不纳入本任务实现指纹之外的修复范围。
- 重注入会更新当前页面中的扩展样式和事件处理器，但不写 ChatGPT 包体或会话数据；验证只读取现有 DOM，不发送测试消息。
