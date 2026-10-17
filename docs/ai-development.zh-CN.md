# AI 辅助开发

[English](ai-development.md) | [简体中文](ai-development.zh-CN.md)

## 接入项目规则

在仓库根目录打开项目。架构、隐私约束和检查要求统一维护在 [AGENTS.md](../AGENTS.md)：

| 工具 | 仓库入口 |
| --- | --- |
| Codex | 自动读取 `AGENTS.md` |
| Claude Code | `CLAUDE.md` 导入 `AGENTS.md`；用 `/memory` 查看 |
| Cursor | `.cursor/rules/project.mdc` 引用 `AGENTS.md`；在 Settings → Rules 查看 |

首次修改前让助手确认已加载规则；未加载时直接提供 `AGENTS.md`。

## 任务示例

~~~text
先阅读 AGENTS.md 和 docs/architecture.zh-CN.md。
任务：[问题与复现步骤]；预期：[可验证的结果]。
检查相关源码和测试，局部修改，保留无关改动。
补充回归验证，运行相关检查，汇报实际结果与未验证事项。
~~~

提交前人工审阅 diff；AI 的说明或模拟测试不能替代真机验证。贡献要求见 [贡献指南](../CONTRIBUTING.md#ai-辅助贡献)。

## 提交与推送

说**“提交代码”**即可使用 [frame-commit](../.agents/skills/frame-commit/SKILL.md)。默认包含当前仓库的**全部本地未提交改动**（已暂存、未暂存、未忽略的新文件及先前任务改动）；只有明确指定“仅提交文档”等范围时才缩小。

助手先运行相关检查，预览文件、提交说明、推送仓库／分支和将推送的提交，**确认后才暂存、commit 和 push**。忽略文件和敏感资料不进入提交，发现敏感文件须先处理。

也可使用 Codex 的 `$frame-commit`、Claude Code 的 [`/frame-commit`](../.claude/commands/frame-commit.md) 或 Cursor 识别到的同名 skill。未识别时，直接要求读取上述 skill 文件。

## REA 功能研究

可选的 [frame-rea](../.agents/skills/frame-rea/SKILL.md) 用于研究自有或已获授权的软件功能。安装、调用与版权边界见 [REA 指南](rea.zh-CN.md)。
