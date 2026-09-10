## 技术方案：修复右上角浮窗遮挡并建立通用宽屏避让机制

### 项目模式
迭代项目，Swift 菜单栏 App + PageRuntime JavaScript。

### 任务类型
Bug 修复，包含有证据的宿主兼容逻辑泛化。

### 需求解析
- **目标**：解决当前右上浮窗覆盖会话正文的问题，降低属性、组件名和容器 class 变化导致的复发概率。
- **输入**：用户截图；当前 ChatGPT 真实运行页；现有 wide-layout 实现及 08-21 修复记录。
- **输出**：修改运行时代码与回归测试，完成验证后构建并安装最新扩展，验证安装后实际浮窗与会话不重叠。
- **边界**：不新增配置或依赖；不改变输入事件、主题和宽度 owner 选择机制；不修改 ChatGPT 包体；不点击、重启宿主或读取正文/草稿/Cookie；保留已有 Harness 升级改动，不提交推送 Git。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：wide-layout 的候选发现、占位判定、几何计算、observer 和缓存；PageRuntime implementation revision；WebKit/FakeDOM 回归。
- **当前实现方式**：先按双 inset class 找右栏 shell，再接受绘制组件或同节点精确双属性 `thread-summary-panel` 占位。水平参考可能选到底部 composer；仅旧精确 PIP 获得特殊纵向判定。
- **现有问题 / 缺口**：当前单属性透明占位被拒绝；同一栏的真实 painted panel 又因不与底部 reference 纵向相交而被拒绝。旧 FakeDOM selector 注册测试未覆盖实际属性拆分。
- **证据**：`wide-layout.js:18-23,203-277,427-453,492-758,778-813,931-979`；`AdapterFixtureTests.swift:324-487,566-1163`；`PageRuntimeTests.swift:590-613`。2026-09-09 只读 CDP 核验 ChatGPT 26.903.61454/build 8378：唯一 layout/scroller、revision 15；浮窗左边界 2244，正文与 composer 右边界 2421.82，重叠 177.82px，offset 0。透明占位 300×282，仅含 `data-pip-obstacle`，全页 home 属性计数 0，painted sibling 与占位同矩形，均位于当前 layout 内的 scroller 旁支。
- **仓库基线**：master，HEAD 与远端 master 均为 `7db7900294205262d073e83dfb9b10d3f6fe76bb`；业务文件无前置未提交差异。

### 冲突摘要
- 需求 vs RULES：无冲突，保留 surface 门禁、隐私、有限观察、差异写入和安装验收要求。
- 需求 vs ABSTRACT：文档仍描述旧双属性逻辑，本次同步最终通用机制。
- 需求 vs 现有代码：以新的实测合同替换精确面板名/双属性特例，保留已验证宽度及原生偏移算法。
- Dev-Spec vs 现有代码：本方案明确修改兼容合同，并更新对应旧测试断言。

### 决策闭环
decision_status: closed
- **已解决问题与结论**：采用通用占位属性存在性、唯一 surface 归属和真实可见几何；语义路径不依赖属性值、home 属性或旧 shell class。保留已有无占位属性的原生 shell+painted 路径，两条统一可见纵向基准。沿用整体内容列避让，正文、Markdown、composer保持一致。候选发现与有效占位分离，并观察已发现节点的有限祖先链。交付包含构建安装与实时数值验证。
- **确认依据**：用户要求修复并尽量通用；当前源码和只读实时几何证明属性变化及纵向基准错误；RULES“任务与开发”要求验证后构建安装。上述技术选择可由证据确定，无需额外产品决策。

### Canonical Spec 来源
- **来源定位**：无。
- **设计 / 文档摘要**：无。
- **共享执行状态**：无。
- **选择任务 / 仓库**：无。
- **消费闭包**：无。
- **基线与冲突**：无。
- **待闭合 integration**：无。

### 影响面分析
- **涉及模块**：PageRuntime 与 adapters、CDP 与 target 的版本合同、测试架构与项目说明。
- **核心类 / 页面 / 接口**：wide-layout 候选/占位/观察函数；CDPPageRuntimeBridge implementationRevision。
- **数据库变更**：无。
- **接口变更**：无外部接口、配置或诊断结构变更。
- **关联历史任务**：08-21-fix-environment-panel-overlap；短记忆 SM-01a022f5-7f3b-748b-9ad7-5294f74ea63e。

### 改动范围

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `CodexAppExtension/Resources/Adapters/wide-layout.js` | 修改 | 保持 UTF-8，依据 file -I | 通用占位发现、统一可见纵向参考、可见链与动态观察 |
| `PageRuntimeTests/AdapterFixtureTests.swift` | 修改 | 保持 ASCII 兼容，依据 file -I | 内联真实 HTML 执行完整 adapter；更新 FakeDOM 合同与负例 |
| `CodexAppExtension/Resources/PageRuntime/bootstrap.js` | 修改 | 保持 ASCII，依据 file -I | implementationRevision 16 |
| `CodexAppExtension/Core/CDP/CDPPageRuntimeBridge.swift` | 修改 | 保持 UTF-8，依据 file -I | implementationRevision 16 |
| `CodexAppExtensionTests/CDPPageRuntimeBridgeTests.swift` | 修改 | 保持 UTF-8，依据 file -I | revision 合同断言 |
| `README.md` | 修改 | 保持 UTF-8，依据 file -I | 最终行为与兼容边界 |

