# 测试策略：环境信息右栏与宽屏动态避让

## 目标

证明 ChatGPT 新版透明 PIP obstacle 能在稳定 rail shell 内驱动 right boundary，并同时覆盖关闭、展开、关闭动画结束、ordinary fast path、observer 收敛、旧 painted rail 兼容、完整恢复和 runtime revision 升级。

## 回归矩阵

| 场景 | PIP 双属性 | painted component | 预期 |
|------|-------------|-------------------|------|
| 右栏关闭、透明 shell 挂载 | 无 | 无 | `rightRail=false`，按完整 reference width 计算 |
| 新版环境信息展开，布局参考为底部 composer 行 | 同一节点同时为 `thread-summary-panel` | 可无 | 顶部 obstacle 只需与 stable rail shell 相交；`rightRail=true`，rightBoundary 等于 rail 左边界 |
| 仅一个 PIP 属性或其他值 | 不完整/不匹配 | 无 | 不占宽，避免误收其他 PIP |
| 环境信息关闭并结束动画 | 移除 | 最终不可见 | 释放 rail 宽度，无残留 offset |
| 旧版真实卡片/短空态 | 无 | 有背景、边框或阴影 | 保持既有避让行为 |
| rail 内菜单/listbox/dialog | 任意 | 任意 | 仍按瞬态浮层排除 |
| adapter uninstall | 任意 | 任意 | marker、CSS 变量、owner offset、observer/RAF/timer 完整恢复 |

## 自动化命令

### 定向 rail fixture

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-environment-panel \
  test \
  -only-testing:ExtensionCoreTests/AdapterFixtureTests \
  CODE_SIGNING_ALLOWED=NO
```

### 定向 runtime bridge

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-environment-panel \
  test \
  -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests \
  CODE_SIGNING_ALLOWED=NO
```

### 完整 Core/PageRuntime 门禁

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-environment-panel \
  test \
  -only-testing:ExtensionCoreTests \
  CODE_SIGNING_ALLOWED=NO
```

### 静态、Release 与安装

```bash
node --check CodexAppExtension/Resources/Adapters/wide-layout.js
node --check CodexAppExtension/Resources/PageRuntime/bootstrap.js
git diff --check
xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension -configuration Release -destination 'platform=macOS' build
```

随后使用仓库 `install.sh` 的既有安全入口执行 Release 安装、签名/资源一致性审计与运行存活检查；不得重启 ChatGPT。

## 隐私与 live gate

- exact `app://-/index.html` target 必须为 1。
- 只输出 rail shell、PIP 双属性节点、layout/scroller/owner 数量、扩展公开 revision/hydration/observer 健康与数值几何；不读取 `innerText`、输入 value、DOM 序列化、Cookie、payload 或网络帧。
- 用户保持环境信息展开时，核对 PIP 双属性唯一命中、right rail 左边界与扩展计算后的 rightBoundary/offset；面板关闭时两属性计数应回到 0 且完整宽度恢复。
- live gate 不执行 install/update/diagnose/uninstall，不点击 UI，不发送消息，不保存配置，不重启 ChatGPT。

## 人工验收

1. 保持宽屏增强开启，展开右上角“环境信息”，确认正文、状态行、输入框与 Markdown 宽块不进入面板下方。
2. 关闭环境信息，确认内容恢复完整宽度，没有持续右侧留白。
3. 再开关一次并缩放窗口，确认动画结束后边界稳定、无横向跳动或残留。

## 无法自动证明

自动化 fixture 可以证明结构、状态、公式、快路径和清理合同，但不能替代当前真实 ChatGPT 窗口的像素级视觉判断；若用户未保持面板展开，live gate 只记录关闭态证据，不自动操作 UI。
