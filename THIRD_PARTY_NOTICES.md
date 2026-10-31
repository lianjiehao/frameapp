# Licenses and bundled assets / 许可与内置素材

| Material / 内容 | License / 许可 |
| --- | --- |
| Project code and documentation / 项目代码与文档 | [MIT](LICENSE); lianjiehao and FRAME contributors. |
| `assets/images/park.jpg` | Bundled sample image, distributed under [MIT](LICENSE). / 内置示例照片，采用 [MIT](LICENSE) 许可证分发。 |
| `docs/images/*.png` | FRAME screenshots, distributed under [MIT](LICENSE). / FRAME 界面截图，采用 [MIT](LICENSE) 许可证分发。 |
| `assets/fonts/DMSerifDisplay-Regular.ttf` | DM Serif Display, SIL Open Font License 1.1; [license](assets/fonts/OFL.txt). |
| `assets/fonts/FrameSans-Regular.ttf` | Subset of Noto Sans SC, SIL Open Font License 1.1; [license](assets/fonts/NotoSansSC-OFL.txt). |
| `assets/reference_templates/*.jpg` | Third-party reference photos, distributed in FRAME's built-in pose library with redistribution permission confirmed by the user; [source and scope](assets/reference_templates/README.md). Not relicensed under MIT. / 第三方参考照片，经用户确认可用于 FRAME 内置姿势图库；[来源与授权范围](assets/reference_templates/README.md)。不因此改为 MIT 许可。 |
| `assets/models/movenet_singlepose_lightning.tflite` | Google MoveNet, Apache-2.0; [source](assets/models/README.md), [license](assets/models/LICENSE). / Android 离线人体检测模型。 |
| `test/fixtures/pose_person.png` | Resized/letterboxed TensorFlow.js pose test photo, Apache-2.0; [provenance](test/fixtures/README.md), [license](test/fixtures/TFJS-LICENSE). Not shipped in the app. / 仅测试使用，不随应用分发。 |

Dependencies keep their own licenses. Direct packages are declared in [pubspec.yaml](pubspec.yaml), resolved versions in [pubspec.lock](pubspec.lock). Review new dependencies and include their required notices in distributions; the project's MIT license does not relicense third-party code or fonts.

依赖保留各自许可证。直接依赖见 [pubspec.yaml](pubspec.yaml)，实际版本见 [pubspec.lock](pubspec.lock)。新增依赖需核对许可，并在分发时保留所需声明；项目 MIT 许可不替代第三方代码和字体的许可。

Android body detection uses Google LiteRT 1.4.0 (Apache-2.0); iOS uses the system Vision framework under Apple platform terms. / Android 人体检测使用 Google LiteRT 1.4.0（Apache-2.0），iOS 使用 Apple 系统 Vision 框架并遵循平台条款。
