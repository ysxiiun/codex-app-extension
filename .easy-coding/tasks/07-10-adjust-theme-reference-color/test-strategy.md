# 测试策略：统一增强主题与作者推荐的引用紫色

## 可测试性分类

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| `DEFAULT_THEME_ENHANCEMENT_COLORS` | 配置生成输入 | [must-test] | Bug 修复的默认值来源，可直接断言完整对象 |
| `data/author-config.json.themeEnhancementColors` | JSON 配置 | [must-test] | 当前配置软链接与作者推荐的实际来源，必须与目标色板一致 |
| `buildCss` 生成的主题 CSS 变量 | 纯字符串生成 | [must-test] | 输入输出确定，可断言目标色值与 surface 作用域 |
| `README.md` 配置示例与说明 | 文档 | [no-test] | 通过人工 diff 和搜索核对，不具备运行行为 |
| `strong-text-color-preview.html` | 纯样式预览 | [no-test] | 自动测试只能检查文本，真实观感需要人工查看 |

## 测试点

1. U1：断言内置默认色板完整等于 `#A879D1`、`rgba(85, 37, 131, 0.30)`、`rgba(139, 101, 176, 0.58)`、`#74509A`、既有引用正文色、`rgba(57, 28, 88, 0.28)`；命令：`./verify.sh`。
2. U1：读取并解析 `data/author-config.json`，断言作者 `themeEnhancementColors` 与内置默认色板一致；命令：`./verify.sh`。
3. U1：生成 CSS，断言行内代码/引用变量含逐字段设计的分层主题紫值，且现有 `html[data-codex-app-extension-surface="true"]` 作用域保护继续通过；命令：`./verify.sh`。
4. U1：继续执行 Node/Shell 语法、ChatGPT Codex 锚点和 `git diff --check` 的项目基线；命令：`./verify.sh`。

## 不测试项及原因

- `README.md`：只包含示例值和文字说明，使用变更审查确认与代码一致。
- `strong-text-color-preview.html`：没有浏览器测试基础设施，保持零依赖约束；使用人工打开预览确认视觉层级。

## 人工验收

- 重新注入后，对照用户截图确认正文行内 `ec-workflow` 已由首版浅紫转为更深、更稳的 `#A879D1` 皇家紫，并与现有金色标题/加粗形成克制的紫金关系。
- 检查行内代码具有独立低明度紫边框，边框稳定但不发亮；Markdown 引用块使用更沉稳的 `#74509A` 结构边框和暗紫背景。
- 检查代码块、链接、Markdown 标题金色和加粗金色未被改变。

## 无法验证项

- 若当前 ChatGPT 进程没有回环 CDP 端口，无法在本轮自动重注入并读取 computed style；此时以 `./verify.sh` 的静态/生成代码结果为新鲜证据，在线视觉由用户下次通过 `./launch.sh` 启动后验收。
