## 技术方案：修复 ChatGPT 已运行时 launch.sh 卡住并支持确认重启

### 修订摘要
- 第 4 轮修复后验收发现 `CFBundleExecutable` 仍会在命令替换中丢失尾随换行，且 macOS `pgrep` / `pkill` 的短进程名存在 19 字符边界；依据 3 轮 fix 上限，REVIEW 已自动退回 ANALYSIS 重规划。
- 用户确认过的产品行为保持不变：已有 CDP 直注入；无 CDP 且应用运行时，仅精确 `Y/y` 立即强杀并调试重启；其他输入、非交互、探测异常均失败安全。
- 重规划保留单一 name-based 识别链：使用哨兵保真读取 plist 值，只移除 PlistBuddy 自身的一个行终止符，在任何进程操作前拒绝控制字符、选项形名称和超过 19 字节的名称，再进行字面 ERE 转义。
- 显式 `CODEX_APP` 与自动发现候选均继续要求 bundle id `com.openai.codex`；README 与架构摘要同步这一已落地的安全契约。

### 项目模式
迭代项目

### 任务类型
Bug 修复

### 需求解析
- **目标**：让 `launch.sh` 在 ChatGPT/Codex 已运行时先识别现有 CDP 能力；有可用调试端口则直接注入，无调试端口则通过明确的 `Y` 确认完成强制重启，避免当前无条件等待约 30 秒后失败。
- **输入**：`launch.sh` 启动请求、配置端口与进程发现得到的候选端口、当前应用主进程状态，以及交互终端中的 `Y/y` 或其他输入。
- **输出**：交付形态为改代码。已有可用 CDP 端口时选择该端口并直接调用注入器；应用已运行但没有可用 CDP 端口时询问是否强制重启，仅 `Y/y` 触发对精确主进程的立即强制终止、确认进程已消失、调试模式重启和注入；其他输入取消且不终止应用；非交互终端无法确认时明确报错。
- **边界**：不修改 ChatGPT/Codex 应用包体、账号数据或历史会话；不新增公网监听、配置项或 CLI 参数；不对 helper 模糊匹配；按用户确认，`Y/y` 分支不尝试正常退出或等待正常退出，直接发出强制终止信号，但仍需短暂确认旧进程确已退出后才能安全重启。

### 现状
- **相关代码 / 页面 / 接口 / 模块**：`lib/runtime.sh` 集中应用 bundle、主进程、Node 与端口能力；`launch.sh` 已实现三分支状态机；`inject-current.sh` 复用统一 CDP 终检；`verify.sh` 已形成零依赖的启动与失败安全回归。
- **当前实现方式**：`launch.sh` 已先复用通过 `/json/version` 的配置/发现端口，再按主进程三态决定确认重启或正常启动，并显式传播两条注入失败（`launch.sh:143-265`）。`lib/runtime.sh` 已执行字面 ERE 转义、`pgrep -x` 三态探测、`pkill -KILL -x` 与有界退出确认（`lib/runtime.sh:60-163`）。
- **现有问题 / 缺口**：`resolve_codex_main_process_name` 通过命令替换读取 plist，Shell 会剥离所有尾随换行，使异常原始值可能在控制字符校验前被归一化（`lib/runtime.sh:51-58`）；当前进程名校验也未覆盖 macOS 非 `-f` 模式的 19 字符上限（`lib/runtime.sh:60-90`）。此外，显式 app bundle 校验已在代码落地（`lib/runtime.sh:27-35`），架构摘要已在本轮 ANALYSIS 校正为统一 bundle id 终检，但 README 的用户契约仍待 U6 同步。
- **证据**：本机 `pgrep(1)` 明确写明“不使用 `-f` 时名称超过 19 字符会静默失败”；当前 `/Applications/ChatGPT.app` 的 PlistBuddy 输出字节为 `43 68 61 74 47 50 54 0a`，即 `ChatGPT` 加工具行终止符。现有 25 组回归已覆盖确认、端口、三态进程、强杀、最终复核与注入失败，但没有从原始 plist 输出贯穿到 launch 的尾随控制字符和第 19/20 字节边界（`verify.sh:110-1378`）。

