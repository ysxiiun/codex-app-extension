## 技术方案：建立 1.0.0 版本元数据、发布文档与 macOS 分发能力

### 项目模式
迭代项目

### 任务类型
新功能 / 发布工程 / 前端设计实现

### 需求解析
- **目标**：把当前产品正式定义为 1.0.0，在 App 内可追溯版本与作者信息，并建立可重复生成 Apple Silicon DMG 的本地测试与 Developer ID 公证发行链路。
- **输入**：用户指定版本 1.0.0、三段版本规则、作者 `ysxiiun`、GitHub 地址，并询问当前 App 是否可直接给其他用户以及如何像常规 macOS App 一样提供成品安装包。
- **输出**：改代码并出文档；更新 Xcode 版本元数据与设置 UI，新增 `CHANGELOG.md` 和正式发行脚本，更新现有 `README.md` 与架构摘要，最终能生成 arm64 `.app`/`.dmg`，并明确当前证书条件下的可分发结论与取得公开分发能力的步骤。
- **边界**：不接入 Mac App Store、不实现自动更新、不提交证书/Apple ID 密钥/公证凭据、不伪造公证成功；不改变 ChatGPT/CDP/PageRuntime 业务行为；本次正式发行只支持 Apple Silicon，不承诺 Intel Mac；不另外创建仅大小写不同的 `README.MD`（macOS 默认文件系统会与现有 `README.md` 冲突），统一使用社区惯例 `README.md`/`CHANGELOG.md`。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：Xcode App/ExtensionCore targets、`Info.plist`、通用设置页、设置 UI tests、`install.sh`、README 与架构摘要。
- **当前实现方式**：版本由 build settings 注入 Info.plist；诊断页已有 bundle 版本读取，通用页没有产品信息；`install.sh` 以禁用 Xcode 签名的方式构建，再按 framework → App 做 ad-hoc 签名并安装到 `/Applications`。
- **现有问题 / 缺口**：Marketing Version 仍为 `1.0`；没有 changelog；README 明确没有预构建安装包/公证链；安装脚本产物为 ad-hoc、无 TeamIdentifier，当前钥匙串没有有效代码签名身份，Gatekeeper 不会把它当作正常公开发行；Release target 未开启 Hardened Runtime；安装产物只有 arm64；UI 没有作者和项目链接。
- **证据**：`CodexAppExtension.xcodeproj/project.pbxproj:716-778` 的 App/ExtensionCore `MARKETING_VERSION = 1.0`；`Info.plist:17-20` 使用 build setting 注入版本；`GeneralSettingsView.swift:7-22` 只有扩展和登录启动两节；`install.sh:625-634` 禁用签名并执行 `--sign - --timestamp=none`；`README.md:28-64` 只描述本机 ad-hoc 安装并声明无公开分发流程。当前 `/Applications/Codex App Extension.app` 的 `codesign -dv` 为 `Signature=adhoc`、`TeamIdentifier=not set`，`security find-identity -v -p codesigning` 为 `0 valid identities found`。分析阶段实测 `ARCHS='arm64 x86_64'` 可成功构建两架构，但用户已选择 1.0.0 正式发行仅 arm64。

### 冲突摘要
- 需求 vs RULES：无冲突；版本、安装方式与诊断字段变化会同步 README，并保持 plist、Release、签名与安装验证门禁。
- 需求 vs ABSTRACT：有计划内冲突；ABSTRACT 当前把 `install.sh` 描述为唯一 Release 入口，需区分“本机安装”与“对外发行”。
- 需求 vs 现有代码：有明确差距；当前版本号、UI、签名模式与分发产物均不满足需求。
- Dev-Spec vs 现有代码：有计划内变更；新增发行脚本与 changelog，Release 开启 Hardened Runtime，通用页增加只读产品信息。

