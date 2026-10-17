# 维护者协作流程

[English](community-governance.md) | [简体中文](community-governance.zh-CN.md)

外部贡献者从 Fork 提交 PR 到 `main`，由 `@lianjiehao` 审核后 Squash 合并，保留作者与共同作者署名。所有者可在 PR 合并时豁免审核要求，但仍须通过必需检查并解决讨论；不能直接推送 `main`。

必需检查为 `Code quality`、`Android build` 和 `iOS build`，内容见 [CI](../.github/workflows/ci.yml)。审核要求由 [CODEOWNERS](../.github/CODEOWNERS) 和 [GitHub 仓库规则](https://github.com/lianjiehao/frameapp/rules) 执行。

`owner-*` 为所有者专用分支，包括 `owner-contributors`；其他开发者使用自己的 Fork，或获授写入权限后在主仓库创建普通分支。独立维护 Fork 时，按自己的维护者信息调整 CODEOWNERS 与仓库规则。