### 冲突摘要
- 需求 vs RULES：无冲突。继续保持 macOS Bash 3.2、回环 CDP、运行时职责集中和 README/ABSTRACT 同步。
- 需求 vs ABSTRACT：无剩余冲突。架构摘要已记录三分支和精确进程强杀，并在本轮 ANALYSIS 校正为显式路径与自动发现候选执行相同 `com.openai.codex` 终检。
- 需求 vs 现有代码：核心行为已落地；剩余冲突是 name-based 精确匹配在原始 plist 尾随字符和 macOS 19 字节边界上仍未失败安全。
- Dev-Spec vs 现有代码：重规划不引入路径/PID 第二条识别链，只补齐现有 `CFBundleExecutable -> pgrep/pkill` 链的输入保真与平台上限，避免扩大架构和回归面。

### 影响面分析
- **涉及模块**：运行时发现、启动与当前实例、验证、用户启动文档。
- **核心类 / 页面 / 接口**：`lib/runtime.sh` 的应用进程/端口辅助函数，`launch.sh` 启动状态机，`inject-current.sh` 的端口可用性复用，`verify.sh` 的 Shell 行为回归用例。
- **数据库变更**：无。
- **接口变更**：有用户可见的 CLI 交互与兼容终检变化，但无新增参数或环境变量；`launch.sh` 在“已运行且无 CDP”时新增 `Y/y` 强制重启确认，配置端口必须为 1–65535，显式 `CODEX_APP` 也必须是 bundle id `com.openai.codex` 的有效 app bundle。
- **关联历史任务**：`SM-20260710-004`（ChatGPT-Codex 兼容适配）。

### 背景数据应用
- `.easy-coding/ABSTRACT.md:11-34` 将 `launch.sh`、`lib/runtime.sh`、`inject-current.sh` 定义为同一启动/发现链，决定继续修补集中式 name-based 辅助函数，而不是新增路径/PID 平行实现。
- `RULES.md` 要求最终 app bundle、Node 能力和 `/json/version` 决定是否继续；本方案保留显式路径优先级，但显式与自动 app 候选都执行相同 bundle id 终检。
- 本机 `pgrep(1)` 的 19 字符说明成为新的 macOS 平台边界；测试策略必须覆盖 19 字节通过、20 字节拒绝，以及尾随 CR/LF 不被命令替换吞掉。

### 改动范围
> 只列真实项目源码/配置文件的改动。禁止把 `.easy-coding/` 下的 harness 产物（dev-spec / execution.jsonl / test-strategy / 记忆 / 报告等）当作改动对象。本表为空仅允许用于"用户明确要求的无代码交付形态"；代码类任务（重构/修复/功能）若此表为空，即为自我降级。

| 改动文件 | 改动类型 | 文件编码 | 改动核心内容 |
|----------|---------|---------|-------------|
| `lib/runtime.sh` | 修改 | 保持原编码 UTF-8，依据：`file -I lib/runtime.sh` | 集中增加调试端口终检、应用主进程名解析、精确运行检测与立即强制终止辅助函数。 |
| `launch.sh` | 修改 | 保持原编码 UTF-8，依据：`file -I launch.sh` | 保留可回归测试的三分支状态机，并在任何探测/强杀/open 前消费经过原始值与平台边界校验的进程名。 |
| `inject-current.sh` | 修改 | 保持原编码 US-ASCII，依据：`file -I inject-current.sh` | 复用 `lib/runtime.sh` 的调试端口终检函数，保持原端口优先级和行为不变。 |
| `verify.sh` | 修改 | 保持原编码 US-ASCII，依据：`file -I verify.sh` | 完整覆盖三分支、失败安全、原始 plist 控制字符、19/20 字节进程名边界和零真实破坏动作。 |
| `README.md` | 修改 | 保持原编码 UTF-8，依据：`file -I README.md` | 更新启动流程、确认风险、端口范围，以及显式/自动 app 候选统一 bundle id 终检。 |

### 修改方案
- **总体改法**：保留已实现的“直接注入 / 确认强制重启 / 正常首次启动”三分支；在 `lib/runtime.sh` 用哨兵包裹 PlistBuddy 输出，命令替换后先移除哨兵、再只移除工具生成的一个行终止符，从而保留异常尾随字符供校验。随后拒绝 CR/LF 等控制字符、以 `-` 开头及按 C locale 计算超过 19 字节的名称，再做字面 ERE 转义并调用 `pgrep -x` / `pkill -KILL -x`。
- **后端改动**：不涉及。
- **前端改动**：不涉及页面代码；仅改变 macOS Shell 启动交互。
- **兼容处理**：继续支持显式 `CODEX_APP`、系统/用户 `ChatGPT.app`、旧 `Codex.app`、`CODEX_APP_EXTENSION_PORT` / `CODEX_WIDE_PORT` 和默认 `9229`；所有 app 候选统一验证 `com.openai.codex`。当前 `ChatGPT` / `Codex` 名称均低于 19 字节，不受新平台门禁影响。
- **风险点**：`Y/y` 仍会立即强制终止并可能丢失状态；异常/超长 bundle executable 将在任何进程探测、确认、强杀或 open 前失败，而不是回退 `-f` 或模糊匹配。哨兵解码必须只移除工具生成的一个换行，不能再次引入 Shell 尾随换行归一化。

