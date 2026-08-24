# 测试策略：新建会话页完整增强恢复

## 目标

验证 target probe 与 PageRuntime 使用同一套“会话页 / 新建会话空白页”结构身份，确保新建会话页不再因缺少 thread scroller 或 composer 标记变化而整体漏注入；同时保留 selector 唯一性、adapter 独立资格、失败开放、隐私与可卸载边界。

## 必测矩阵

| 场景 | Target / surface | wide-layout | header-offset | ime-enter-guard | Markdown 主题 |
|------|------------------|-------------|---------------|-----------------|---------------|
| 唯一 layout + 唯一 thread scroller | `thread` 合格 | 会话 scroller 路径 | 生效 | 唯一标记 editor 存在时生效 | Markdown candidate 存在时生效 |
| 唯一 layout + 唯一标记 composer，无 scroller | `empty-composer` 合格 | layout/composer owner 路径 | 生效 | 生效 | 无正文时 recoverable waiting |
| 唯一 layout + 唯一安全无标记 ProseMirror，无 scroller | `empty-composer` fallback 合格 | layout/composer owner 路径 | 生效 | 绑定 fallback editor | 无正文时 recoverable waiting |
| layout-only 或 fallback editor 未挂载 | 不合格/可恢复等待 | 不写入或保持安全预置 | 不写入 | 不绑定 listener | 不写入 |
| 重复 layout/scroller/editor 或 fallback 候选隐藏/歧义 | 不合格/失败开放 | 不接管歧义节点 | 不接管 | 不绑定 | 不写入 |
| 空白页 → 会话页 → 空白页 | 持续重新资格审查 | scope 双向切换无残留 | layout marker 持续正确 | editor listener 重绑且不重复 | thread 出现后生效、移除后恢复等待 |
| 同 ID 导航事件早于 composer DOM | event-time probe 可暂时不合格；health poll 后恢复 | 重新安装 | 重新安装 | 重新安装 | 按新 surface 等待/生效 |
| 升级 / 关闭 / uninstall | revision 热升级 | 宿主 marker/property/style 恢复 | 恢复 | listener/marker 恢复 | 恢复 |

## 自动化命令

### 定向 Core 与 PageRuntime

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-new-session \
  test \
  -only-testing:ExtensionCoreTests/TargetCoordinatorTests \
  -only-testing:ExtensionCoreTests/CDPPageRuntimeBridgeTests \
  -only-testing:ExtensionCoreTests/RuntimeReliabilityTests \
  -only-testing:ExtensionCoreTests/PageRuntimeTests \
  -only-testing:ExtensionCoreTests/AdapterFixtureTests \
  CODE_SIGNING_ALLOWED=NO
```

### 全量 ExtensionCoreTests

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-new-session \
  test \
  -only-testing:ExtensionCoreTests \
  CODE_SIGNING_ALLOWED=NO
```

### Release 与静态门禁

```bash
xcodebuild \
  -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-new-session-release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

./install.sh --audit-only \
  '/tmp/codex-app-extension-new-session-release/Build/Products/Release/Codex App Extension.app'

plutil -lint CodexAppExtension/Supporting/Info.plist
git diff --check
```

## 隐私、性能与恢复

- live probe 只读取 exact target 数量、结构 selector 数量、runtime revision/hydration、surface 分类和既有 adapter performance 状态；不读取正文、草稿、Cookie、完整 DOM、URL payload 或 WebSocket frame。
- composer fallback 只在 exact target、唯一 layout、无 thread scroller 时启用，并要求唯一布局内 ProseMirror editable；隐藏或歧义候选不得通过。
- observer 继续使用稳定 document root 的 child-list 合并，当前 editor 只观察必要资格属性；不得突破 8 ms/3 strikes、16 observers、32 events 的固定预算。
- 双向 SPA 切换、旧 revision 热升级与 uninstall 后，marker、style、inline property、listener、observer、RAF 和 timer 必须恢复或归零。
- 空白页 width owner 可使用 composer 或 canonical content token，但必须位于唯一 editor 到唯一 layout 的有限祖先路径上；生成 CSS 只允许 `:has(data-cae-wide-layout-editor)` 的当前确认 editor 分支命中，隐藏/残留 marked 旁支不命中。owner token 仅靠 class 原地增删时必须在下一合并帧双向切换 healthy/waiting，并继续完整恢复独立 composer 宽度变量与有限观察器。
- performance poll 的只读 envelope 只有在 runtime 或 performance API 确实缺失时返回专用 `runtimeUnavailable`；畸形 snapshot、transport、protocol 与 stale 错误不得触发 probe/apply。专用信号也必须在当前 generation/revision 仍匹配时才重新安装；并发 target 刷新、destroy 或 reconnect 已推进生命周期时，迟到 poll 只能丢弃。

## 人工验收

1. 正式安装并确认扩展总开关、宽屏、顶部栏、中文输入与 Markdown 外观配置已启用。
2. 从已有会话切换到新建会话页，确认输入框立即保持宽屏，顶部避让仍在，菜单状态不再显示 target 整体失效。
3. 在新建会话页使用真实中文输入法，确认组合输入期间 Enter 不误发送，组合结束宽限期后普通 Enter 恢复原生行为。
4. 发送首条消息进入会话后，确认宽度不跳回，Markdown 标题、强调、行内代码和引用样式在相应内容出现时生效。
5. 在新建会话与已有会话间往返，确认四个 adapter 状态按结构自动收敛且无重复偏移或事件。

## 无法自动证明

当前 live gate 不允许导航、发消息、读取输入或临时执行 adapter 生命周期，因此真实新建会话页的最终视觉连续性与中文输入手感需要正式安装后由用户人工验收；自动化 fixture 负责证明结构、状态、切换与完整恢复合同。
