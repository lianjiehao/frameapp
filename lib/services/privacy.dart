import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'policy_pages.g.dart' show policyRevision;

enum PolicyDocument {
  privacy('privacy', '隐私政策'),
  terms('terms', '用户协议'),
  permissions('permissions', '权限使用说明'),
  sdk('sdk', '第三方组件清单'),
  support('support', '帮助与联系');

  const PolicyDocument(this.path, this.title);
  final String path, title;
  String get asset => 'assets/legal/$path.html';
  static const revision = policyRevision;
}

abstract class ConsentStore {
  Future<String?> readConsent();
  Future<void> writeConsent(String? revision);
  Future<bool> wasPrompted(String permission);
  Future<void> markPrompted(String permission);
}

class LocalConsentStore implements ConsentStore {
  static const consentKey = 'frame.privacy.revision';
  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<String?> readConsent() async =>
      (await _preferences).getString(consentKey);
  @override
  Future<void> writeConsent(String? revision) async {
    final preferences = await _preferences;
    final success = revision == null
        ? await preferences.remove(consentKey)
        : await preferences.setString(consentKey, revision);
    if (!success) throw StateError('Consent could not be saved');
  }

  @override
  Future<bool> wasPrompted(String permission) async =>
      (await _preferences).getBool('frame.permission.$permission') ?? false;
  @override
  Future<void> markPrompted(String permission) async {
    if (!await (await _preferences).setBool(
      'frame.permission.$permission',
      true,
    )) {
      throw StateError('Permission prompt could not be saved');
    }
  }
}

class PrivacyConsent extends ChangeNotifier {
  PrivacyConsent({ConsentStore? store}) : store = store ?? LocalConsentStore();
  final ConsentStore store;
  bool loaded = false, accepted = false, saving = false;
  String? error;
  bool _disposed = false;

  Future<void> load() async {
    try {
      final revision = await store.readConsent();
      if (_disposed) return;
      accepted = revision == PolicyDocument.revision;
    } catch (_) {
      error = '无法读取同意记录，请重新确认。';
    }
    if (_disposed) return;
    loaded = true;
    notifyListeners();
  }

  Future<void> accept() async {
    if (saving || _disposed) return;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await store.writeConsent(PolicyDocument.revision);
      if (_disposed) return;
      accepted = true;
    } catch (_) {
      error = '未能保存同意记录，请重试。';
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> withdraw() async {
    if (_disposed) return;
    // Revoke in memory immediately, so persistence cannot delay camera shutdown.
    accepted = false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await store.writeConsent(null);
    } catch (_) {
      error = '同意已撤回，但本机记录未能清除。请重试或清除应用数据。';
    } finally {
      saving = false;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
