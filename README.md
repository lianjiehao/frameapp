# 取景 · FRAME

[简体中文](README.md) | [English](README.en.md)

一款用于学习与研究的构图相机应用：点选主体，获得六种经典构图建议，跟随实时引导调整画面。画面分析在本机完成。

![取景：点选主体、构图建议、对齐拍照与拍照指南](docs/images/frame-overview.png)

## 下载

| 平台 | 下载入口 |
| --- | --- |
| Android | 待补充 APK 下载链接 |
| iOS | 待补充安装或 TestFlight 链接 |

<!-- Replace these placeholders only when a verified build is available. -->
暂无可用下载链接；可按下方步骤自行运行。

## 快速开始

安装 **Flutter 3.47.6**、Git 和 Chrome：

~~~sh
git clone https://github.com/lianjiehao/frameapp.git
cd frameapp
flutter pub get --enforce-lockfile
flutter run -d chrome
~~~

Android 7.0+ 真机运行：`flutter run -d <device-id>`；手机练习模式追加 `--dart-define=DEMO_MODE=true`。iOS 15+ 需要 macOS、Xcode 和自己的开发团队，见 [iOS 配置](docs/ios-setup.zh-CN.md)。帮助与政策页面在本地渲染。

## 开发与贡献

- [应用介绍](docs/app.zh-CN.md)：功能与使用限制。
- [架构说明](docs/architecture.zh-CN.md) · [贡献指南](CONTRIBUTING.md)：源码入口、检查命令与 PR 流程。
- [AI 辅助开发](docs/ai-development.zh-CN.md)：项目规则、任务示例与提交 skill。
- [REA 功能研究](docs/rea.zh-CN.md)：用可选的 `frame-rea` skill 研究自有或已获授权的软件功能。
- [软著申请材料](docs/distribution/README.md)：可按需填写的模板与 PDF 生成工具。

## 法律与许可

代码采用 [MIT](LICENSE)，依赖、字体与素材遵循[各自许可](THIRD_PARTY_NOTICES.md)。功能演示与研究流程面向学习和研究，不限制 MIT 授予的商用、修改或分发权利。

软件按现状提供。使用、研究及分发须核实授权，尊重版权、隐私与肖像权；免责声明不免除法定责任，详见 [使用与许可边界](docs/legal.zh-CN.md)。安全问题见 [SECURITY.md](SECURITY.md)。
