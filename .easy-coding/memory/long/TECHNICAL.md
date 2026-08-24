---
memory_schema: 2
memory_file: TECHNICAL
last_updated: 2026-08-11
---

# 长期技术记忆

## 有效记忆

### 原生宿主与 PageRuntime V2

- Codex App Extension 的唯一产品宿主是 macOS 原生菜单栏 App。Swift 负责进程生命周期、配置、CDP、健康和 UI；页面 JavaScript 仅负责通过资格审查、可独立安装和卸载的 adapters。UI 不直接操作 CDP 或文件系统，统一经 `RuntimeController`。
- 只识别 `/Applications/ChatGPT.app`、bundle id `com.openai.codex` 的主进程；CDP 必须是显式 `127.0.0.1` 回环端口。正在运行但没有 CDP 时先等待用户确认，确认前不得终止或重启应用。
- Browser 级连接订阅 `Target.*`，只接纳 exact `app://-/index.html`。target 身份、surface 资格和 adapter capability 分层处理；页面升级不能靠产品版本号、窗口标题或业务文案推断兼容性。
- `window.__codexAppExtensionV2` 是 runtimeVersion 2 API。bootstrap 与 adapter 源码分离加载，单 adapter 的 source/evaluate/execute 失败不得阻塞其他增强；资源或 lifecycle 逻辑变化必须同步 implementation revision、Swift bridge、热升级测试和文档。
- 同 target 的 reload、SPA 根替换和 reconnect 都可能让旧节点或旧异步结果失效。运行时写入需以 lifecycle generation、active identity、known membership、surface/per-target revision 等状态隔离迟到结果，不能只比较 target ID 或幂等签名。

### Adapter 生命周期与宿主状态恢复

- 对非公开 DOM 使用小型独立 adapter、唯一 native anchors、幂等 install/update/diagnose/uninstall、宿主属性/CSS 快照恢复、observer 合并与单项性能熔断。adapter 聚合不能把单项失败升级为整个 target 丢失。
- React/Electron 会复用节点并只修改 class、hidden、aria-hidden 或 style，不一定产生 child-list mutation。等待结构能力时，应只观察影响资格的有限节点和最窄 attribute filter，并覆盖资格增加、移除两个方向。
- DOM burst 应合并为一轮 RAF 加一轮 settle；observer、事件、target 状态、RAF 和 timer 必须有界。卸载和 surface 切换需证明 marker、style、property、listener、observer、RAF、timer 全部归零或恢复。
- 诊断只允许版本、状态、错误码、计数和耗时等 typed allowlist 字段；live gate 不读取正文、草稿、Cookie 或 payload，且必须在 `finally` 中卸载并验证主世界和宿主 DOM/CSS 恢复。

### 配置事务与离线能力

- schema-v2 是唯一配置源，采用同目录临时文件、同步、原子替换和 last-known-good；首次保存必须同时建立 current 与 LKG 可恢复基线。
- 配置更新遵循“本地先校验、在线预应用、原子持久化、失败回滚”。没有合格 target 时仍允许离线保存，待连接后延迟安装；在线应用失败不能留下页面状态与持久化配置不一致。
- V1 迁移保留备份且幂等，只映射有效字段；废弃、未知或无效字段进入迁移报告，不能静默写入新 schema。

### 浮层分类、右侧栏与 composer 对齐

- 页面浮层按职责分为三类：`menu/listbox` 瞬态交互浮层不参与 right rail；composer 上方附着组件跟随 composer 中心；持久 `thread-floating-content` rail 继续参与主内容避让并保持局部宽度/偏移隔离。
- 瞬态浮层分类必须形成对称闭包：元素自身 `matches()`、位于菜单内部的 `closest()`、包裹菜单的 `querySelector()` 都使用完整 `role=menu/listbox` selector；在几何测量前排除命中的定位 wrapper，避免“宽度回写—菜单重定位—再测量”的反馈环。
- composer 附着组件同时兼容旧版类名信号和新版几何结构。新版候选需消费 thread/composer 宽度变量、与主 composer 共享非 layout-shell 宿主、位于其上方并有定位祖先，同时排除 menu/listbox 与 persistent rail。
- 附着组件偏移是目标相对自然位置的绝对 translate，不等同于根 content offset。先以 `naturalCenter = currentCenter - currentTranslate` 恢复自然中心，再计算 `composerCenter - naturalCenter`，避免新版自然居中 slot 重复左移及多轮刷新累计；已有原生 transform 时失败开放。
- 浮层分类和布局调整必须有可执行行为回归：覆盖共同宿主/定位祖先、普通 flow/menu/rail/独立宿主负例、原生 transform 排除、重复刷新幂等、目标退出与增强关闭清理。只检查生成源码包含函数名或属性写入字符串不足以证明行为。

