"""Build self-contained policy documents for local app rendering."""
import html
import json
from pathlib import Path
from policy_config import validate_config

PROJECT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((PROJECT / 'policies/config.json').read_text())
validate_config(CONFIG)
OUTPUT = PROJECT / 'assets/legal'
OUTPUT.mkdir(parents=True, exist_ok=True)
OPERATOR = html.escape(CONFIG['operator'])
EMAIL = html.escape(CONFIG['email'])
VERSION = html.escape(CONFIG['version'])
TEMPLATE_NOTICE = '<p class="meta">发布者应按实际版本填写运营者、联系方式与数据处理说明。</p>'
FOOTER = f'{OPERATOR}<br><a href="mailto:{EMAIL}">{EMAIL}</a>'

CSS = '''
:root{color-scheme:light;--ink:#172019;--muted:#576158;--paper:#f5f5ef;--acid:#d9f77e;--line:#d8ddd1}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:28px}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.85 "PingFang SC","Noto Sans CJK SC","Microsoft YaHei",sans-serif}
a{color:inherit;text-underline-offset:4px;overflow-wrap:anywhere}a:hover{color:#3f6019}a:focus-visible{outline:3px solid #608b2e;outline-offset:4px}
.wrap{max-width:820px;margin:auto;padding:28px 28px 56px}header{display:flex;align-items:baseline;justify-content:space-between;gap:20px;border-bottom:1px solid var(--line);padding-bottom:18px}.brand{font:italic 34px/1 Georgia,serif;text-decoration:none;letter-spacing:-2px}.brand span{font:12px/1.5 sans-serif;letter-spacing:3px;margin-left:14px;color:var(--muted)}.eyebrow{font-size:11px;letter-spacing:2px;color:var(--muted)}h1{font-size:clamp(30px,6vw,46px);letter-spacing:-1px;line-height:1.3;margin:34px 0 12px}h2{font-size:21px;line-height:1.5;margin:30px 0 12px}h3{font-size:17px;margin:20px 0 8px}p{margin:10px 0}small,.meta{font-size:12px;color:var(--muted)}.summary{background:var(--acid);border-radius:3px;padding:20px 22px;margin:24px 0;font-size:17px;line-height:1.8}.summary p{margin:0}.toc{display:flex;flex-wrap:wrap;gap:8px 18px;padding:18px 0;border-bottom:1px solid var(--line);font-size:13px}section{border-bottom:1px solid var(--line);padding-bottom:22px}ul,ol{padding-left:22px;margin:12px 0}li{margin:7px 0}table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.8}th,td{padding:12px 10px;text-align:left;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-weight:500}.table-scroll{overflow:auto}.sensitive{font-weight:700}nav{display:flex;gap:16px;flex-wrap:wrap;margin:25px 0;font-size:13px}.index-links{display:grid;gap:0}.index-links a{display:flex;justify-content:space-between;padding:20px 0;border-bottom:1px solid var(--line);text-decoration:none;font-size:19px}.index-links a span{font-size:20px;color:#638221}footer{margin-top:34px;color:var(--muted);font-size:12px;line-height:1.8}.contact{overflow-wrap:anywhere}@media(max-width:480px){.wrap{padding:24px 20px 40px}.eyebrow{letter-spacing:1px}h1{margin-top:28px}th,td{padding:10px 8px;min-width:95px}.summary{padding:18px}body{font-size:15px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
'''


def section(anchor, title, content):
    return f'<section id="{anchor}"><h2>{title}</h2>{content}</section>'


