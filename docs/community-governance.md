# Maintainer workflow

[English](community-governance.md) | [简体中文](community-governance.zh-CN.md)

External contributors submit PRs from forks to `main`. After review by `@lianjiehao`, squash merge while retaining author and co-author attribution. The owner may bypass review requirements when merging a PR, but must still pass required checks and resolve discussions. Direct pushes to `main` are blocked.

Required checks are `Code quality`, `Android build` and `iOS build`; see [CI](../.github/workflows/ci.yml). Review is enforced by [CODEOWNERS](../.github/CODEOWNERS) and the [GitHub repository rules](https://github.com/lianjiehao/frameapp/rules).

The `owner-*` branches, including `owner-contributors`, are reserved for the owner. Other developers use forks, or ordinary branches in the main repository if granted write access. Independently maintained forks should configure CODEOWNERS and repository rules for their own maintainers.
