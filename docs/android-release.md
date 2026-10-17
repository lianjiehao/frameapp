# Android builds

[English](android-release.md) | [简体中文](android-release.zh-CN.md)

Use `flutter run` or `flutter build apk --debug` for daily development. The following steps build your own release version.

## Configure

1. Set `applicationId`/`namespace` in `android/app/build.gradle.kts` and update the package declaration/path of `MainActivity.kt`. Set your app name, icon and `pubspec.yaml` version.
2. Create and back up your own signing key. Copy [key.properties.example](../android/key.properties.example) to `android/key.properties` and fill it in. Keep keys and passwords out of Git.
3. Fill in the [policy configuration](../policies/README.en.md) for your version and regenerate local pages.

## Build

~~~sh
flutter pub get --enforce-lockfile
flutter build appbundle --release
flutter build apk --release
~~~

Choose AAB or APK as needed. Missing release signing fails the build without falling back to a debug key. Updates need compatible application identity and signing.

Check the resulting version and signature, then complete the [device and build checks](release-checklist.md).
