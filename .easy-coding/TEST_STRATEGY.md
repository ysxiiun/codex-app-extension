# codex-app-extension 测试策略

> 由 ec-init 根据 `verify.sh`、README 和当前运行环境生成。

## 测试基线

- 测试框架：无第三方框架；使用仓库自带的零依赖自定义验证脚本。
- 标准命令：`./verify.sh`。
- 命令状态：已于 2026-07-10 在当前仓库验证通过。
- 构建命令：无；项目直接运行 `.mjs` 和 Shell 脚本。
- 覆盖率工具与阈值：无；不声明无法采集的行覆盖率百分比，以关键分支断言和在线验收清单作为门禁。

## 测试位置与命名

- 自动验证入口固定为仓库根目录 `verify.sh`。
- JavaScript 断言位于 `verify.sh` 的 Node.js ESM heredoc 中，避免为当前零依赖项目引入 test runner。
- 当前没有 `test/`、`tests/` 或 `*.test.*` 文件，也没有可证实的单测文件命名惯例。
- 若验证逻辑仍是少量注入 builder/选择器断言，继续扩展 `verify.sh`；只有规模明显增长并经用户确认后才引入独立测试目录或框架。

## 标准验证覆盖

`./verify.sh` 必须同时覆盖：

1. `lib/runtime.sh`、启动、配置、当前实例和作者配置 Shell 入口的 `bash -n`。
2. `inject-wide-layout.mjs` 的 Node.js `--check`。
3. 动态暴露 builder 后，编译生成的 surface probe、diagnose 与 installer 源；宽屏启用和关闭分支都要编译。
4. 生成 CSS 必须含 `data-codex-app-extension-surface="true"`，并拒绝已知未加表面约束的增强选择器。
5. target 选择必须拒绝无关页面并优先 Codex 候选；surface probe 必须分别覆盖支持和拒绝样例。
6. 注入源码必须保留新版 request input、dismiss 和 skip 锚点。
7. 当前应用 bundle id、PATH/内置 Node 的 `fetch`/`WebSocket` 能力，以及 ChatGPT `app.asar` 中的布局与输入稳定锚点。
8. 仓库处于 Git 工作树时执行 `git diff --check`。

## 条件式在线验证

当 ChatGPT/Codex 已通过 `./launch.sh` 暴露 CDP 端口时，运行：

```bash
CODEX_APP_EXTENSION_VERIFY_LIVE=1 ./verify.sh
```

该命令追加只读 `inject-current.sh --diagnose`。重点确认：

- `surfaceSupported=true`，target、URL 和 surface anchor 计数符合当前 Codex 工作区。
- `layoutWidthState` / `layoutWidthScopes` 的参考容器、gutter 与右侧 rail 避让合理。
- `nativeFloatingResetTargets` 与 `leftSidebar` 没有继承错误宽度或偏移。
- request input 出现时协议为 `chatgpt-codex-data-attributes` 或明确的 legacy fallback。
- 启用的 IME、长文本、Tab 和主题功能显示已安装；最近事件原因与实际操作一致。

没有调试端口时必须标记在线验证未运行，不能用 `app.asar` 静态锚点代替运行时验收。

## 人工验收范围

以下行为依赖真实 Electron 窗口、输入法或视觉布局，不由默认脚本完全证明：

- 窗口模式、全屏、左侧栏开合、右侧 agent/来源面板与 git/diff 浮层的实际宽度和抖动。
- 中文输入法组合期间 Enter、组合结束后的 Enter，以及 Plan/request input 的原生提交。
- `longTextSendEnhancement=true` 时 Enter 换行、Cmd+Enter 发送；`tabIndentEnhancement=true` 时普通 Tab 与焦点导航边界。
- 主题、标题、strong、行内代码、引用和 focus ring 的视觉可读性。
- 正常方式重启应用后扩展不残留，证明增强可撤销。

## 必测与暂不测试的代码类别

### 必测

- 应用/Node/端口发现顺序和能力门禁。
- CLI 与配置解析校验、默认/关闭分支、旧兼容 alias。
- CDP target 防误选和 Codex surface 失败关闭。
- 生成 CSS 作用域、request input 识别与提交按钮失败开放。
- 诊断字段结构和已知稳定锚点存在性。

### 暂不自动化

- macOS `open -na` 真正重启应用：会中断当前用户会话，默认测试不得执行。
- 实际 CDP WebSocket 的完整注入写入：需要用户以调试端口启动应用；默认验证只做生成代码编译。
- 像素级截图比较和真实 IME 自动化：仓库没有浏览器驱动、截图基线或输入法控制设施。
- `strong-text-color-preview.html`：仅人工配色预览，不作为生产正确性证据。

## 变更到验证的映射

| 变更类型 | 最低验证 |
|---|---|
| `inject-wide-layout.mjs` 配置、builder、选择器或事件 | `./verify.sh`；有端口时追加在线验证和对应人工输入/布局场景 |
| `lib/runtime.sh`、`launch.sh`、`inject-current.sh` | `./verify.sh`；至少覆盖显式覆盖、PATH Node 和内置 Node fallback |
| `config.sh`、`data/author-config.json` | `./verify.sh`，并人工确认 `--configure` 不丢未知字段或软链接语义 |
| README / ABSTRACT | 检查命令、字段、优先级和实际代码一致；`git diff --check` |
| 仅预览 HTML | 浏览器人工查看目标颜色，不替代 `./verify.sh` |

## 通过标准与失败处理

- 标准命令退出码必须为 0，且输出 `Verification passed.`。
- 任何 bundle、Node 能力、生成源码、surface、target 或 anchor 断言失败都阻止交付；先按错误项定位当前应用升级边界。
- 在线诊断失败时先区分“应用未带 CDP 端口”“target 未注册”“surface 签名变化”“注入代码异常”，不得直接放宽选择器或恢复任意 target 回退。
