# AI-assisted development

[English](ai-development.md) | [简体中文](ai-development.zh-CN.md)

## Load project rules

Open the repository root. [AGENTS.md](../AGENTS.md) is the shared source for architecture, privacy constraints and checks:

| Tool | Repository entry |
| --- | --- |
| Codex | Reads `AGENTS.md` automatically |
| Claude Code | `CLAUDE.md` imports `AGENTS.md`; inspect with `/memory` |
| Cursor | `.cursor/rules/project.mdc` references `AGENTS.md`; inspect in Settings → Rules |

Before the first edit, ask the assistant to confirm the rules are loaded. Supply `AGENTS.md` directly if needed.

## Example task

~~~text
Read AGENTS.md and docs/architecture.md first.
Task: [problem and reproduction steps]; expected: [verifiable result].
Inspect related code and tests, make a focused fix, and preserve unrelated changes.
Add regression coverage, run relevant checks, and report results and untested items.
~~~

Review the diff yourself before submitting. AI explanations or simulated tests cannot replace device verification. See [contribution requirements](../CONTRIBUTING.en.md#ai-assisted-contributions).

## Commit and push

Say **“提交代码”** or **“commit code”** to use [frame-commit](../.agents/skills/frame-commit/SKILL.md). The default is **all local uncommitted changes** in this repository: staged, unstaged, non-ignored new files and earlier tasks' work. Only an explicit request such as “commit only docs” narrows the scope.

The assistant runs relevant checks and previews files, the message, destination repository/branch and outgoing commits. **Staging, committing and pushing require confirmation of that preview.** Ignored files and sensitive records stay out of commits; sensitive-file blockers must be resolved first.

You can also use Codex's `$frame-commit`, Claude Code's [`/frame-commit`](../.claude/commands/frame-commit.md), or the discovered skill in Cursor. If it is not recognized, ask the assistant to read the skill file directly.

## REA feature research

The optional [frame-rea](../.agents/skills/frame-rea/SKILL.md) skill researches features of software you own or are authorized to examine. See the [REA guide](rea.md) for setup, usage and rights boundaries.
