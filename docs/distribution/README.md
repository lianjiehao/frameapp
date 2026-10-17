# 软著申请材料

[简体中文](README.md) | [English](README.en.md)

提供软件著作权申请的空白模板，并从当前源码和填写的说明书生成 PDF。开发者可按自己的软件版本和申请要求调整。

## 1. 填写模板

将下列文件复制到已被 Git 忽略的 `docs/software-copyright/`，填写自己的资料，保留仓库中的空白模板：

| 模板 | 用途 |
| --- | --- |
| [申请填写项](templates/copyright-application.md) | 核对申请人、权属、日期等信息 |
| [元数据](templates/copyright-metadata.example.json) | 重命名为 `copyright-metadata.json`，填写软件名、版本、申请人等信息 |
| [软件说明书](templates/software-description.md) | 填写功能、操作、技术实现和数据处理说明 |

## 2. 生成 PDF

安装 Python 的 `reportlab`，准备有使用许可、支持中文的 TTF 字体。在仓库根目录执行，将字体路径替换为实际文件：

~~~sh
python3 tools/build_software_copyright_materials.py \
  --metadata docs/software-copyright/copyright-metadata.json \
  --description docs/software-copyright/software-description.md \
  --font /path/to/licensed-cjk.ttf
~~~

结果保存在 `docs/software-copyright/`：

- `source-materials.pdf`：源码材料，每页 50 行；超过 60 页取前、后各 30 页，否则输出全文。
- `software-description.pdf`：软件说明书。

## 3. 核对材料

检查 PDF 内容与排版，按受理机构要求填写正式申请表。区分上游代码、自己的新增部分和第三方素材，如实填写权属与发表状态；MIT 许可不等于著作权转让。工具仅辅助整理材料，不保证登记通过，详见 [许可说明](../legal.zh-CN.md)。填写后的资料与导出文件不要提交 Git。

其他可选资料：[Android 构建](../android-release.zh-CN.md) · [iOS 开发](../ios-setup.zh-CN.md) · [上架资料模板](templates/store-listing.md)。
