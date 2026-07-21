# 测试策略：ChatGPT 已运行时 launch.sh 分支修复

## 可测试性分类

| Change | Kind | Verdict | Reason |
|---|---|---|---|
| 调试端口 HTTP 终检与候选选择 | Shell utility | [must-test] | 输入候选端口、输出首个可用端口，分支结果可通过命令桩稳定断言。 |
| app bundle 与原始主进程名解析 | Shell utility | [must-test] | 直接决定破坏性分支目标，必须保留 plist 尾随字符并在进程操作前完成 bundle/control/长度终检。 |
| 进程名 19 字节门禁、字面 ERE 与三态运行检测 | Shell utility | [must-test] | macOS 非 `-f` 模式对超过 19 字符的名称静默失败，必须显式拒绝而非误判未运行。 |
| `Y/y` 立即强制终止分支 | Destructive state transition | [must-test] | 本次 Bug 修复核心路径，必须断言只有显式确认才调用强制终止。 |
| 已有 CDP 端口直接注入分支 | Launch orchestration | [must-test] | 本次 Bug 修复核心路径，必须断言不提示、不终止、不重复启动。 |
| 首次启动且无运行进程分支 | Launch orchestration | [should-test] | 现有行为需要保持，适合通过可替换 Shell 函数验证调用顺序。 |
| README | Documentation | [no-test] | 无运行时逻辑，通过人工对照实现与 `git diff --check` 检查。 |

## 测试点

| ID | 归属单元 | 测试场景 | 期望结果 | 验证命令 |
|---|---|---|---|---|
| T1 | U4/U5 | 配置端口或发现端口通过 `/json/version` | 选择该端口并直接注入；不调用确认、强制终止或 `open`。 | `./verify.sh` |
| T2 | U4/U5 | 无可用 CDP、主进程正在运行、输入 `Y` | 精确主进程收到立即强制终止；确认旧进程消失后以回环 CDP 参数启动并注入。 | `./verify.sh` |
| T3 | U4/U5 | 无可用 CDP、主进程正在运行、输入 `y` | 与大写 `Y` 相同，大小写兼容。 | `./verify.sh` |
| T4 | U4/U5 | 无可用 CDP、主进程正在运行、输入其他值或空输入 | 安全取消；不终止、不启动、不注入。 | `./verify.sh` |
| T5 | U4/U5 | 无可用 CDP、主进程正在运行、stdin 非 TTY | 明确返回非零并提示需交互确认；不进入破坏性分支。 | `./verify.sh` |
| T6 | U4/U5 | 无可用 CDP、主进程未运行 | 保留首次启动路径，等待配置端口就绪后注入。 | `./verify.sh` |
| T7 | U4/U5 | 候选监听端口无法返回有效 `/json/version` | 不将其视为 CDP，不执行误注入。 | `./verify.sh` |
| T8 | U5 | 修改后的全部 Shell、Node 生成代码、surface guard、bundle 锚点与 Git 空白 | 既有统一验证全部通过。 | `./verify.sh` |
| T9 | U4/U5 | PlistBuddy 返回正常 `ChatGPT` 加工具换行 | 哨兵捕获只移除工具生成的一次行终止，得到精确 `ChatGPT`。 | `./verify.sh` |
| T10 | U4/U5 | 原始 `CFBundleExecutable` 自身含尾随/嵌入 CR/LF、以 `-` 开头或为空 | 返回安全错误；不调用真实或桩化的 pgrep、pkill、open、注入。 | `./verify.sh` |
| T11 | U4/U5 | 进程名字节长度分别为 19 和 20（C locale） | 19 字节允许并字面转义；20 字节返回安全错误，避免 macOS 静默未匹配。 | `./verify.sh` |
| T12 | U4/U6 | 显式 `CODEX_APP` 指向错误/正确 bundle id | 错误 bundle 在任何破坏动作前失败；正确 `com.openai.codex` 保持最高路径优先级；README/ABSTRACT 契约一致。 | `./verify.sh` |

## 不测试项及原因

- README 与 ABSTRACT 为说明性内容，不增加独立自动测试；通过实现对照、文件编码检查与 `git diff --check` 验证。
- 不在自动测试中向真实 ChatGPT/Codex 发送强制终止信号；测试使用 Shell 函数桩记录调用，避免破坏当前会话与用户状态。

## 人工验收

- 在已暴露 CDP 的 ChatGPT/Codex 实例中运行 `./launch.sh`，确认脚本直接注入，当前窗口不重启。
- 在普通方式启动、未暴露 CDP 的实例中运行 `./launch.sh`，先输入非 `Y` 确认应用保持运行，再重新执行并输入 `Y`，确认应用被强制终止后以调试模式重启并进入增强 Codex。
- 核对提示文字明确说明：`Y/y` 可能丢失未发送文本和运行中状态。

## 当前环境无法验证项

- 无法在本任务承载的 ChatGPT/Codex 实例内自动执行真实 `Y` 强制重启；这会终止当前任务界面与会话。VERIFICATION 仅执行全量离线回归，以及在现有 CDP 可用时执行非破坏性 `--diagnose`。
- 当前环境的 `pgrep` 进程读取受系统沙箱限制；精确进程识别由命令桩回归覆盖，真实进程行为留在人工验收中确认。
