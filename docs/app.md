# FRAME: the app

[English](app.md) | [简体中文](app.zh-CN.md)

FRAME helps you decide where to place a subject before taking a photo. Choose what matters in the frame, compare suggestions, then follow the markers. You remain in control of the composition and shutter.

## Three steps

| 1. Select | 2. Compare | 3. Align and shoot |
| --- | --- | --- |
| <img src="images/select-subject.png" width="220" alt="Select the subject"> | <img src="images/composition-advice.png" width="220" alt="Review composition advice"> | <img src="images/align-and-shoot.png" width="220" alt="Aligned subject ready to shoot"> |
| Tap the subject. A white box means it is being tracked. | View a recommendation, its reason and alternatives. | Keep the green target center inside the subject box for one second, then tap the shutter. Small hand movements within the box are allowed. |

Screenshots show the Chinese UI in practice mode. The app itself is not yet localized into English.

## What it offers

- Six composition options: rule of thirds, centered, symmetry, golden ratio, leading lines and negative space.
- Subject tracking, target markers and direction hints; an in-app photo guide explains the workflow.
- Front/rear camera switching, flash, direct capture and a preview of the most recent shot.
- Clean 3:4 PNG photos without guide overlays. Failed saves can be retried while the captured image remains in memory.
- A practice mode using a bundled photo. In the browser, drag the scene or use automatic alignment, then download the result.

<p align="center">
  <img src="images/six-compositions.png" width="250" alt="Six composition options">
  <img src="images/photo-guide.png" width="250" alt="In-app three-step photo guide">
</p>

## Privacy and control

Live frames and photos are processed on the device, without a cloud recognition service. The app does not require an account or API key. Camera and saving permissions are requested when needed. You can withdraw consent from the privacy screen; photos already saved in the system gallery remain yours to manage.

Help and policy pages ship with the app and render locally. Developers can customize the [policy content](../policies/README.en.md).

## Expectations

Suggestions come from measured image structure and local rules, not semantic object recognition or a trained aesthetic model. Scores compare the available compositions; they do not certify a photo's quality. Low texture, low light, repeated patterns, occlusion or fast movement may lose the subject. Select it again when needed.

The completion signal requires the target to remain inside the subject box for one second; small movements inside it do not restart the timer. Leaving the box, lost tracking, stale frames or strong shaking resets readiness. Level and structural suggestions remain optional. You can also choose direct capture. Android and iOS provide real camera operation; the browser is for practice. Device behavior needs testing on the target phone.

For a reproducible problem, open a [GitHub Issue](https://github.com/lianjiehao/frameapp/issues). Include the app version, device and steps; redact personal information from screenshots.
