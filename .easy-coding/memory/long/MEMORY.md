---
memory_schema: 2
memory_file: MEMORY
last_updated: 2026-05-28
---

# 长期记忆索引

> 本文件只作为索引与读取导航，不承载大量正文。
> 业务事实写入 `BUSINESS.md`，技术/架构/工程事实写入 `TECHNICAL.md`。
> 状态仅使用 `active / deprecated / superseded`；默认分析只读取 `active` 主题。

## 快速导航

| 主题 | 类型 | 关键词 | 详情文件 | 状态 | 最近更新 | 来源 |
|---|---|---|---|---|---|---|
| 项目边界与交付约束 | business | Codex App 本地增强、只读包体、README 同步、兼容入口 | BUSINESS.md | active | 2026-05-28 | legacy long memory |
| 运行时注入架构 | technical | Node.js ESM、Chrome DevTools Protocol、Bash、远程调试端口 | TECHNICAL.md | active | 2026-05-28 | legacy long memory |
| 配置化增强链路 | technical | DEFAULT_CONFIG、配置文件、环境变量、CLI 参数、diagnose | TECHNICAL.md | active | 2026-05-28 | legacy long memory + short memories |
| 当前实例重注入流程 | technical | inject-current.sh、端口发现、/json/version、--diagnose | TECHNICAL.md | active | 2026-05-28 | short memory 1 |
| 输入与布局增强边界 | technical | layoutFocusRingFix、IME guard、tabIndentEnhancement、选择器边界 | TECHNICAL.md | active | 2026-05-28 | short memories 2/3 |
| 配置脚本维护模式 | technical | --configure、config.sh、旧配置补齐、未知字段保留 | TECHNICAL.md | active | 2026-05-28 | short memory 4 |

## 当前重点业务域

- Codex App 本地运行时增强的安全边界和交付约束。

## 当前重点技术域

- `inject-wide-layout.mjs` 作为注入、配置合并、诊断和页面增强的核心入口。
- `inject-current.sh` 作为配置变更后的当前实例重注入入口。
- 宽屏布局、输入行为和主题阅读增强均需保持可配置、可诊断、可回退。

## 读取策略

- 涉及业务概念、字段语义、业务流程、业务规则、上下游契约或业务排障时，读取 `BUSINESS.md`。
- 涉及架构决策、接口决策、工程规则、实现模式、易错点、验证或发布经验时，读取 `TECHNICAL.md`。
- 默认只读取状态为 `active` 的主题；`deprecated` / `superseded` 仅在迁移、冲突排查或用户追溯历史原因时读取。
- 若长期记忆与当前代码或用户最新表达冲突，优先相信当前代码和用户最新表达，并在后续沉淀中更新记忆状态。

## 迁移审计

| 日期 | 来源 | 处理结果 |
|---|---|---|
| 2026-05-28 | legacy long memory | 拆分为 `BUSINESS.md` 的项目边界与 `TECHNICAL.md` 的架构/配置主题 |
| 2026-05-28 | legacy short memories 1-4 | 一次性沉淀可复用技术主题，删除旧版短期文件 |