privacy = section('operator', '01 · 谁提供这个服务', f'''
<p>「取景 · FRAME」由{OPERATOR}运营。本政策适用于取景 App 中的拍照、构图建议、主体跟踪、照片保存，以及应用内的说明页面。</p>
<p>隐私联系邮箱：<a href="mailto:{EMAIL}">{EMAIL}</a>。本版本不要求注册或登录，没有广告、云端照片分析或第三方统计服务。</p>''')
privacy += section('data', '02 · 使用哪些信息', '''
<h3>取景与构图</h3><p>开启相机后，App 在设备内处理<span class="sensitive">实时相机画面、你点选的主体位置与画面特征</span>，用于显示预览、跟踪主体和推荐构图。取景画面可能包含人像等敏感内容；请留意画面中的他人隐私。App 不进行身份识别，不建立人脸档案，也不会把这些画面传到服务器。退出取景或撤回同意后，停止相机和画面分析，清除当前跟踪状态。</p>
<h3>拍照与保存</h3><p>按快门后，App 在设备内生成照片。相机产生的临时文件在读取后尝试删除；当前照片暂存于 App 内，以便预览或在保存失败后重试。成功保存的照片存放在系统相册，由你通过系统相册管理和删除。App 不扫描、读取或上传相册中的其他照片，不在照片中写入 GPS 位置。撤回同意会清除 App 中当前照片的内存副本，不会删除你已保存到系统相册的照片。</p>
<h3>水平提示</h3><p>取景时读取设备的加速度／重力方向，显示水平和仰俯姿态提示；这些读数在设备内即时使用，不建立运动历史或上传服务器。</p>
<h3>本机设置</h3><p>在 App 私有存储内保存你是否同意本政策、同意的政策版本、权限申请是否已提示等设置，以避免重复打扰。这些记录不包含账号、通讯录或广告标识符，不上传服务器。撤回同意会删除同意记录；卸载 App 可清除本机设置，具体以系统行为为准。</p>
<h3>内置说明与外部链接</h3><p>帮助与政策页面随应用提供，在设备内渲染。你主动点击 GitHub 或邮件链接时，会打开系统浏览器或邮件程序，由相应服务处理你的访问或邮件内容。分享问题或截图前，请遮挡私人信息。</p>''')
privacy += section('permissions', '03 · 权限由你决定', '''
<ul><li><strong>相机：</strong>用于实时取景和拍照。首次进入真实取景前说明用途，再请求系统授权。拒绝后无法使用真实相机，但仍可查看指南、政策并使用练习模式。</li>
<li><strong>保存照片：</strong>仅在保存照片且系统确实需要权限时说明并申请。iOS 使用仅添加照片权限；旧版 Android 可能需要存储写入权限，新版 Android 按系统相册接口保存。拒绝后不影响已经拍下的照片在 App 内暂存，可稍后主动重试保存。</li>
<li><strong>运动传感器：</strong>在同意政策并进入真实取景后使用，提供水平提示。若设备不支持或不可用，不妨碍直接拍照。</li></ul>
<p>不会申请定位、通讯录、电话、短信、麦克风或广告跟踪权限。同意隐私政策不等于授予系统权限；你可分别拒绝或撤销授权。详情见<a href="/permissions">权限使用说明</a>。</p>''')
privacy += section('thirdparty', '04 · 第三方组件', '''
<p>App 使用 Flutter、相机、照片保存、传感器、网页显示和本机设置等开源组件完成对应功能。具体名称、用途和提供方见<a href="/sdk">第三方组件清单</a>。本版本没有广告、统计、推送或云端照片识别组件。</p>''')
privacy += section('rights', '05 · 如何管理和撤回', f'''
<p>你可在系统设置中管理相机和保存照片权限，在 App 的「拍照指南 → 隐私与权限」中查阅本政策或撤回同意。撤回后立即停止取景和传感器读取，返回告知页；已保存的照片继续由你管理。</p>
<p>你可通过 <a href="mailto:{EMAIL}">{EMAIL}</a> 提出访问、更正、删除或其他隐私请求。请说明问题及必要的核验信息，无需发送原始照片；实际运营者应补充处理渠道与回复时限，并依法处理。由于照片与取景分析留在你的设备，我们无法远程调取这些照片。发送邮件时，你的邮箱地址和邮件内容会由邮件服务商处理，我们仅用于回复与处理你的请求。</p>''')
privacy += section('children', '06 · 未成年人与信息安全', '''
<p>未成年人应在监护人指导下使用；未满 14 周岁的用户应由监护人阅读本政策并同意。请避免拍摄、传播侵犯他人隐私的内容。</p><p>请保护自己的设备和相册。若发生与个人信息有关的安全事件，实际发布者应按适用规定采取处理措施并通知。</p>''')
privacy += section('updates', '07 · 政策版本', '''
<p>页面顶部标明政策版本。涉及处理目的、信息种类、共享对象或权限范围等重大变化时，发布者应同步更新应用中的说明，并在实施相应变化前重新征求必要的同意。同意隐私政策不等于授予系统权限。</p>''')

