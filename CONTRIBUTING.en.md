# Contributing to FRAME

[简体中文](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

We welcome reports, fixes, tests, design and documentation translations. Open an Issue before substantial features or architectural changes; small, clear fixes can go straight to a PR.

## Open a pull request

1. Fork the repository and branch from the latest `main`. Keep one issue per PR. Read [architecture](docs/architecture.md) and [AGENTS.md](AGENTS.md).
2. Add regression tests for changed behavior and screenshots for UI changes. Camera, permissions, orientation, saving and lifecycle changes need device results; state untested platforms.
3. Run the checks below and use the [PR template](.github/pull_request_template.md) to describe the problem, changes, validation and limits. Keep credentials, signing files, private photos and build output out of Git.

## How changes are accepted

Target `main`. Required checks and approval from `@lianjiehao` precede squash merging. After review changes, rerun affected checks and resolve discussions. Maintainer rules are in [governance](docs/community-governance.md).

## Checks

Use Flutter 3.47.6 from the repository root:

~~~sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
python3 -m unittest discover -s tools/tests
python3 tools/check_docs.py
~~~

Run documentation checks for docs changes and the relevant checks for code or tooling changes. See the [workflow](.github/workflows/ci.yml) for full CI. After changing policy sources, run `python3 tools/build_policy_pages.py` and include generated outputs.

## AI-assisted contributions

See the [AI guide](docs/ai-development.md) for setup and the commit skill. Review the diff, understand the changes, and briefly describe significant AI assistance and actual validation in the PR. Never fabricate tests or device results, or send secrets and private data to an assistant.

## Attribution and license

Contributions use [MIT](LICENSE). You must have the right to contribute the code and assets and retain [third-party licenses](THIRD_PARTY_NOTICES.md). Credit co-authors with `Co-authored-by: Name <GitHub-linked email>`.

Report security issues privately through [SECURITY.md](SECURITY.md).
