# AGENTS.md

## 输出语言

本项目的一切输出（回复、文档、issue、提交信息、代码注释）一律使用中文。术语按 `CONTEXT.md` 中的定义使用。

## Agent skills

### Issue tracker

本仓库的 issue 以 markdown 文件形式存放在 `.scratch/<feature>/` 下。详见 `docs/agents/issue-tracker.md`。

### Triage labels

五个规范角色，标签字符串与角色同名（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。详见 `docs/agents/triage-labels.md`。

### Domain docs

单上下文（single-context）：仓库根目录的 `CONTEXT.md` + `docs/adr/`。详见 `docs/agents/domain.md`。