permissions = '''<div class="table-scroll"><table><thead><tr><th>项目</th><th>何时使用</th><th>拒绝后的影响</th></tr></thead><tbody>
<tr><td>相机</td><td>同意政策后，首次使用真实取景时。用于预览、拍照与构图分析。</td><td>真实取景不可用；练习模式、指南和政策仍可查看。</td></tr>
<tr><td>添加／保存照片</td><td>保存拍下的照片时，且系统确实要求授权。iOS 仅添加照片；旧版 Android 为存储写入。</td><td>照片保留在 App 当前页面，可主动重试；退出或重启前请留意尚未保存的照片。</td></tr>
<tr><td>运动传感器</td><td>真实取景期间，读取加速度／重力方向用于水平提示。</td><td>水平提示可能不可用；不阻止直接拍照。</td></tr>
</tbody></table></div>'''
permissions += section('manage', '管理权限', '''<p>在手机系统设置中找到「取景」，分别开启或关闭相机、照片保存等权限。App 的「拍照指南 → 隐私与权限 → 系统权限设置」也可打开对应设置页。</p><p>拒绝后不会在下次启动时反复申请。你主动点击重新开启相机或重新保存时，App 才再次说明并尝试授权；系统不允许再次弹窗时，可自行前往设置。</p>''')
permissions += section('excluded', '不会申请这些权限', '''<p>定位、麦克风、通讯录、电话、短信、广告跟踪。本版本只拍照，不录制音视频；不要求读取整个相册。</p>''')

SDK_ROWS = [
('Flutter', 'Google / Flutter 开源项目', '界面与本机运行', '渲染与运行所需的设备环境；本版本不主动上传'),
('camera', 'Flutter 官方插件', '相机预览与拍照', '系统相机画面、临时照片、相机设备信息；本机处理'),
('gal', 'Gal 开源项目', '把拍下的照片保存到相册', '你拍下的照片、系统保存权限状态；本机处理'),
('sensors_plus', 'Flutter Community / Plus Plugins', '显示水平与仰俯提示', '加速度／重力方向；本机即时使用'),
('shared_preferences', 'Flutter 官方插件', '记住政策同意与提示状态', '政策版本、同意状态和提示状态；本机保存'),
('permission_handler', 'Baseflow 开源项目', '查询和申请相机权限、打开系统设置', '系统权限状态；本机使用'),
('webview_flutter', 'Flutter 官方插件', '在 App 内渲染说明页面', '应用内 HTML 与系统 WebView 环境；本机展示'),
('url_launcher', 'Flutter 官方插件', '打开用户选择的 GitHub 或邮件链接', '你主动选择的链接；由系统处理'),
]
sdk = '<div class="table-scroll"><table><thead><tr><th>组件</th><th>提供方</th><th>用途与信息</th></tr></thead><tbody>'
sdk += ''.join(f'<tr><td>{html.escape(a)}</td><td>{html.escape(b)}</td><td>{html.escape(c)}。{html.escape(d)}</td></tr>' for a,b,c,d in SDK_ROWS)
sdk += '</tbody></table></div><p>部分组件包含平台实现与间接依赖，均用于上述功能。本版本没有广告、统计、推送或云端照片识别组件。随功能变化会同步更新清单。</p>'

terms = section('service', '01 · 服务与使用', f'''<p>{OPERATOR}提供取景、构图建议、主体跟踪和照片保存功能。你可自行决定采用哪种构图，也可直接拍照。</p><p>构图分数用于比较当前候选方案，不保证审美上的唯一最优结果。主体跟踪可能因遮挡、低光、缺乏纹理或快速移动失败，拍摄前请确认画面与主体。</p>''')
terms += section('content', '02 · 照片与权利', '''<p>你拍摄的照片由你管理；使用本 App 不会把你的照片所有权转让给我们。请确保拍摄和使用照片符合当地法律，并尊重被拍摄者的隐私、肖像权及其他合法权益。不要使用 App 制作或传播违法内容。</p><p>项目代码按 MIT 许可提供，第三方字体、依赖与素材保留各自许可。研究用途说明不限制 MIT 的修改、分发或商用权利，也不授权侵犯第三方版权、隐私或肖像权。软件按现状提供，免责声明不排除法律不得排除的责任。</p>''')
terms += section('availability', '03 · 保存与设备', '''<p>App 的主要拍照功能在本机运行。设备、系统权限、存储空间和相机状态可能影响运行。保存失败时会显示提示；请在离开当前页面或退出 App 前确认重要照片已保存。本版本不提供云端备份。</p><p>本版本无需登录，也没有广告。</p>''')
terms += section('changes', '04 · 更新与联系', f'''<p>我们可修复问题并更新功能。涉及个人信息处理的变化按<a href="/privacy">隐私政策</a>处理。请通过 <a href="mailto:{EMAIL}">{EMAIL}</a> 反馈问题。</p><p>实际发布者应根据运营地区补充适用法律、争议处理与联系方式。法律赋予用户的权利不因本模板而受到限制。</p>''')

