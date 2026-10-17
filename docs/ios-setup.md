# iOS development

[English](ios-setup.md) | [简体中文](ios-setup.zh-CN.md)

Requires macOS, full Xcode compatible with your target device, and Flutter 3.47.6. The project targets iOS 15+ and uses Swift Package Manager.

## Build and run

1. Finish Xcode's first launch and platform-component installation. Select it as the active developer directory if needed.
2. From the repository root, run:

~~~sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter devices
open ios/Runner.xcworkspace
~~~

3. In Runner → Signing & Capabilities, select your own development team and, when needed, a unique Bundle ID. Do not commit local signing changes.
4. Connect and trust your iPhone, enable Developer Mode if required, then run `flutter run -d <device-id>`.
5. Use `flutter build ios --release --no-codesign` for a compilation check; its output cannot be installed directly.

## Permission plugin

Keep the existing camera, add-only photos and motion usage descriptions in `ios/Runner/Info.plist`. When building through Flutter, the permission plugin reads this file. If launching directly from Xcode and camera authorization fails, configure the build environment's `PERMISSION_HANDLER_INFO_PLIST` to the absolute path of your checkout's `ios/Runner/Info.plist`, then resolve Swift packages again. Do not add microphone or photo-library read permissions to bypass the problem.

## Verify on a phone

Use the [device and build checks](release-checklist.md) to verify the camera, permissions and saving. Record the device, iOS version and results in the PR. Simulator or unsigned builds do not replace device verification.
