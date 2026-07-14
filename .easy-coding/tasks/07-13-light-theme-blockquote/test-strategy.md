# 测试策略：状态引用块正文颜色与嵌套引用修复

## 可测试性分类

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| `DEFAULT_THEME_ENHANCEMENT_COLORS.blockquoteText` 默认值改 `inherit` | config default | [must-test] | 经 `buildCss` 生成的引用文本变量可静态断言 |
| `buildCss` 的 `blockquote blockquote` 复位规则 | pure function | [must-test] | 相同 options 必须生成固定的嵌套复位选择器与属性 |
| 安装/诊断源编译与 `themeEnhancementColors` 透出 | runtime state | [should-test] | 生成 installer/diagnose 源可编译，色板字段可静态断言 |
| `README.md` 默认值与字段说明 | documentation | [no-test] | 无运行行为，按字段与实现人工校对 |
| `data/author-config.json` `blockquoteText` 同步 | config data | [no-test] | 合法 JSON 由人工与既有语法检查校对，非运行时行为 |

## 测试点

| 测试点 | 归属单元 | 验证命令 |
|---|---|---|
| 默认色板下生成 CSS 中引用文本变量解析为 `inherit`（不再是 `rgba(252, 252, 252, 0.78)`） | U1 | `./verify.sh` |
| 生成 CSS 含 `blockquote blockquote` 复位：`background` 透明、`border-left` 0、`border-radius` 0、`margin-inline` 0、`padding` 0 | U1 | `./verify.sh` |
| 顶层 `:where(blockquote)` 仍保留 `background`/`border-left`（未被误伤） | U1 | `./verify.sh` |
| installer/diagnose 源可编译，且 `themeEnhancementColors` 反映 `blockquoteText=inherit` | U1 | `./verify.sh` |
| surface guard、未作用域选择器、target/表面签名与 `git diff --check` 保持通过 | U1 | `./verify.sh` |

## 不自动测试项及原因

- `README.md`：文档内容不产生可执行行为，人工核对默认值、字段说明与实现一致性。
- `data/author-config.json`：为推荐配置数据，`blockquoteText=inherit` 由合法 JSON 校验与人工核对保证，不引入浏览器测试基础设施。

## 人工验收

- 浅色主题：引用块正文为原生深色、清晰可读；引用内部无灰色二层块；顶层引用块背景/左边框保持既有观感。
- 深色主题：引用正文（原生浅色）、行内代码与结构色无视觉回归。
- 主题切换：浅/深切换后无需重启增强脚本即生效（`inherit` 天然随主题）。

## 在线验证能力

- 已实测 `127.0.0.1:9229` 为有效 CDP 端点（`/json/version` 返回 Chrome/150，`/json/list` 含 2 个 `Codex` 页面 target）；实现后可连接做实时 DOM/computed-style 对比并免重启重注入。`./verify.sh` 通过后追加 `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` 在线诊断，仅主观“清晰可读”视觉判断由人工在应用内确认。
