# 项目架构摘要

> 最后更新：2026-07-10

## 项目定位

`codex-app-extension` 是面向 ChatGPT 中 Codex 工作区的本地运行时增强工具，并兼容旧版独立 Codex App。它通过仅监听回环地址的远程调试端口，在确认 target 具有 Codex 工作区表面签名后注入样式和事件处理逻辑，改善宽屏阅读、全屏遮挡、中文输入法 Enter、防长文本误发送等体验。

## 模块结构

| 模块 | 职责 | 路径 |
|---|---|---|
| 注入脚本 | 读取配置、连接 CDP、注入 CSS/JS、输出诊断 | `inject-wide-layout.mjs` |
| 运行时发现 | 发现 ChatGPT/Codex 应用、兼容 Node.js 与调试端口 | `lib/runtime.sh` |
| 启动脚本 | 以回环远程调试端口启动 ChatGPT/Codex 并调用注入脚本 | `launch.sh` |
| 当前实例注入 | 发现已有 ChatGPT/Codex 调试进程并重新注入或诊断 | `inject-current.sh` |
| 配置脚本 | 使用兼容 Node.js 维护本地配置 | `config.sh` |
| 自动验证 | 校验应用身份、运行时、生成代码、表面保护和新版输入锚点 | `verify.sh` |
| 使用文档 | 说明能力、配置、CLI、环境变量、诊断和兼容入口 | `README.md` |
| 许可证 | 项目授权声明 | `LICENSE` |

## 核心业务流程

1. **发现应用与运行时**：按“显式 `CODEX_APP` > `ChatGPT.app` > `Codex.app`”解析应用，按显式 `NODE_BIN`、PATH 与应用内置 Node 的顺序寻找同时支持 `fetch` / `WebSocket` 的运行时。
2. **启动 ChatGPT/Codex**：`launch.sh` 通过 `open -na` 启动应用，并把远程调试端口限制在 `127.0.0.1`。
3. **发现调试目标**：`inject-wide-layout.mjs` 轮询 `http://127.0.0.1:{port}/json/list`，按 Codex、`app:`、ChatGPT 等信号给 target 评分，不回退到任意页面。
4. **校验工作区表面**：通过布局根、工作区和交互锚点组成的 DOM 签名确认当前页面是 Codex 工作区；不满足时拒绝注入。
5. **合并配置**：按“内置默认值 < 配置文件 < 环境变量 < CLI 参数”生成最终运行选项。
6. **注入增强**：通过 CDP `Runtime.evaluate` 执行页面上下文代码；CSS、布局变量、IME、长文本和 Tab 逻辑统一受 Codex 表面开关约束。
7. **输入协议适配**：新版 request input 使用 `data-codex-composer-request-navigation` / `data-request-input-*`，旧类名继续回退；提交按钮识别有歧义时让给原生行为。
8. **诊断输出**：`--diagnose` 读取表面签名、布局消费者、输入协议、配置元信息、已安装增强状态和最近输入事件状态。

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
| Codex 表面签名与路由保护 | `inject-wide-layout.mjs` |
| CSS 样式生成 | `inject-wide-layout.mjs` |
| IME Enter 防护 | `inject-wide-layout.mjs` |
| 长文本发送增强 | `inject-wide-layout.mjs` |
| request input 新旧协议适配 | `inject-wide-layout.mjs` |
| 应用 / Node / 调试端口发现 | `lib/runtime.sh` |
| 启动入口 | `launch.sh` |
| 自动验证入口 | `verify.sh` |
| 用户说明 | `README.md` |

## 当前约束

- 项目当前无构建系统、无 package.json、无测试框架；`verify.sh` 提供零依赖静态与生成代码验证。
- 修改 `inject-wide-layout.mjs` 或运行时发现链后，至少需要执行 `./verify.sh`。
- 能访问 Codex 调试端口时，应优先用 `--diagnose` 验证注入状态。
- 已运行但未带远程调试端口的 ChatGPT/Codex 进程不能无损补开端口；在线验证必须在退出后通过 `launch.sh` 重启再执行。
- ChatGPT Codex 页面结构可能随版本变化，选择器和 DOM 事件策略需要保持可诊断、可回退、失败时让给原生行为。
