# 测试策略：1.0.0 版本元数据、产品信息与 macOS 分发

## 1. 必测合同

| 合同 | 归属 | 通过条件 |
|---|---|---|
| 单一版本源 | U1 | App/ExtensionCore `MARKETING_VERSION=1.0.0`、build=1；UI 从 Bundle 读取，不维护第二份版本常量 |
| App 内产品信息 | U1 | 通用页可访问节点稳定展示版本、作者 `ysxiiun`、GitHub 链接 |
| 本机安装兼容 | U1/U3 | `install.sh` 仍能 ad-hoc 构建、审计、幂等安装与冷启动，不被正式发布链破坏 |
| 正式发行安全边界 | U3 | 缺 Developer ID identity 或 notary profile 时 fail-closed；绝不自动降级为“正式” ad-hoc 包 |
| arm64 发行边界 | U3 | App 与 ExtensionCore Mach-O 都只有 arm64；README/产物名明确 Apple Silicon |
| DMG 完整性 | U3 | DMG 可验证、挂载，根目录包含 App 和 Applications 链接；App bundle 版本/资源/签名可审计 |
| 公证链 | U3 | 有外部凭据时 Developer ID + hardened runtime + timestamp + notarytool accepted + stapler validate 全绿 |
| 文档真实性 | U2 | README/CHANGELOG 命令与脚本真实参数一致，不把本地模式描述成可公开分发 |

## 2. 自动化与集成验证

```bash
plutil -lint CodexAppExtension/Supporting/Info.plist
bash -n install.sh
bash -n release.sh

xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-tests \
  test -only-testing:ExtensionCoreTests CODE_SIGNING_ALLOWED=NO

xcodebuild -project CodexAppExtension.xcodeproj -scheme CodexAppExtension \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/codex-app-extension-ui-tests build-for-testing

./release.sh --local-adhoc --output-dir /tmp/codex-app-extension-release-test
./install.sh
```

本地 DMG 生成后继续执行：

```bash
hdiutil verify '/tmp/codex-app-extension-release-test/Codex-App-Extension-1.0.0-arm64-local.dmg'
lipo -archs '<mounted>/Codex App Extension.app/Contents/MacOS/Codex App Extension'
lipo -archs '<mounted>/Codex App Extension.app/Contents/Frameworks/ExtensionCore.framework/Versions/A/ExtensionCore'
plutil -extract CFBundleShortVersionString raw -o - '<mounted>/Codex App Extension.app/Contents/Info.plist'
codesign --verify --deep --strict '<mounted>/Codex App Extension.app'
```

## 3. 正式发行负向与外部凭据验证

- 不传 `--identity` 或 `--notary-profile`：必须非零退出；错误明确指出缺失项；不得留下被命名为正式版的 DMG。
- identity 不是 `Developer ID Application`：必须拒绝，不接受 Apple Development、Mac Development、Mac Distribution 或 ad-hoc。
- identity/profile 齐全时：按嵌套 framework → App → DMG 顺序签名，所有签名带 secure timestamp，App 使用 hardened runtime；提交 `notarytool --wait` 后只有 Accepted 才继续 staple。
- 公证或 staple 失败：保留可诊断日志位置但不输出成功声明，不覆盖已有发行产物。

正式凭据环境命令：

```bash
./release.sh \
  --identity 'Developer ID Application: Example (TEAMID)' \
  --notary-profile 'codex-app-extension-notary'

codesign --verify --deep --strict --verbose=2 'dist/Codex App Extension.app'
spctl -a -t exec -vv 'dist/Codex App Extension.app'
xcrun stapler validate 'dist/Codex-App-Extension-1.0.0-arm64.dmg'
```

## 4. UI 与人工验收

- 设置 > 通用显示版本 `1.0.0`、构建 `1`、作者 `ysxiiun` 和 GitHub 地址；点击链接交给系统默认浏览器。
- 关于区不参与“应用/放弃”配置事务，修改其他设置时行为不变。
- 挂载 DMG 后能看到 App 与 Applications 快捷入口，拖入后从菜单栏启动。
- Apple Silicon 真机验证菜单栏状态、打开设置、登录项和 CDP 连接；不对 Intel Mac 宣称支持。

## 5. 当前环境无法完成的项目

当前机器没有有效代码签名身份，也没有已提供的 notarytool Keychain profile，因此不能产生真正可公开分发且经 Apple 公证的 1.0.0。验证阶段必须完成本地 ad-hoc DMG 和正式模式 fail-closed，并把 Developer ID/公证列为外部凭据依赖，不得用本机 ad-hoc 冷启动冒充公证通过。