### 影响面分析
- **涉及模块**：Xcode 版本/签名构建配置、SwiftUI 通用设置、XCUITest、Shell 发布工程、Markdown 文档。
- **核心类 / 页面 / 接口**：`GeneralSettingsView`、App target build settings、`release.sh` 的 build/sign/package/notarize pipeline。
- **数据库变更**：无。
- **接口变更**：新增仓库级 `release.sh` 命令行入口；App 配置模型和 PageRuntime 协议无变化。
- **关联历史任务**：`SM-019fcfe3-0cfa-7d6b-987c-0edda8fb811c`（Release 幂等安装与动态宽屏布局稳定修复）；`SM-019fc76b-6b2c-745d-9c4b-d08639bd0a68`（原生菜单栏运行时 V2 重构）。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension.xcodeproj/project.pbxproj` | 修改 | 保持原编码 UTF-8/ASCII compatible | App 与 ExtensionCore 版本统一为 1.0.0；Release 开启 Hardened Runtime。 |
| `CodexAppExtension/App/Settings/GeneralSettingsView.swift` | 修改 | 保持原编码 UTF-8 | 增加“关于”区，动态读取版本/构建号并展示作者、可点击 GitHub 链接。 |
| `CodexAppExtensionUITests/SettingsUITests.swift` | 修改 | 保持原编码 UTF-8 | 锁定版本、作者、GitHub 产品信息及可访问标识。 |
| `release.sh` | 新增 | 项目编码 UTF-8，依据：现有 `install.sh` 为 UTF-8 Shell | 建立 arm64 构建、嵌套签名、审计、DMG 打包、公证、staple 与本地测试模式。 |
| `.gitignore` | 修改 | 保持原编码 UTF-8 | 忽略可再生成的 `dist/` 发行产物。 |
| `CHANGELOG.md` | 新增 | 项目编码 UTF-8，依据：现有 Markdown | 记录 1.0.0 初始稳定发行，并固化 major/minor/patch 维护原则与 Unreleased 区。 |
| `README.md` | 修改 | 保持原编码 UTF-8 | 展示版本/作者/仓库地址，区分开发安装与正式发行，给出证书、公证和 DMG 使用步骤，声明 arm64 边界。 |
| `.easy-coding/ABSTRACT.md` | 修改 | 保持原编码 UTF-8 | 同步本机安装入口与正式发行入口、签名/公证边界和验证要求。 |

### 修改方案
- **总体改法**：以 Xcode build settings 为唯一版本源，UI 从 Bundle 动态读取；保留 `install.sh` 的本机幂等安装职责，新增 fail-closed 的 `release.sh` 负责 arm64 Developer ID 发行与 DMG 公证。
- **后端改动**：新增发布流水线。默认正式模式必须显式提供 `Developer ID Application` identity 与 `notarytool` Keychain profile；先无签名构建 arm64，再按 ExtensionCore → App → DMG 顺序签名，使用 secure timestamp 与 hardened runtime，执行 `codesign`/`spctl`/`notarytool`/`stapler` 审计。`--local-adhoc` 是显式本地测试模式，只生成带明显本地测试语义的 DMG，不声称可对外发布。
- **前端改动**：通用设置增加紧凑“关于”区，显示 `版本 1.0.0（构建 1）`、作者和 GitHub Link；不增加额外设置项或干扰现有配置保存。
- **兼容处理**：继续支持 `./install.sh` 本机开发安装；现有配置、登录项、CDP 和四个 adapter 不迁移。README 解释旧 ad-hoc 安装不等于正式发行。正式产物固定 arm64，未来如需 Intel/Universal 作为常规功能升级再扩展。
- **风险点**：签错嵌套 framework 或签名顺序导致 Gatekeeper 拒绝；把未公证产物误标为正式版；hardened runtime 引入启动回归；DMG 内 App/Applications 链接布局错误；UI 直接硬编码版本造成后续漂移；本机没有 Developer ID 证书与公证凭据，因此本轮不能实际完成 Apple 公证，只能验证 fail-closed 与本地测试包链路。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 | 验收条件 | 测试点 | 跨单元契约 |
|------|------|------|---------|------|---------|-------|-----------|
| U1 | 1.0.0 元数据与 App 内产品信息 | frontend/config/test | project.pbxproj、GeneralSettingsView、SettingsUITests | — | 构建 Info 为 1.0.0/1；通用页显示版本、作者和 GitHub 链接 | plist、Release build、XCUITest/可访问标识 | UI 必须从 Bundle 读取版本，不复制第二份版本常量 |
| U2 | 版本维护与使用文档 | docs | CHANGELOG.md、README.md | U1 | README/CHANGELOG 一致声明 1.0.0、版本规则、作者、arm64、安装与发行步骤 | 文档命令/链接/版本静态扫描 | 文档只宣称 U3 实际提供的模式与产物 |
| U3 | 安全可重复的 DMG 发行链 | build/security/docs | release.sh、.gitignore、project.pbxproj、ABSTRACT.md | U1 | 本地模式生成可挂载 arm64 DMG；正式模式无凭据时提前失败，有凭据时签名、公证、staple 并验证 | Shell 语法、local DMG、Mach-O、codesign、hdiutil、fail-closed | 版本从已构建 Info.plist 读取；正式/本地模式不得混淆 |

**执行策略**：sequential
- 第一批：U1 版本元数据与 UI
- 第二批：U3 发行链
- 第三批：U2 文档按最终命令与产物收口

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 工程与产物版本一致 | 必测 | U1 | plist/build | `plutil -lint ...` + Release 产物读取 `CFBundleShortVersionString/CFBundleVersion` |
| 关于区信息可见且版本非硬编码漂移 | 必测 | U1 | 编译/XCUITest/源码审查 | SettingsUITests 定向测试 + `rg` 版本源 |
| arm64 本地测试 DMG 可生成、挂载并包含正确 App | 必测 | U3 | Shell 集成 | `bash -n release.sh`；`./release.sh --local-adhoc --output-dir /tmp/...`；`hdiutil verify/attach`；`lipo -archs` |
| 正式发行 fail-closed | 必测 | U3 | 负向集成 | 缺 identity/profile 时命令非零且不生成“公证完成”产物 |
| Developer ID、公证与 stapling | 依赖外部凭据 | U3 | 安全发行 | `codesign --verify --deep --strict`、`spctl -a -t exec`、`xcrun notarytool submit --wait`、`xcrun stapler validate` |
| 全量业务回归与本机安装 | 必测 | U1/U3 | XCTest/Release | ExtensionCoreTests 全量；`./install.sh`；安装后冷启动存活 |
| 文档/版本/产物命名一致 | 必测 | U2 | 静态扫描 | README/CHANGELOG/release.sh/project 交叉检查，`git diff --check` |

- **人工验收**：设置 > 通用可看到版本 1.0.0、作者 ysxiiun 和可点击 GitHub 链接；挂载 DMG 后能把 App 拖入 Applications；从 DMG 安装的本地测试包在本机可启动。
- **无法验证项**：当前钥匙串 `0 valid identities found`，缺少 Developer ID Application 证书和 notarytool 凭据，无法在本机完成真实 Apple 公证/Gatekeeper 外机验证；实现必须通过明确的缺凭据失败和文档步骤交付，不能把 ad-hoc 成功作为替代证据。

### Workflow Mode
- **项目配置**：adaptive
- **Session 覆盖**：无
- **机械最低模式**：strict
- **推荐并选择**：strict
- **选择原因**：变更跨 Xcode 版本/安全构建设置、App UI、Shell 发布流水线和公开文档；正式分发涉及 Developer ID、hardened runtime、公证与 Gatekeeper，错误会直接导致用户无法安装或造成错误安全承诺。
- **状态内执行差异**：IMPLEMENT 顺序完成 U1/U3/U2 并逐单元验证；REVIEW 独立覆盖签名安全/失败策略、UI/版本合同和文档准确性；VERIFICATION 执行全量 Core、Release 本机安装、本地 DMG 集成与正式模式负向门禁，外部公证项明确标记为凭据阻塞；MEMORY 记录 1.0.0 版本与双入口发布合同。

### 风险与注意事项
- `release.sh` 绝不能自动回退到 ad-hoc 后仍把产物命名或提示为正式发行；正式模式缺少任一凭据都必须在构建/上传前失败。
- 不在仓库或日志中写入 Apple ID、app-specific password、API private key 或 Developer ID 私钥；推荐只引用 `notarytool store-credentials` 创建的 Keychain profile。
- DMG/`.app` 是构建产物，不提交 Git；公开发布时应作为 GitHub Release asset 上传，并让源码 tag、CHANGELOG 与 bundle 版本一致。