### 实施拆解

| 单元 | 说明 | 类型 | 涉及文件 | 依赖 |
|------|------|------|---------|------|
| U4 | 收口运行时原始进程名读取、19 字节平台门禁并保持三分支状态机 | shell/runtime | `lib/runtime.sh`、`launch.sh`、`inject-current.sh` | — |
| U5 | 补齐原始 plist 与 macOS 进程名边界的零依赖回归 | test | `verify.sh` | U4 |
| U6 | 同步显式/自动 app bundle 与端口用户契约 | docs | `README.md` | U4 |

**执行策略**：parallel
- 第一批：U4 收口运行时安全边界
- 第二批并行：U5 补齐回归；U6 同步用户契约

### 测试策略

| 测试点 | 级别 | 归属单元 | 方式 | 验证命令 |
|--------|------|---------|------|---------|
| 发现任一可用 CDP 端口时直接注入，且不提示、不终止、不重复启动 | 必测 | U4/U5 | Shell 函数桩回归 | `./verify.sh` |
| 应用已运行且无 CDP 时，`Y/y` 立即调用精确强制终止，再以配置端口启动并注入 | 必测 | U4/U5 | Shell 函数桩回归 | `./verify.sh` |
| 非 `Y/y` 输入取消，不终止、不启动、不注入 | 必测 | U4/U5 | Shell 函数桩回归 | `./verify.sh` |
| 需要确认但 stdin 非 TTY 时明确失败，不进入破坏性分支 | 必测 | U4/U5 | Shell 函数桩回归 | `./verify.sh` |
| 原始 `CFBundleExecutable` 含尾随/嵌入 CR/LF、以 `-` 开头或超过 19 字节时，在任何 pgrep/pkill/open 前失败 | 必测 | U4/U5 | 保真读取与底层命令桩回归 | `./verify.sh` |
| 19 字节字面名称可精确转义，20 字节名称按 macOS 平台边界拒绝 | 必测 | U4/U5 | C locale 字节边界回归 | `./verify.sh` |
| Bash 3.2 语法、Node 注入器、surface guard、应用 bundle 与 Git 空白检查不回归 | 必测 | U5 | 既有统一验证 | `./verify.sh` |

- **人工验收**：一是在已带 CDP 端口的 ChatGPT/Codex 实例中运行 `./launch.sh`，确认直接注入且窗口不重启；二是在普通方式启动且无 CDP 的实例中运行 `./launch.sh`，确认出现风险提示，输入非 `Y` 保持现状，输入 `Y` 后应用被强制终止并以调试模式重新进入增强 Codex。
- **无法验证项**：当前任务运行在 ChatGPT/Codex 本身，自动执行真实 `Y` 强制重启会终止承载本任务的应用与会话，因此 VERIFICATION 只做全量离线回归和非破坏性在线诊断；真实强制重启分支留给用户在交付后人工验收。

### 风险与注意事项
- `Y/y` 是明确的破坏性确认：实现将直接发送强制终止信号，不走正常退出等待；提示必须写明可能丢失未发送文本和运行中状态。
- 进程操作必须使用保真读取且通过控制字符、选项形名称和 19 字节平台门禁的 `CFBundleExecutable`，再进行字面 ERE 全名匹配；不能用 `-f` 或宽泛的 `ChatGPT|Codex` 模糊杀进程。
- 显式 `CODEX_APP` 只保留路径优先级，不绕过 bundle id 终检；无效 bundle 必须在任何破坏动作前失败。
- 端口发现结果仍需通过 `http://127.0.0.1:{port}/json/version` 终检，不能仅凭 `lsof` 就执行注入。
- 仓库现有 `.agents/skills/ec-git/SKILL.md`、`.claude/skills/ec-git/SKILL.md`、`.easy-coding/config.yaml`、`.easy-coding/install-manifest.json` 未提交改动来自 harness 升级，本任务不得覆盖或回退。
