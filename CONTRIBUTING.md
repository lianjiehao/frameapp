# 参与 FRAME

[简体中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

欢迎问题反馈、修复、测试、设计和文档翻译。较大功能或架构调整先开 Issue，小而明确的修复可直接提交 PR。

## 提交 PR

1. Fork 仓库，从最新 `main` 建立分支，一个 PR 解决一个问题。先读 [架构说明](docs/architecture.zh-CN.md) 和 [AGENTS.md](AGENTS.md)。
2. 行为变化补充回归测试，界面变化附截图。相机、权限、方向、保存或生命周期变化附真机结果，注明未验证的平台。
3. 运行下方检查，按 [PR 模板](.github/pull_request_template.md) 说明问题、改动、验证与限制。不提交凭据、签名文件、私人照片或构建产物。

## 代码如何被采用

PR 提交到 `main`，通过必需检查并获得 `@lianjiehao` 审核批准后 Squash 合并。根据审查意见修改时，重跑相关检查并解决讨论。维护者规则见 [协作说明](docs/community-governance.zh-CN.md)。

## 提交前检查

使用 Flutter 3.47.6，在仓库根目录执行：

~~~sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
python3 -m unittest discover -s tools/tests
python3 tools/check_docs.py
~~~

文档改动运行文档检查；代码和工具改动运行对应检查。完整 CI 见 [工作流](.github/workflows/ci.yml)。修改政策源文件后须运行 `python3 tools/build_policy_pages.py` 并提交生成结果。

## AI 辅助贡献

接入和提交 skill 见 [AI 开发指南](docs/ai-development.zh-CN.md)。提交者须审阅 diff、理解改动，并在 PR 简述主要 AI 辅助部分与实际验证结果；不要虚构测试或真机结果，也不要向助手提供密钥和私人数据。

## 署名与许可

贡献适用 [MIT](LICENSE)，提交者须拥有代码与素材的贡献权利，并保留 [第三方许可](THIRD_PARTY_NOTICES.md)。共同作者可填写 `Co-authored-by: 姓名 <与 GitHub 关联的邮箱>`。

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告。