知识同步另更新 `.easy-coding/ABSTRACT.md` 的 PageRuntime 模块；不将 Harness 产物当作源码改动对象。

### 修改方案
- **总体改法**：从“特定面板的特殊规则”改为“已确认会话区域内的语义占位与可见几何合同”。
- **后端改动**：仅同步 Swift bridge 的 runtime revision；不改变连接、进程和配置流程。
- **前端改动**：
  1. 在唯一 layoutRoot 内查找 `[data-pip-obstacle]`，不比较属性值；排除 scroller 正文、当前 editor/width-owner 分支、瞬态 role 路径和不属于当前 surface 的节点。使用右侧相交几何排除跨页 header 与底部 composer。透明、childless、pointer-events:none 不构成拒绝理由。
  2. 语义节点直接测自身矩形与到 layoutRoot 的完整可见链；不要求它有绘制后代。可见性使用实际 display/visibility/opacity/有效矩形，aria-hidden 仅触发重新判断，不单独等同视觉隐藏。
  3. 保留既有原生 shell+painted 检测。把水平居中参考和纵向可见区域分开：纵向统一取 surface/layout 与 viewport 的交集，body 与 shell 均不再使用底部 composer 的 Y 区间。直接语义占位沿用实际组件的最小尺寸要求，不强加满高 shell 的高度门槛。
  4. 两条路径合并时取最左有效占位边界，不累计预留宽度；保留当前 `layoutState` 可用宽度、最小侧边距与 native/residual offset 公式。
  5. 候选集合在可见性过滤前进入 identity；隐藏候选保持观察。layoutRoot 子树仅监听 `data-pip-obstacle` 属性发现新增/删除，已发现候选及其有限祖先观察影响定位/可见性的属性、尺寸和动画。变化置 dirty，下一合并帧重新计算；普通正文 mutation 保持身份快路。监听目标去重，删除、切 surface 与卸载完整清理。`diagnose` 和 `reconcile` 使用同一识别合同。
- **兼容处理**：当前单属性、旧双属性、占位值改名或旧 shell class 移除均使用同一语义路径；已有无标记 painted panel 使用统一纵向计算。无全页逐节点扫描或推测性拓扑备用路径。
- **风险点**：瞬态标记误收缩、祖先变化漏观察、重复观察与多次偏移；以结构负例、动态真实 DOM、性能及卸载回归控制。

### 实施拆解

| 单元 | 说明 | 类型 | 仓库 / 来源任务 / 步骤 | 涉及文件 / 符号 | 依赖 | 验收条件 | 测试点 / 命令 | 跨单元契约 |
|------|------|------|----------------------|-----------------|------|---------|---------------|-----------|
| U1 | 通用占位避让、动态收敛、真实回归与版本同步 | frontend/runtime+test+docs | 当前仓库 / 无 / 无 | 上述文件；candidate/record/geometry/observer/reconcile/diagnose | — | 非重叠、关闭恢复、负例不误缩、性能清理、安装后通过 | T1–T9；精确命令见 test-strategy.md | 保留 surface/width/native offset 和隐私合同 |

**执行策略**：single，一个连贯实现单元；独立子代理审查与验证。

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 当前拓扑、属性/class更名、短顶部面板、动态开关及范围负例 | 必测 | U1 | 真实 WKWebView 执行完整 runtime/adapter；先证明旧实现失败 | `xcodebuild ... -only-testing:ExtensionCoreTests/AdapterFixtureTests`，完整命令见同目录 test-strategy.md |
| 快路径、合并调度、native offset、预算与卸载 | 必测 | U1 | FakeDOM 计数器与现有生命周期回归 | 同目录 test-strategy.md 的定向命令 |
| 全量Core、语法、plist与差异范围 | 必测 | U1 | 自动验证 | 同目录 test-strategy.md 的完整Core与静态命令 |
| Release安装、资源一致性及当前页面实际几何 | 必测 | U1 | 构建/安装审计、只读CDP数值 | `./install.sh`；重新发现动态端口后运行隐私受限探针 |

- **人工验收**：真实浮窗开合、滚动、窗口缩放和无闪烁；不以模拟测试声称人工交互已验证。
- **无法验证项**：尚未发布的宿主版本不存在可验证环境；本次仅承诺已覆盖的变化类别。当前宿主可只读测量，真实未呈现状态以真实 WebKit 动态用例验证并如实标明范围。

### Workflow Mode
- **项目配置**：adaptive。
- **Session 覆盖**：无。
- **机械最低模式**：fast，state API 返回 single-bounded-unit。
- **推荐并选择**：standard。
- **选择原因**：单仓单单元虽满足机械 fast 下限，但这是重复发生的外部宿主兼容故障，用户明确要求通用性；需真实WebKit、影响范围回归及安装后实时几何，采用 standard。
- **状态内执行差异**：IMPLEMENT 按一个完整单元实施；QUALITY 独立正确性/兼容/性能审查与影响模块验证，包含完整Core和安装live；MEMORY 按最终证据归档。允许用户在机械下限与项目硬门禁内调整到 fast，或提高到 strict；验证合同不随选择弱化。

### 风险与注意事项
- 通用标记若未来被用于瞬态区域，仍需结构、定位、完整可见链与role负例共同限制。
- 未来宿主同时移除语义标记和已知原生结构时，不能保证自动适配；本次消除已证实的具体面板名/双属性/纵向特例依赖，不作永久兼容承诺。
- 安装只替换扩展自身包；保留 ChatGPT 运行状态和已有工作树修改。
