# 项目架构摘要

> 最后更新：2026-05-11

## 项目定位

`codex-app-extension` 是面向 Codex App 的本地运行时增强工具，通过远程调试端口向正在运行的 Codex 页面注入样式和事件处理逻辑，改善宽屏阅读、全屏遮挡、中文输入法 Enter、防长文本误发送等体验。

## 模块结构

| 模块 | 职责 | 路径 |
|---|---|---|
| 注入脚本 | 读取配置、连接 CDP、注入 CSS/JS、输出诊断 | `inject-wide-layout.mjs` |
| 启动脚本 | 以远程调试端口启动 Codex App 并调用注入脚本 | `launch.sh` |
| 使用文档 | 说明能力、配置、CLI、环境变量、诊断和兼容入口 | `README.md` |
| 许可证 | 项目授权声明 | `LICENSE` |

## 核心业务流程

1. **启动 Codex App**：`launch.sh` 检查 Node.js 与 Codex App 路径，必要时通过 `open -na` 带远程调试端口启动 Codex。
2. **发现调试目标**：`inject-wide-layout.mjs` 轮询 `http://127.0.0.1:{port}/json/list`，选择可附加的 Codex 页面 target。
3. **合并配置**：按“内置默认值 < 配置文件 < 环境变量 < CLI 参数”生成最终运行选项。
4. **注入增强**：通过 CDP `Runtime.evaluate` 执行页面上下文代码，安装 CSS、全屏状态检测、IME Enter 防护和长文本发送增强。
5. **诊断输出**：`--diagnose` 读取页面布局、配置元信息、已安装增强状态和最近输入事件状态。

## 技术栈

- Node.js ESM
- Chrome DevTools Protocol
- WebSocket
- 运行时 CSS 注入
- DOM 事件捕获与输入法组合事件处理
- Bash
- JSON 配置
- Markdown 文档

## 目录索引

| 功能 | 路径 |
|---|---|
| 默认配置与配置读取 | `inject-wide-layout.mjs` |
| CLI 参数解析 | `inject-wide-layout.mjs` |
| CDP target 发现与连接 | `inject-wide-layout.mjs` |
| CSS 样式生成 | `inject-wide-layout.mjs` |
| IME Enter 防护 | `inject-wide-layout.mjs` |
| 长文本发送增强 | `inject-wide-layout.mjs` |
| 启动入口 | `launch.sh` |
| 用户说明 | `README.md` |

## 当前约束

- 项目当前无构建系统、无 package.json、无自动化测试框架。
- 修改 `inject-wide-layout.mjs` 后，至少需要执行 Node.js 语法检查。
- 能访问 Codex 调试端口时，应优先用 `--diagnose` 验证注入状态。
- Codex App 页面结构可能随版本变化，选择器和 DOM 事件策略需要保持可诊断、可回退。
