# 测试策略：新建任务空白页宽屏连续生效

## 目标

验证 Target 资格、PageRuntime revision 与 wide-layout 作用域共同支持新建任务空白页，同时不放宽其他 adapter、不误选歧义页面、不破坏既有会话、右侧栏动态计算、性能预算和完整卸载合同。

## 必测矩阵

| 场景 | Target | wide-layout | 其他 adapter | 预期 |
|------|--------|-------------|----------------|------|
| 唯一 layout + 唯一 thread scroller，无 composer | 合格 | 按原 scroller 路径工作 | IME 等待 | 既有兼容不变 |
| 唯一 layout + 唯一 composer，无 thread scroller | 合格 | 回退 layout root，仅增强 composer width owner | header/Markdown 等按自身锚点等待 | 空白页立即宽屏 |
| 只有唯一 layout | 不合格 | 等待 | 等待 | 不误选过渡壳 |
| layout、scroller 或 composer 任一关键计数歧义 | 不合格 | 失败开放/等待或降级按现有合同 | 不注入 | 不误选 renderer |
| 空白页 → 会话页 | 持续合格 | 恢复 layout scope 后切到 scroller | 各 adapter 随锚点恢复 | 无残留、无双重 translate |
| 会话页 → 空白页 | 持续合格 | 恢复 scroller 后切到 layout scope | 缺失能力进入等待 | 输入框不闪回原生窄宽度 |
| 宽屏关闭/adapter uninstall | 不变 | marker、style、变量、owner offset、observer 全恢复 | 不受影响 | 宿主 DOM 与快照一致 |

## 自动化命令

### 定向 Core/CDP

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test \
  -only-testing:ExtensionCoreTests/TargetCoordinatorTests \
  -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests \
  CODE_SIGNING_ALLOWED=NO
```

### 定向 PageRuntime

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test \
  -only-testing:ExtensionCoreTests/PageRuntimeTests \
  -only-testing:ExtensionCoreTests/AdapterFixtureTests \
  CODE_SIGNING_ALLOWED=NO
```

### 全量门禁

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test \
  -only-testing:ExtensionCoreTests \
  CODE_SIGNING_ALLOWED=NO
```

并执行仓库现有 Release/安装 dry-run、`plutil`、签名/资源扫描与 `git diff --check`。若安装脚本没有 `--dry-run`，以其实际安全验证入口替换，不猜测参数。

## 隐私与性能

- bridge probe 只能统计 exact selector count，不读取 `innerText`、输入 value、DOM 序列化、URL payload、Cookie 或 WebSocket frame。
- 空白页 observer 必须继续通过统一 document-root coalescing；不得突破 8 ms/3 strikes、16 observers、32 events 固定门禁。
- current ChatGPT live gate 仅允许读取 exact target 数量、selector counts、runtime handshake/hydration 与既有 performance snapshot；禁止 install/update/diagnose/uninstall、重启、发消息、保存配置或读取正文/草稿。

## 人工验收

1. 安装新构建并启用“宽屏布局”。
2. 从已有会话点击新建任务，确认底部输入框不缩回原生窄宽度。
3. 在空白页发送首条消息或进入新会话，确认内容区与输入框保持连续，无左右跳动。
4. 新开直接落在空白任务页的窗口，确认无需先进入旧会话也能宽屏。
5. 开关右侧环境信息栏并缩放窗口，确认最大宽度和最小侧边距仍按实时可用空间收敛。
6. 关闭宽屏，确认页面恢复原生布局且没有残留 translate/marker/style。

## 无法自动证明

当前 ChatGPT 真实版本的主观视觉连续性和原生过渡动画只能由正式安装后的人工验收确认；自动化 fixture 负责证明结构、状态、公式、切换与清理合同。