### 顶部避让与兼容根

- 顶部避让不能对所有兼容 selector 同时加 padding。运行时按新版 data layout、旧 app-shell viewport、旧 main surface 的顺序只选择并标记一个实际布局根，CSS 只作用于唯一 marker。
- 跨版本兼容根可能形成祖先/后代嵌套；grouped `:is/:where` 只能合并 selector，不能保证单点生效。对会累积的 padding、transform 或 margin，应使用“有序候选 + 唯一 marker + 生命周期清理”。
- `fullscreenHeaderOffset` 独立于宽屏开关，目标选择必须位于宽屏分支之外。根切换、离开 surface 或关闭增强时清理旧 marker；marker 自身不要进入 observer 的 attributeFilter，避免自激刷新。
- 不要把顶部偏移直接写到 `.thread-scroll-container`，否则会叠加宿主原生 top inset。在线验收应同时验证唯一 marker 数量、header/frame/thread 几何关系和原生 thread padding 保持。

### Markdown 主题兼容

- Markdown 主题内容根兼容合同包含 `main.main-surface`、`.main-surface` 与 `.thread-scroll-container`，并受扩展 surface 和功能开关门禁约束；不能把某一代 DOM 根再次固化为唯一实现。
- heading、strong、inline code、pre-code reset、顶层及嵌套 blockquote 应复用同一兼容根定义。引用块正文默认继承原生正文色；嵌套引用只复位容器视觉，不重写正文色。
- 当样式节点与开关均正常但真实元素未命中规则时，优先核对当前 DOM 根数量和生成 CSS 作用域，避免把 selector 静默失配误判为配置或注入失败。
- CSS 合同测试应解析完整 selector prelude、按括号深度拆分顶层逗号，再与精确允许集合和数量比较。邻接单行正则会漏掉同义根和换行格式，造成假绿。
- 主题升级验证需组合生成 CSS 回归、旧根/新根正负例、live target/surface 诊断及真实元素 computed-style/匹配规则探针；仅看到 `installed=true` 不代表样式实际生效。

### 输入与焦点增强边界

- IME guard 的 Enter 判断只接受真实 Enter 信号，不能把 `keyCode=229` 的普通组合键单独视为提交；应保留组合输入期间的原生行为，并在组合结束后恢复普通 Enter。
- focus ring 修复只处理顶层布局容器误触边框，不得影响输入框、按钮、菜单、链接等真实控件的焦点可见性。
- 输入增强应复用统一 surface/editor 识别和事件框架。无法唯一识别 editor 或提交语义时失败开放，不以草稿、占位文案或按钮文字补足资格。

### 验证与交付方法

- 严格交付需组合 Core/PageRuntime fixtures、完整 UI 或相应边界测试、Release resource/symbol/privacy scan、签名/安装审计和 current ChatGPT count-only live gate；本地 `installed=true`、静态字符串命中或单个 happy path 都不是完整验收。
- DOM 兼容修复应在 fixture 中覆盖唯一候选、重复候选、隐藏/旁支候选、同节点属性变化、SPA 双向切换和完整卸载；在线再验证真实 target、surface、computed geometry 与 adapter 健康。
- Xcode 多显示器环境可能把真实 `MenuBarExtra` 状态项点击错投。自动化可用复用同一 `StatusMenuView` 的 Debug-only hosting window 验证内容和动作，但不得冒充真实状态项点击与定位验收，也不得进入 Release。
- 构建与安装是不同证据：Release 编译成功后仍需检查资源集合、签名、built/staged/installed 一致性、原子替换、冷启动与存活。未经用户授权不据此自动提交、推送或重启 ChatGPT。

## 已淘汰记录

| 淘汰日期 | 原内容摘要 | 淘汰原因 | 替代内容或来源 |
|---|---|---|---|
| 2026-08-03 | Shell/Node 产品链、`launch.sh`、`inject-current.sh`、`verify.sh` 和交互式配置脚本作为当前架构 | 原生 MenuBarExtra + ExtensionCore + PageRuntime V2 已完成绿色切换，旧发布链已删除 | `SM-019fc76b-6b2c-745d-9c4b-d08639bd0a68` |
| 2026-08-03 | 仅用 grouped CSS selector 同时命中多个 header 兼容根 | 新旧根嵌套会累计 padding | 唯一有序布局根 marker 生命周期 |
| 2026-08-03 | 将 `main.main-surface` 固化为唯一 Markdown 内容根 | ChatGPT DOM 已迁移到 thread scroll 等结构 | surface-guarded 多根兼容合同 |
