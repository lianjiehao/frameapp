# Device and build checks

[English](release-checklist.md) | [简体中文](release-checklist.zh-CN.md)

Use when verifying camera changes or preparing a distribution. Record the commit SHA, device, OS version and observed results; state any untested platforms.

## Device checks

- [ ] No camera activity before privacy consent; permission refusal requires an explicit retry before another request.
- [ ] Subject selection, movement, loss and reselection work; test low light, shaking and fast pans.
- [ ] Front/rear cameras, cropping, orientation, guided capture and direct capture behave correctly.
- [ ] Photos save to the gallery; storage or save failures retain the photo for retry.
- [ ] Background/resume and return from policy pages work; consent withdrawal stops camera/analysis and clears the in-memory photo.
- [ ] Help and policy pages render locally; external links open only on user action.

## Before distribution, if needed

- [ ] Required checks pass; artifacts match the verified commit and have the correct version/build.
- [ ] Use your own signing; artifacts contain no credentials. Policy content and contact details match your version.
- [ ] Retain MIT and third-party notices; new assets have redistribution permission.
