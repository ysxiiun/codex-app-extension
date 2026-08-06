## 技术方案：修复 ChatGPT 升级后 fullscreenHeaderOffset 失效与顶部重叠

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：恢复 ChatGPT 升级后 `fullscreenHeaderOffset` 对主内容区的顶部标题避让，消除全屏窗口中固定 header 与 Git Diff、Plan 或对话内容的重叠。
- **输入**：用户反馈 `fullscreenHeaderOffset` 再次失效；当前调试端口 `9229` 已开放，本地最终配置为 `46px`。
- **输出**：改代码；扩展生产 CSS 的顶部避让目标到新版稳定 app-shell layout root，补齐生成 CSS 回归、文档与架构摘要，并在当前真实窗口重注入后完成几何验证。
- **边界**：不修改 ChatGPT 应用包体、账号或会话数据；不改变配置字段、默认值、CLI、全屏识别、宽屏布局、Markdown 主题或右侧 rail 识别；不把偏移叠加到 `.thread-scroll-container` 的原生顶部 inset；不覆盖当前工作树已有改动。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`inject-wide-layout.mjs` 的 `buildCss` 顶部避让规则和 `buildDiagnoseSource`，`verify.sh` 的生成 CSS 合同，`README.md` 配置说明，`.easy-coding/ABSTRACT.md` 核心注入与验证摘要。
- **当前实现方式**：配置链正确解析 `fullscreenHeaderOffset=46px` 并把变量写到 body、旧 main surface、`.app-shell-main-content-viewport` 和 `[data-app-shell-main-content-layout]`；但真正设置 `padding-top` 的 CSS 仍只匹配 `main.main-surface/.main-surface`。
- **现有问题 / 缺口**：当前 ChatGPT `26.727.51351` 已无 `main.main-surface/.main-surface`，新版主内容根是 `[data-app-shell-main-content-layout]`。因此变量存在、全屏属性为 `true`，但 layout 的 computed `padding-top` 仍为 `0px`，固定 header 覆盖其下方内容；现有 `verify.sh` 也没有验证顶部避让 selector。
- **证据**：`inject-wide-layout.mjs:3448-3463` 已向新版 layout root 写入变量，`inject-wide-layout.mjs:3466-3469` 的 padding 规则仍只有旧 main surface。在线诊断：`detectedFullscreen=true`、`fullscreenHeaderOffset=46px`、`mainSurface=0`、`mainViewport=0`、`layoutRoot=1`；固定 `header` 为 `top=0/bottom=46/position=fixed/z-index=30`，layout/frame 为 `top=0/paddingTop=0`。同一 JavaScript task 内临时应用 `border-box + 46px padding` 后，frame/thread `top` 从 `0` 变为 `46`、右侧 rail `top` 从 `58` 变为 `104`、composer 保持 `top=980/bottom=1024`，撤销后全部恢复，证明新版 layout root 是正确避让层。

### 冲突摘要
- 需求 vs RULES：无冲突；沿用现有 CDP、surface guard、零依赖验证和可撤销运行时注入，不引入依赖。
- 需求 vs ABSTRACT：无冲突；属于“模块：核心注入”“模块：配置”“模块：验证”的升级兼容修复。
- 需求 vs 现有代码：有冲突；现有 padding 规则把已消失的 main surface 固化为唯一目标。
- Dev-Spec vs 现有代码：无额外冲突；方案保留旧目标，并把已存在于 surface probe 和变量写入链的新版 layout root纳入兼容集合。

### 影响面分析
- **涉及模块**：核心注入、生成 CSS 验证、配置兼容说明、架构知识摘要。
- **核心类 / 页面 / 接口**：`buildCss(options)`、`fullscreenHeaderOffset`、`main.main-surface/.main-surface`、`.app-shell-main-content-viewport`、`[data-app-shell-main-content-layout]`、`app://-/index.html`。
- **数据库变更**：无。
- **接口变更**：无；JSON 字段、默认值、CLI 参数、环境变量和诊断 JSON 结构不变。
- **关联历史任务**：`SM-20260710-004`（ChatGPT Codex 兼容适配）；上一任务 `08-03-restore-theme-enhancement-after-chatgpt-upgrade` 同样确认新版移除了 `.main-surface`，但改动的是 Markdown 内容根，不与本任务顶部布局根混用。

