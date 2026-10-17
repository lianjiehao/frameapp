# Android 构建

[English](android-release.md) | [简体中文](android-release.zh-CN.md)

日常开发使用 `flutter run` 或 `flutter build apk --debug`。以下步骤用于构建自己的发布版本。

## 配置

1. 设置 `android/app/build.gradle.kts` 中的 `applicationId`／`namespace`，同步 `MainActivity.kt` 的包声明与目录；修改名称、图标和 `pubspec.yaml` 版本号。
2. 创建并备份自己的签名密钥，将 [key.properties.example](../android/key.properties.example) 复制为 `android/key.properties` 并填写。私钥和密码不提交 Git。
3. 按实际版本填写 [政策配置](../policies/README.md) 并重新生成本地页面。

## 构建

~~~sh
flutter pub get --enforce-lockfile
flutter build appbundle --release
flutter build apk --release
~~~

按需选择 AAB 或 APK。缺少发布签名时构建会失败，不回退到调试密钥。后续更新需保持应用标识与签名兼容。

构建后核对版本与签名，并完成 [真机与构建检查](release-checklist.zh-CN.md)。
