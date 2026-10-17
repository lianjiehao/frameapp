# 本地政策页面

[简体中文](README.md) | [English](README.en.md)

隐私、权限、组件、协议和帮助页面使用应用内 HTML，在 Android／iOS 的 WebView 和 Web 的内嵌页面中渲染。页面间跳转由应用处理；GitHub 与邮件链接仅在点击时交给浏览器或邮件程序。

## 修改与生成

- `config.json`：运营者、联系邮箱和政策版本日期。发布者按实际服务填写。
- [生成器](../tools/build_policy_pages.py)：政策正文与样式。

在仓库根目录运行：

~~~sh
python3 tools/build_policy_pages.py
python3 -m unittest discover -s tools/tests
~~~

产物为 `assets/legal/*.html` 和 `lib/services/policy_pages.g.dart`，一起提交，不直接编辑。原生与 Web 共用生成的页面内容；WebView 不可用时显示同一内容的可选择文本。

修改数据用途或权限时，同步更新正文与版本，并在必要时重新征求同意。模板可按实际发布需求调整，修改遵循 [贡献指南](../CONTRIBUTING.md)。
