import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/privacy.dart';
import '../services/policy_pages.g.dart' show policyOperator, policyEmail;
import '../services/permissions.dart';
import 'policy_view.dart';

class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, this.consent, required this.builder});
  final PrivacyConsent? consent;
  final Widget Function(PrivacyConsent) builder;
  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> {
  late final PrivacyConsent consent;
  bool declined = false;
  @override
  void initState() {
    super.initState();
    consent = widget.consent ?? PrivacyConsent();
    consent.addListener(_changed);
    if (!consent.loaded) consent.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    consent.removeListener(_changed);
    if (widget.consent == null) consent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!consent.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (consent.accepted) return widget.builder(consent);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'frame',
                    style: TextStyle(fontFamily: 'Editorial', fontSize: 48),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    declined ? '准备好后，再开始取景' : '开始前，了解你的隐私',
                    style: const TextStyle(fontSize: 26, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '运营者：$policyOperator。\n\n'
                    '• 相机画面只在手机内用于构图和主体跟踪，不上传照片。\n'
                    '• 相机和保存照片权限会分别说明、按需申请，你可以拒绝。\n\n'
                    '请阅读以下说明。同意后才会开启取景；你可以随时撤回同意。',
                    style: TextStyle(height: 1.8, fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    children: [
                      for (final doc in [
                        PolicyDocument.privacy,
                        PolicyDocument.terms,
                        PolicyDocument.permissions,
                      ])
                        TextButton(
                          onPressed: () => openPolicy(context, doc),
                          child: Text(doc.title),
                        ),
                    ],
                  ),
                  if (declined)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '相机与传感器保持关闭，你仍可查阅上面的说明。',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  if (consent.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        consent.error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('privacy-accept'),
                      onPressed: consent.saving ? null : consent.accept,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 17),
                      ),
                      child: Text(consent.saving ? '正在保存…' : '同意并开始'),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      key: const Key('privacy-decline'),
                      onPressed: consent.saving
                          ? null
                          : () => setState(() => declined = true),
                      child: const Text('暂不使用'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void openPolicy(BuildContext context, PolicyDocument document) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PolicyPage(document: document)),
  );
}

class PolicyPage extends StatefulWidget {
  const PolicyPage({super.key, required this.document});
  final PolicyDocument document;
  @override
  State<PolicyPage> createState() => _PolicyPageState();
}

class _PolicyPageState extends State<PolicyPage> {
  late String _path = widget.document.path;
  String get _title => _path == 'index'
      ? '隐私与帮助'
      : PolicyDocument.values.firstWhere((doc) => doc.path == _path).title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: PolicyView(
      document: widget.document,
      onPageChanged: (path) {
        if (mounted && _path != path) setState(() => _path = path);
      },
    ),
  );
}

class PrivacyHub extends StatelessWidget {
  const PrivacyHub({super.key, required this.consent});
  final PrivacyConsent consent;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('隐私与权限')),
    body: ListView(
      children: [
        for (final document in PolicyDocument.values)
          ListTile(
            title: Text(document.title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPolicy(context, document),
          ),
        if (!kIsWeb)
          ListTile(
            title: const Text('系统权限设置'),
            subtitle: const Text('管理相机与照片保存权限'),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () => DevicePermissions().openSettings(),
          ),
        const Divider(),
        ListTile(
          key: const Key('privacy-withdraw'),
          title: const Text('撤回同意'),
          subtitle: const Text('停止取景，清除当前照片的内存副本'),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('撤回隐私同意？'),
                content: const Text('取景和水平提示将停止，未保存的当前照片会清除。已经存入相册的照片会保留。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('继续使用'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('撤回同意'),
                  ),
                ],
              ),
            );
            if (confirmed != true || !context.mounted) return;
            // Close covering routes before the gate replaces the camera page.
            Navigator.of(context).popUntil((route) => route.isFirst);
            await consent.withdraw();
          },
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '隐私联系：$policyEmail\n同意版本：${PolicyDocument.revision}',
            style: TextStyle(fontSize: 12, height: 1.8),
          ),
        ),
      ],
    ),
  );
}

Future<bool> explainPermission(
  BuildContext context,
  PermissionPurpose purpose,
) async {
  final camera = purpose == PermissionPurpose.camera;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(camera ? '允许使用相机？' : '允许保存照片？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                camera
                    ? '用于显示取景画面、推荐构图和拍照。画面在手机内处理，不上传。拒绝后仍可使用练习模式。'
                    : '用于把刚拍下的照片添加到系统相册，不读取其他照片。拒绝后照片会留在当前页面，你可稍后重试保存。',
              ),
              TextButton(
                onPressed: () =>
                    openPolicy(context, PolicyDocument.permissions),
                child: const Text('查看权限使用说明'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('暂不开启'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        ),
      ) ??
      false;
}
