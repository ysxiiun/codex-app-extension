# 测试策略：菜单栏确认重启失败恢复

## 范围与基线

- 框架：Swift 6、XCTest、XCUITest；TDD 关闭，不增加覆盖率或 CI 基础设施。
- 受影响路径：AppModel 菜单动作、RuntimeController 重启状态机、Debug runtime double、真实 MenuBarExtra UI tests。
- 安全边界：自动测试只能用 actor/UI doubles 模拟 terminate/launch/connect，不能真实终止当前用户的 ChatGPT。

## U1：RuntimeController 状态机

### 必测场景

1. 现有无 CDP 进程生成 pending plan，确认前 terminate/launch 次数均为 0。
2. terminate 在返回前失败：`pendingRestartConfirmation` 保持 true、pendingPlan 可再次消费、错误可见；解除 double 故障后第二次确认只执行一条成功 terminate/launch 链。
3. terminate/launch 成功但 pipeline connect 失败：旧 pendingPlan 已消费，`pendingRestartConfirmation` 为 false，observed PID/port 更新，错误可见。
4. 新 PID/端口进入下一 monitor cycle 后，pipeline reconnect 成功，连接/生命周期恢复且 pending 继续为 false；不得再次 terminate/launch。
5. 原有一次全成功路径保持 `terminate -> launch -> connect`，pending 清除。

### 定向命令

```bash
xcodebuild -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-restart-core \
  test \
  -only-testing:ExtensionCoreTests/RuntimeControllerTests \
  CODE_SIGNING_ALLOWED=NO
```

## U2：AppModel 与真实菜单栏动作

### 必测场景

1. 点击“确认重启 ChatGPT…”弹出独立 `NSAlert`；取消后 runtime 确认次数仍为 0，动作仍可用。
2. 点击“重启”后一次执行期只调用 runtime 一次，菜单显示进行中/禁用重复提交；成功后 pending 动作消失。
3. Debug runtime double 模拟确认执行返回但 pending 仍为 true：菜单恢复可点击，第二次点击再次出现 `restart.confirm`，证明 UI 锁没有跨失败永久保留。
4. 失败重试测试读取固定测试状态和计数，不依赖真实 ChatGPT、CDP 或任意用户内容。

### 定向命令

```bash
xcodebuild -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-restart-ui \
  build-for-testing

xcodebuild -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-restart-ui \
  test-without-building \
  -only-testing:CodexAppExtensionUITests/MenuBarUITests
```

## 完整门禁

```bash
xcodebuild -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Debug \
  -destination 'platform=macOS' \
  test \
  -only-testing:ExtensionCoreTests \
  CODE_SIGNING_ALLOWED=NO

xcodebuild -project CodexAppExtension.xcodeproj \
  -scheme CodexAppExtension \
  -configuration Release \
  -destination 'platform=macOS' \
  build

git diff --check
```

- Release 通过后运行现有 `./install.sh`，复核安装包签名/资源并确认扩展进程冷启动存活；安装不会代替真实 ChatGPT 重启验收。
- 当前工作树已有 Runtime/PageRuntime 与 Harness 改动，测试必须保留并在最终指纹中如实纳入，不能通过回滚它们制造绿色结果。

## 人工验收

1. 安装最终 Release，确认 ChatGPT 为无 CDP 启动状态。
2. 点击菜单动作，警告框必须可见；取消不得结束 ChatGPT。
3. 再次确认后，菜单应显示执行中；ChatGPT 正常退出并以唯一 `127.0.0.1:<dynamic-port>` 重启。
4. 若正常退出/启动失败，菜单显示错误且允许再次显式确认；若仅 CDP/Target 尚未就绪，则不要求再次破坏性确认，由监控自动恢复。
5. 最终状态应为 CDP 已连接、唯一合格 Target、增强按配置恢复。

## 无法自动验证项

- 真实确认重启会终止承载当前任务的 ChatGPT，会话和未发送输入可能丢失，因此必须由用户在安装完成后自行点击。
- 当前 ChatGPT 未来版本的启动参数行为不作永久保证；只接受本机安装版本的现场验收。