### 改动范围
> 只列真实项目源码/配置文件以及规则要求随兼容行为同步的项目知识摘要；本任务 dev-spec、execution、test-strategy、记忆或报告不计入产品改动范围。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `inject-wide-layout.mjs` | 修改 | 保持原编码 UTF-8 | 提取顶部避让兼容目标常量，将 padding 规则扩展到旧 main surface、旧 app-shell viewport 和新版 data layout root |
| `verify.sh` | 修改 | 保持原编码 US-ASCII | 断言顶部避让目标精确集合、surface guard、`border-box` 和变量 padding，禁止回退为 legacy-only selector |
| `README.md` | 修改 | 保持原编码 UTF-8 | 补充 `fullscreenHeaderOffset` 对新旧主内容布局根的兼容语义 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8 | 同步核心注入与验证模块的顶部避让合同 |

### 修改方案
- **总体改法**：将顶部避让目标统一为受 surface guard 约束的新旧兼容集合 `:where(main.main-surface, .main-surface, .app-shell-main-content-viewport, [data-app-shell-main-content-layout])`，继续以 `box-sizing:border-box` 应用 `fullscreenHeaderOffset`。
- **后端改动**：不涉及。
- **前端改动**：仅扩展运行时 CSS 的 padding 目标；不改变 header、本地配置值、原生 thread top inset、内容宽度或横向偏移算法。
- **兼容处理**：保留旧 main surface 和旧 app-shell viewport，同时新增当前 surface probe 已使用的 `[data-app-shell-main-content-layout]`；若多个兼容标识落在同一元素，selector list 仍只产生一条 padding 声明。
- **风险点**：不能直接给 `.thread-scroll-container` 加 46px，否则会叠加其原生 `padding-top:78px`；layout root 必须保持 `border-box`，避免总体高度增长和底部溢出。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 恢复新版 ChatGPT 主内容布局的顶部标题避让 | frontend | `inject-wide-layout.mjs`、`verify.sh`、`README.md`、`.easy-coding/ABSTRACT.md` | — | 当前 layout 有效 padding 为 46px，frame 从 header 底部开始，旧根继续兼容 | 生成 CSS 精确 selector 合同、离线基线、live diagnose、重注入后几何探针 | 配置/CLI/诊断结构不变；顶部避让只作用于主布局根，不叠加 thread inset |

**执行策略**：single
- 单一批次：U1 由一个实现单元原子修改生产 CSS、回归断言和文档，避免 selector 与测试合同漂移。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 注入器与验证脚本语法 | 必测 | U1 | 静态语法 | `node --check inject-wide-layout.mjs`、`bash -n verify.sh` |
| 顶部避让 selector 精确覆盖新旧根并保留 surface guard | 必测 | U1 | 生成 CSS 回归 | `./verify.sh` |
| 当前 target/surface 在线诊断 | 必测 | U1 | Live CDP | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |
| 当前 fixed header 与主内容几何不重叠 | 必测 | U1 | 重注入 + 只读探针 | `./inject-current.sh` 后读取 header/layout/frame/thread/rail/composer 的 rect 与 computed style |
| 补丁范围与编码 | 必测 | U1 | Diff/文件审计 | `git diff --check`、`file -I`、限定文件 diff |

- **人工验收**：全屏窗口顶部标题栏不再覆盖 Git Diff、Plan 或对话内容；输入框与右侧面板布局正常。
- **无法验证项**：最终审美观感由用户肉眼确认；自动几何探针覆盖是否重叠及关键布局不变量。

### Workflow Mode
- **项目配置**：adaptive。
- **Session 覆盖**：无。
- **机械最低模式**：standard（状态 API 原因：`multi-file-impact`）。
- **推荐并选择**：standard。
- **选择原因**：生产 CSS、生成 CSS 合同、README 和架构摘要构成普通多文件兼容修复；当前 CDP 已把根因限定为顶部避让 selector 丢失新版 layout root，没有 schema、安全、数据或跨仓风险。
- **状态内执行差异**：IMPLEMENT 以单一单元完成 CSS、回归与文档；REVIEW 独立核查根集合、双重 padding 风险、旧版兼容和测试有效性；VERIFICATION 执行受影响全基线及当前页面几何证据；MEMORY 生成 schema-v2 兼容检查点并按状态指令决定是否长期沉淀。

### 风险与注意事项
- 当前工作树已有上一主题任务修改、`.easy-coding/config.yaml`、`.easy-coding/install-manifest.json` 和 `data/author-config.json` 改动，必须保留且不纳入本任务产品改动范围。
- 在线验证只在当前 `app://-/index.html` Codex surface 上重注入和读取布局，不发送消息、不修改应用包体或持久用户数据。
