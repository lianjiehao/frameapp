# Architecture

[English](architecture.md) | [简体中文](architecture.zh-CN.md)

## Read the code in this order

1. [main.dart](../lib/main.dart): app startup, consent integration and camera screen.
2. [CameraCoach](../lib/services/coach.dart): a `ChangeNotifier` coordinating phases, camera lifecycle, analysis and capture. The screen listens to its state.
3. [core](../lib/core/): pixel normalization, selected-subject tracking, scene evidence, composition ranking and stability.
4. [platform services](../lib/services/): conditional native/Web photo capture, saving and local policy rendering.

~~~text
Camera / practice image
  → pixel_buffer: orientation, mirror, centered 3:4 crop
  → GrayFrame: tracking at 192×256; scene analysis at 96×128
  → subject_tracking + vision + scene_evidence
  → composition: rank options, choose target, evaluate stability
  → CameraCoach → main.dart + ui/guides.dart
  → camera_photo → gallery (native album / Web download)
~~~

`CapturePhase` in `coach.dart` is `framing → analyzing → recommending → guiding → ready → capturing → captured`. Direct capture, reset, retry, suspension and lost tracking branch from this flow; inspect the controller before changing transitions. Native camera sampling and analysis share one `compute` job, with requests throttled to about 120 ms and only the latest pending frame retained with its original time. The camera crop is area-averaged before reduction to 192×256 so fine foliage does not turn into aliasing noise during small movements. The controller publishes the sampled frame together with its analysis; an expired result cannot restore a live lock or shutter readiness.

## Where to make a change

For a selected subject, the one-second hold means the target center stays inside the visible tracking box (14% of preview width × 13% of preview height). The drawing and readiness check share these dimensions. Small movements within that box continue the timer and retain readiness; there is no separate per-frame displacement gate. Leaving the box, losing the subject, stale frames or strong sensor motion resets the hold. Horizon-only guidance keeps its line tolerance; tilt and composition quality remain advice.

| Change | Source | Tests to start with |
| --- | --- | --- |
| Pixel format, filtered crop, rotation, mirror | `core/pixel_buffer.dart` | `pixel_buffer_test.dart`, `vision_test.dart` |
| Selected-subject tracking / recovery | `core/subject_tracking.dart`, `core/vision.dart` | `tracking_test.dart`, `vision_test.dart` |
| Composition scores / target / readiness | `core/composition.dart`, `core/scene_evidence.dart` | `alignment_test.dart`, `recommendation_test.dart`, `vision_test.dart` |
| Gravity / tilt / shaking | `core/level.dart` | `level_test.dart` |
| Camera flow, saving, stale frames | `services/coach.dart`, `services/camera_photo*.dart`, `services/gallery*.dart` | `widget_test.dart`, `privacy_test.dart` |
| Screen, overlays, guidance copy | `main.dart`, `ui/guides.dart` | `widget_test.dart` + rendered screenshot |
| Photo styles, strength, preview and PNG rendering | `core/photo_filter.dart`, `ui/photo_filters.dart`, `services/coach.dart` | `photo_filter_test.dart` + rendered screenshot |
| Consent / permissions | `services/privacy.dart`, `services/permissions.dart`, `ui/privacy_flow.dart` | `privacy_test.dart` |
| Local policy rendering / navigation | `services/policy_*.dart`, `ui/policy_*.dart` | `policy_content_test.dart`, `privacy_test.dart` |

Source paths in the table are relative to `lib/`; tests are under `test/`. [AGENTS.md](../AGENTS.md) records the behavioral contracts that require regression coverage.

## Photo filters

The filter control shares the existing action row below the viewfinder, without adding a separate row or covering the preview. Camera switching and flash are in the upper-right header beside Help; the header has no photo shortcut. It offers Original, Warm Light, Clear, Film and Monochrome, with adjustable strength. `PhotoFilter` defines local color matrices from saturation, contrast and channel balance. Film adds deterministic procedural grain and a vignette; Monochrome adds a subtle vignette. Strength zero restores the original pixels when manual adjustments are neutral. Presets require no downloaded resources or additional permissions.

Only the photo layer passes through `FilteredPhoto`; guides and text retain their own colors. Tracking and composition continue to use the unfiltered camera samples. Preview and PNG export share the same recipe and normalized texture coordinates. Capture freezes that recipe; changing filters is disabled until the next shot. Saving retries reuse the captured PNG without applying the filter again. An in-flight capture invalidated by suspension cannot publish or save its result.

The same sheet also offers brightness, contrast, saturation and warmth. Their neutral value is zero, displayed on a −100 to +100 scale. These local adjustments compose after the preset's color matrix and before its texture; neutral adjustments preserve the existing preset output. They also work with Original or zero preset strength. Reset clears the four adjustments while keeping the selected style and its strength. All controls remain in the modal sheet, so they add no row below the viewfinder. The capture recipe includes these adjustments and saving retries retain them.

`photo_filter_test.dart` compares rendered preview and export pixels, checks zero strength, monochrome output, cropping/mirroring and save retries. Widget screenshots use the licensed practice image. Native camera textures, front/back camera orientation, gallery output, permission interruption and capture during backgrounding still require real-device verification on Android and iOS; widget rendering does not establish device color or performance parity.

## Generated content and assets

| Output | Source / generation |
| --- | --- |
| `assets/legal/`, `lib/services/policy_pages.g.dart` | `python3 tools/build_policy_pages.py` from policy text in that script and `policies/config.json` |
| `assets/fonts/FrameSans-Regular.ttf` | `tools/update_ui_font.py` subsets a licensed full Noto Sans SC font using current Dart / policy text |
| Build output, plugin registration, local SDK paths | Flutter / platform tooling; keep local artifacts out of Git |

Operator, contact and consent revision are generated from `policies/config.json`. `policy_pages.g.dart` contains the HTML used by native and Web views. The app handles internal document links using the `frame-policy` URI scheme; selected GitHub/mail links open externally.

Do not patch generated policy output directly. Change the source, regenerate, and review the resulting copies together. See [local policy pages](../policies/README.en.md).

For new Chinese UI characters, inspect actual rendering. To rebuild the font, use a virtual environment with `fonttools`, then run `python tools/update_ui_font.py /path/to/NotoSansSC.ttf`. Keep the font license and inspect the diff; changing prose in Markdown does not require rebuilding the UI font.

Licenses for the practice photo and documentation screenshots are listed in [Third-party notices](../THIRD_PARTY_NOTICES.md). Screenshots are presentation assets, not device-test evidence.
