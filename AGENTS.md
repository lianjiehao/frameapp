# Working on FRAME

Shared repository instructions for coding agents. Human onboarding: [简体中文](README.md) | [English](README.en.md). Read [architecture](docs/architecture.md) and the relevant source/tests before changing behavior.

## Task skills

When the user asks **提交代码** (or an equivalent commit request), automatically use [frame-commit](.agents/skills/frame-commit/SKILL.md); no skill name is required. The default scope is **all local uncommitted changes in this repository**: staged, unstaged, added, deleted, renamed and non-ignored untracked files, including earlier tasks' work. Do not ask which files to include or restrict the scope to the latest task unless the user explicitly narrows it. Preview the complete scope, message, checks, destination and outgoing commits, then wait for confirmation before staging, committing or pushing. Respect ignore rules and surface sensitive-file blockers. Editing these rules or finishing ordinary coding work does not itself trigger a submission.

For REA-based feature research or extension, use [frame-rea](.agents/skills/frame-rea/SKILL.md). REA is optional; establish target authorization, keep private research artifacts out of Git, and implement from a sanitized behavioral specification. Never promise complete legal immunity.

## Scope and workflow

- Inspect the current diff first. Preserve unrelated and uncommitted work.
- Implement the requested behavior with a focused diff. Follow nearby patterns; avoid speculative layers, unrelated rewrites, new state-management packages, or dependency upgrades.
- Use Flutter 3.47.6 and `flutter pub get --enforce-lockfile`. Deliberate dependency changes must update `pubspec.yaml` and `pubspec.lock` together and explain their purpose.
- Fix behavior at its owning layer. UI belongs in `lib/main.dart` / `lib/ui/`, orchestration in `lib/services/`, and image/composition logic in `lib/core/`. Keep native I/O behind the existing conditional imports.
- For a behavior change, add or update a meaningful regression near the affected tests. Reuse `CameraCoach` injection points: `previewFrames`, `levelEvents`, `now` and `saver`. Do not rely on arbitrary wall-clock sleeps or weaken assertions to get green checks.
- Follow the user's language in explanations. Keep identifiers in English and current UI copy in Chinese unless the task explicitly changes localization.

## Behavior that must remain true

- No camera, sensor or permission activity before privacy consent. Withdrawal stops capture/analysis and clears the in-memory photo; it does not delete photos already saved to the gallery.
- Permission prompts are contextual. A rejection requires an explicit retry; do not add microphone, location, photo-library read access, analytics or image uploads as an incidental fix.
- Help and policy documents render from generated in-app HTML. Keep document navigation local and external links user-initiated.
- Web is practice-only. Phone practice mode uses `DEMO_MODE=true`. Do not activate a browser camera while fixing mobile behavior.
- Pixels, preview, tap coordinates and capture share orientation, mirroring and centered 3:4 cropping. Respect native row/pixel strides. Tracking uses 192×256 frames; scene analysis uses 96×128 frames.
- The selected subject stays the selected subject. Do not silently substitute automatic detections; hide the visible tracking box when lost. Recommendation requires a valid selection and a fresh frame.
- Guidance readiness needs alignment and one second of stability. Lost tracking, stale frames and shaking revoke readiness. Level, symmetry, leading-line and negative-space suggestions are advice, not extra shutter gates.
- Keep native analysis off the UI thread; preserve latest-frame scheduling and original sample timestamps. Do not accumulate a stale frame queue.
- Captured PNGs contain no guides. Keep captured bytes when saving fails so the user can retry. Report success only after saving succeeds.
- Treat composition scores as rule-based comparisons, not a trained aesthetic score. Do not invent confidence, benchmarks or device results.

If a request intentionally changes one of these contracts, identify the change, update the affected tests and docs, and explain it in the PR.

## Distribution authority

- Ordinary contributor work is local development, debug builds and PRs. Independent distributors use their own identity, accounts, policies and signing; templates are in `docs/distribution/`. No contributor may act for the upstream owner or request the owner’s credentials.
- A commit/push request or approval does not authorize release builds with official credentials, deployment, store uploads or publication. Keep these actions out of frame-commit and ordinary CI; owner release work needs an explicit request for that action.
- Keep private signing files, passwords, profiles and store API keys outside Git and tool output. The checked-in signing code and placeholder example are not credentials. Android development uses a local debug key; iOS device testing uses the contributor’s own development team.
- Do not claim MIT prohibits independent forks or redistribution. Official account/key access and authority to act for the owner are separate from the code license.

## Generated files and assets

- Completed store/copyright forms stay outside Git or in ignored `docs/software-copyright/`; only sanitized blank templates are shared.
- Do not hand-edit `assets/legal/` or `lib/services/policy_pages.g.dart`. Their generator is `tools/build_policy_pages.py`; configuration is in `policies/config.json`.
- Changes require the review defined by [.github/CODEOWNERS](.github/CODEOWNERS) and [CONTRIBUTING.md](CONTRIBUTING.md). Keep generated policy documents synchronized with their sources.
- New Chinese UI text may need missing glyphs added to `assets/fonts/FrameSans-Regular.ttf` via `tools/update_ui_font.py` and a licensed full Noto Sans SC source. See architecture; do not replace the font without checking its license and rendered text.
- Keep README.md and CONTRIBUTING.md as the default Chinese entries, with linked README.en.md and CONTRIBUTING.en.md counterparts. Keep all English/Chinese pairs synchronized, including commands and links. Document headers contain only their own language links; keep body links relevant to the topic. Do not add personal workstation paths, historical local test diaries, release archives or signing material to public docs.

## Validation and handoff

For Dart changes:

~~~sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
~~~

For repository tooling: `python3 -m unittest discover -s tools/tests`. For docs/rules: `python3 tools/check_docs.py`. When changing policy sources as an authorized maintainer, regenerate their outputs and inspect the complete generated diff. Full PR checks are in [.github/workflows/ci.yml](.github/workflows/ci.yml).

Use targeted tests while iterating, then the relevant complete checks. UI changes need screenshots. Camera, permissions, orientation, gallery and lifecycle changes need real-device verification; if unavailable, say so and list the exact manual check still needed. Do not describe simulated input or a Web preview as device testing.

Before handing off, review the diff. Report changed behavior/files, commands actually run and outcomes, and remaining limitations. Do not claim tests passed unless observed. Never commit secrets, private photos, generated builds or machine-specific configuration. Commit, push, deploy and publish only within the user's requested scope.
