# 测试策略：恢复 fullscreenHeaderOffset 顶部避让

## 范围

- 验证 `fullscreenHeaderOffset` 的配置链和字段语义保持不变。
- 验证生成 CSS 将旧版 main surface 与新版 app-shell layout root 纳入同一顶部避让合同。
- 验证当前 ChatGPT 全屏窗口中固定 header 与主内容、右侧 floating rail 不再重叠。

## 必测项

| 测试点 | 方法 | 命令 / 证据 | 通过条件 |
|---|---|---|---|
| Node 与 Shell 语法 | 静态检查 | `node --check inject-wide-layout.mjs`、`bash -n verify.sh` | 均退出 0 |
| 生成 CSS 合同 | 零依赖回归 | `./verify.sh` | surface guard 下的顶部避让 selector 精确覆盖新旧四类根；规则含 `box-sizing: border-box` 和配置变量 padding；禁止回退为 legacy-only selector |
| 补丁范围与编码 | Diff/文件检查 | `git diff --check`、`file -I` | 无空白错误；源码编码保持不变；任务外既有修改未被覆盖 |
| 当前 target 在线诊断 | Live CDP | `CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh` | `app://-/index.html` surface 通过，`fullscreenHeaderOffset=46px`，新版 layout root 存在 |
| 当前窗口几何 | 重注入和只读探针 | `./inject-current.sh` 后读取 header/layout/frame/thread/rail rect 与 computed style | layout `padding-top=46px`；`header.bottom=46`；`frame.top=46`；rail 顶部不小于 header 底部；页面结构和 composer 仍可用 |

## 人工验收

- 全屏窗口顶部固定标题栏不再覆盖 Git Diff、Plan、对话内容或其他主内容。
- 输入框和右侧面板仍保持正常位置与可用高度。

## 不适用项

- 项目没有 package.json、lint、TypeScript typecheck 或构建系统；这些检查记录为不适用，不能虚构命令。
- 不修改 ChatGPT 应用包体，不发送测试消息，不需要数据库或接口测试。
