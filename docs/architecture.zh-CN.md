# 架构说明

[English](architecture.md) | [简体中文](architecture.zh-CN.md)

## 建议阅读顺序

1. [main.dart](../lib/main.dart)：应用启动、同意流程接入和相机页面。
2. [CameraCoach](../lib/services/coach.dart)：通过 `ChangeNotifier` 统筹阶段、相机生命周期、分析与拍照，页面监听状态。
3. [core](../lib/core/)：像素归一化、选中主体跟踪、画面证据、构图排序与稳定判断。
4. [平台服务](../lib/services/)：通过条件导入区分原生／Web 的拍照、保存和本地政策渲染。

~~~text
相机／练习图像
  → pixel_buffer：方向、镜像、3:4 居中裁剪
  → GrayFrame：192×256 跟踪；96×128 画面分析
  → subject_tracking + vision + scene_evidence
  → composition：候选排序、目标选择、稳定判断
  → CameraCoach → main.dart + ui/guides.dart
  → camera_photo → gallery（原生相册／Web 下载）
~~~

`coach.dart` 中的 `CapturePhase` 为 `framing → analyzing → recommending → guiding → ready → capturing → captured`。直接拍照、重置、重试、挂起及跟丢会分叉；调整阶段前先读控制器。原生相机采样与分析在同一个 `compute` 任务中完成，约每 120 ms 请求一次，忙碌时只保留最新待处理帧及其原始采样时间。相机裁剪区域先做面积加权平均，再缩小到 192×256，避免细枝、草叶在轻微移动时产生混叠噪点。控制器同时更新采样画面和分析结果；已经过期的结果不能恢复实时锁定或拍照就绪。

## 改动定位

选中主体后的“一秒保持”指目标中心持续位于可见跟踪框内（取景宽度的 14% × 高度的 13%）。绘制和就绪判定共用这一尺寸。框内轻微移动继续计时并保留就绪状态。目标出框、主体跟丢、画面过期或传感器检测到剧烈晃动时重置计时。横向分界引导按线条容差判断；倾斜和构图质量仍属于建议。

| 改动 | 源码 | 优先查看的测试 |
| --- | --- | --- |
| 像素格式、滤波裁剪、方向、镜像 | `core/pixel_buffer.dart` | `pixel_buffer_test.dart`、`vision_test.dart` |
| 主体跟踪与恢复 | `core/subject_tracking.dart`、`core/vision.dart` | `tracking_test.dart`、`vision_test.dart` |
| 构图评分、目标和完成条件 | `core/composition.dart`、`core/scene_evidence.dart` | `alignment_test.dart`、`recommendation_test.dart`、`vision_test.dart` |
| 重力、倾斜与晃动 | `core/level.dart` | `level_test.dart` |
| 相机流程、保存、过期帧 | `services/coach.dart`、`services/camera_photo*.dart`、`services/gallery*.dart` | `widget_test.dart`、`privacy_test.dart` |
| 页面、叠层和引导文案 | `main.dart`、`ui/guides.dart` | `widget_test.dart` + 实际渲染截图 |
| 照片滤镜、强度、预览与 PNG 绘制 | `core/photo_filter.dart`、`ui/photo_filters.dart`、`services/coach.dart` | `photo_filter_test.dart` + 实际渲染截图 |
| 隐私同意与权限 | `services/privacy.dart`、`services/permissions.dart`、`ui/privacy_flow.dart` | `privacy_test.dart` |
| 本地政策渲染与跳转 | `services/policy_*.dart`、`ui/policy_*.dart` | `policy_content_test.dart`、`privacy_test.dart` |

源码相对 `lib/`，测试位于 `test/`。[AGENTS.md](../AGENTS.md) 记录了需要持续回归保护的行为约束。

## 照片滤镜

滤镜入口与取景框下方的已有操作行共用空间，不新增独立行，也不遮挡预览。切换镜头和闪光灯位于页面右上方、帮助按钮旁，顶部不设照片入口。滤镜提供原图、暖光、清透、胶片和黑白，支持调整强度。`PhotoFilter` 根据饱和度、对比度和通道平衡定义本地色彩矩阵。胶片额外绘制确定性的程序颗粒和暗角，黑白带轻微暗角；手动调节均为中性值时，样式强度归零会恢复原始像素。预设不需要下载资源或新增权限。

只有照片层经过 `FilteredPhoto`，引导线和文字保留各自颜色；跟踪与构图仍使用未调色的相机采样。预览和 PNG 导出共用同一配方及归一化纹理坐标。快门按下时固定配方，下一张照片前禁用滤镜修改；保存重试直接复用已拍摄的 PNG，不再次叠加滤镜。挂起时失效的进行中拍摄不能再发布或保存结果。

同一面板还提供亮度、对比度、饱和度和冷暖调节，中性值为零，界面显示范围为 −100 至 +100。本地调节合成在样式色彩矩阵之后、纹理之前；全部归零时保留样式输出。选择原图或将样式强度归零后仍可调节；重置只清除四项调节，保留样式及其强度。控件全部放在弹出面板内，不增加取景框下方的行数。拍照时固定的配方包含这些调节，保存重试仍使用同一成片。

`photo_filter_test.dart` 对比预览与导出像素，覆盖零强度、黑白输出、裁剪／镜像和保存重试。组件截图使用已有许可的练习照片。原生相机纹理、前后镜头方向、相册成片、权限中断及拍摄中切到后台仍须在 Android 和 iOS 真机验证；组件渲染不能证明设备上的色彩或性能一致性。

## 生成内容与素材

| 产物 | 来源与生成方式 |
| --- | --- |
| `assets/legal/`、`lib/services/policy_pages.g.dart` | `python3 tools/build_policy_pages.py`；正文在脚本中，配置在 `policies/config.json` |
| `assets/fonts/FrameSans-Regular.ttf` | `tools/update_ui_font.py` 根据 Dart／政策文本，从有许可的完整 Noto Sans SC 字体生成子集 |
| 构建目录、插件注册和本机 SDK 路径 | Flutter／平台工具生成，本机构建产物不提交 Git |

运营者、联系方式与同意版本由 `policies/config.json` 生成。`policy_pages.g.dart` 提供原生与 Web 共用的 HTML。应用通过 `frame-policy` URI 处理页面间跳转；点击 GitHub／邮件链接时才打开外部程序。

不要直接修改生成的政策副本。修改源文件后重新生成，一起审阅和提交副本，见 [本地政策页面](../policies/README.md)。

新增中文界面字符后检查实际显示。需要补字时，在虚拟环境安装 `fonttools`，执行 `python tools/update_ui_font.py /path/to/NotoSansSC.ttf`，保留字体许可并核对差异。只改 Markdown 文档无需重建界面字体。

练习照片和文档截图的许可见 [第三方与素材说明](../THIRD_PARTY_NOTICES.md)。展示截图不能代替真机验证记录。
