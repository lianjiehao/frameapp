# iOS 开发

[English](ios-setup.md) | [简体中文](ios-setup.zh-CN.md)

需要 macOS、与目标设备兼容的完整 Xcode 和 Flutter 3.47.6。工程最低 iOS 15，使用 Swift Package Manager。

## 编译与运行

1. 完成 Xcode 首次启动和平台组件安装；必要时将其选为当前开发工具目录。
2. 在仓库根目录执行：

~~~sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter devices
open ios/Runner.xcworkspace
~~~

3. 在 Runner → Signing & Capabilities 设置自己的开发团队，必要时更换为唯一 Bundle ID；不要提交本机签名变化。
4. 连接并信任 iPhone，按系统要求启用开发者模式，再执行 `flutter run -d <device-id>`。
5. 仅检查编译可用 `flutter build ios --release --no-codesign`，产物不能直接安装。

## 权限插件

保留 `ios/Runner/Info.plist` 中已有的相机、仅添加照片和运动用途说明。通过 Flutter 编译时，权限插件读取该文件。直接从 Xcode 启动而相机授权异常时，将构建环境中的 `PERMISSION_HANDLER_INFO_PLIST` 指向当前仓库 `ios/Runner/Info.plist` 的绝对路径，重新解析 Swift 包。不要用添加麦克风或相册读取权限来绕过问题。

## 真机检查

按 [真机与构建检查](release-checklist.zh-CN.md) 验证相机、权限与保存，在 PR 记录设备、iOS 版本和结果。模拟器或无签名编译不能替代真机验证。