support = section('contact', '联系取景', f'''<p>运营者：{OPERATOR}</p><p>客服与隐私邮箱：<a class="contact" href="mailto:{EMAIL}">{EMAIL}</a></p><p>反馈时请描述手机型号、系统版本和复现步骤。通常不需要发送照片；若需提供截图，请先遮挡个人或他人信息。</p>''')
support += section('faq', '常见问题', '''<h3>为什么推荐构图按钮是灰色的？</h3><p>先点一下想拍的主体。白框出现并成功锁定后，按钮才可使用；跟丢时请重新点选。</p><h3>照片没有保存？</h3><p>检查系统相册权限和可用空间，再点「重新保存」。在确认保存前，请保留当前页面。</p><h3>如何管理授权？</h3><p>在「拍照指南 → 隐私与权限」中打开系统权限设置，或撤回隐私同意。</p>''')

PAGES = {
    'privacy': ('隐私政策', '你的画面，留在你的设备。', privacy),
    'permissions': ('权限使用说明', '只在需要时申请，由你分别决定。', permissions),
    'sdk': ('第三方组件清单', '了解每个组件的用途和处理范围。', sdk),
    'terms': ('用户协议', '拍摄由你决定，照片由你管理。', terms),
    'support': ('帮助与联系', '遇到问题，告诉我们。', support),
}

for path in OUTPUT.glob('*.html'):
    if path.stem not in {*PAGES, 'index'}:
        path.unlink()

for slug, (title, summary, content) in PAGES.items():
    links = ''.join(f'<a href="/{key}">{label}</a>' for key,(label,_,_) in PAGES.items() if key != slug)
    meta = f'<p class="meta">版本 {VERSION} · 更新与生效日期 {VERSION}</p>'
    doc = f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="color-scheme" content="light"><meta name="referrer" content="no-referrer"><title>{title} · 取景 FRAME</title><style>{CSS}</style></head><body><main class="wrap"><header><a class="brand" href="/">frame<span>取景</span></a><span class="eyebrow">{title}</span></header><h1>{title}</h1>{meta}{TEMPLATE_NOTICE}<div class="summary"><p>{summary}</p></div>{content}<nav aria-label="更多说明">{links}</nav><footer>{FOOTER}</footer></main></body></html>'''
    (OUTPUT / f'{slug}.html').write_text(doc)

index_links = ''.join(f'<a href="/{slug}">{title}<span aria-hidden="true">↗</span></a>' for slug,(title,_,_) in PAGES.items())
(OUTPUT / 'index.html').write_text(f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><meta name="viewport" content="width=device-width,initial-scale=1"><title>隐私与帮助 · 取景 FRAME</title><style>{CSS}</style></head><body><main class="wrap"><header><a class="brand" href="/">frame<span>取景</span></a><span class="eyebrow">隐私与帮助</span></header><h1>安心取景，<br>自在拍照。</h1>{TEMPLATE_NOTICE}<div class="summary"><p>相机画面与构图分析在设备内处理，照片不上传。<br>在这里查阅说明，或联系我们。</p></div><div class="index-links">{index_links}</div><footer>{FOOTER}</footer></main></body></html>''')
# Compile the same HTML documents for native and browser rendering.
def dart_string(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n').replace('\r', '\\r') + "'"

bundled = PROJECT / 'lib/services/policy_pages.g.dart'
bundled.write_text('// Generated by tools/build_policy_pages.py. Do not edit.\n'
                   + 'const policyOperator = ' + dart_string(CONFIG['operator']) + ';\n'
                   + 'const policyEmail = ' + dart_string(CONFIG['email']) + ';\n'
                   + 'const policyRevision = ' + dart_string(CONFIG['version']) + ';\n'
                   + 'const Map<String, String> policyPages = {\n'
                   + ''.join('  ' + dart_string(path.stem) + ':\n      ' + dart_string(path.read_text()) + ',\n'
                             for path in sorted(OUTPUT.glob('*.html')))
                   + '};\n')
print(f'Built {len(PAGES) + 1} local policy documents.')
