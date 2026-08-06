# 测试策略：ChatGPT 升级后 Markdown 主题增强作用域修复

## 可测试性分类

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| Markdown 增强根从单一 `main.main-surface` 扩展为兼容根集合 | generated CSS | [must-test] | `buildCss` 输出稳定，可断言新旧根、surface guard 与全部增强规则 |
| 标题、strong、行内代码、代码块排除、引用块与嵌套引用规则 | generated CSS | [must-test] | 六组选择器共享同一兼容根，任一遗漏都会造成局部增强失效 |
| 当前 ChatGPT 主工作区真实 DOM 命中 | live CDP | [must-test] | 用户已开放 9229；可重注入并读取真实元素的 matched rule / computed style |
| README 与架构摘要 | documentation | [no-test] | 通过实现对照与 diff 检查校对，不引入文档测试设施 |

## 回归基线

- App：`/Applications/ChatGPT.app`，当前版本 `26.727.51351`（build `6119`）。
- CDP：`127.0.0.1:9229`，主 target `app://-/index.html`。
- 修复前证据：surface 支持、样式节点存在、三个增强属性均为 `true`；但 `main.main-surface/.main-surface` 数量为 `0`、`.thread-scroll-container` 为 `1`，真实 `strong` 与 `blockquote` 的 `matchedExtensionRules=[]`。

## 自动测试点

| 测试点 | 级别 | 归属单元 | 验证命令 |
|---|---|---|---|
| 生产注入器与验证脚本语法正确 | 必测 | U1 | `node --check inject-wide-layout.mjs && bash -n verify.sh` |
| 生成 CSS 中 heading/strong/inline-code/pre-code/blockquote/nested-blockquote 全部使用兼容 Markdown 根 | 必测 | U1 | `./verify.sh` |
| CSS 仍受 `data-codex-app-extension-surface="true"` 门禁约束，无新增裸选择器 | 必测 | U1 | `./verify.sh` |
| 引用正文 `inherit`、代码块复位、顶层背景/边框和嵌套扁平化不回归 | 必测 | U1 | `./verify.sh` |
| 当前应用的 surface/target/输入协议在线诊断通过 | 必测 | U1 | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` |
| 重注入后真实 blockquote 与 strong 命中扩展规则，computed style 与配置一致 | 必测 | U1 | `./inject-current.sh` 后执行只读 CDP 样本探针 |
| 补丁无空白错误且未覆盖既有用户改动 | 必测 | U1 | `git diff --check` 与限定文件 diff 审计 |

## 人工验收

- 当前深色主题下，引用块重新出现粉色左边框和淡色背景，strong 恢复 `#F2C94C` / `800`，行内代码恢复结构色。
- 打开包含标题、代码块和嵌套引用的消息，确认标题着色、代码块未被当作行内代码、嵌套引用没有重复背景与边框。

## 无法完全自动验证项

- “视觉是否符合个人审美”仍需用户肉眼确认；颜色、边框、背景与字重本身通过 computed style 自动取证。
- 当前页面没有现成标题或行内代码样本时，对应真实 DOM 项仅由生成 CSS 回归覆盖；不向用户会话写入测试消息。
