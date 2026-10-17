import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/services/policy_pages.g.dart';
import 'package:framecoach/services/policy_content.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/ui/policy_view_native.dart';

void main() {
  test('all policy documents have local content and a local address', () {
    expect(
      PolicyDocument.values.map((document) => document.path),
      unorderedEquals(['privacy', 'terms', 'permissions', 'sdk', 'support']),
    );
    expect(
      policyPages.keys,
      unorderedEquals([
        'index',
        ...PolicyDocument.values.map((document) => document.path),
      ]),
    );
    for (final path in policyPages.keys) {
      final content = PolicyContent(path);
      expect(content.html, contains('<html lang="zh-CN">'));
      expect(content.uri, Uri.parse('frame-policy:/$path'));
      expect(policyPath(content.uri), path);
    }
    expect(() => PolicyContent('missing'), throwsArgumentError);
  });

  test('document navigation accepts only known local paths', () {
    for (final path in policyPages.keys) {
      expect(policyPath(Uri.parse('/$path')), path);
      expect(policyPath(Uri.parse(path)), path);
      expect(policyPath(Uri.parse('frame-policy:/$path#section')), path);
    }
    expect(policyPath(Uri.parse('/')), 'index');
    for (final value in [
      'https://example.com/privacy',
      'file:///privacy',
      'javascript:privacy',
      'frame-policy://host/privacy',
      'frame-policy:/privacy?query=true',
      '/missing',
      '/privacy/extra',
      '//host/privacy',
    ]) {
      expect(policyPath(Uri.parse(value)), isNull, reason: value);
    }
  });

  test('external navigation is limited to GitHub and email links', () {
    expect(isPolicyExternalLink(Uri.parse('https://github.com/example')), true);
    expect(isPolicyExternalLink(Uri.parse('mailto:support@example.com')), true);
    for (final value in [
      'http://github.com/example',
      'https://github.com.example.com',
      'https://user@github.com/example',
      'https://example.com',
      'javascript:alert(1)',
      'file:///privacy',
    ]) {
      expect(isPolicyExternalLink(Uri.parse(value)), false, reason: value);
    }
  });

  test('generated document links resolve to real pages and sections', () {
    final links = RegExp(r'href="([^"]+)"');
    for (final page in policyPages.entries) {
      for (final link in links.allMatches(page.value)) {
        final uri = PolicyContent(page.key).uri.resolve(link.group(1)!);
        final path = policyPath(uri);
        if (path == null) {
          expect(isPolicyExternalLink(uri), true, reason: uri.toString());
        } else if (uri.hasFragment) {
          expect(policyPages[path], contains('id="${uri.fragment}"'));
        }
      }
    }
  });

  test('documents contain no scripts or external subresources', () {
    for (final page in policyPages.values) {
      expect(page, contains("default-src 'none'; style-src 'unsafe-inline'"));
      expect(
        RegExp(
          r'<(script|iframe|img|link|video|audio)\b',
          caseSensitive: false,
        ).hasMatch(page),
        false,
      );
      expect(
        RegExp(r'url\s*\(|@import', caseSensitive: false).hasMatch(page),
        false,
      );
    }
  });

  testWidgets('packaged HTML matches the app content for every document', (
    tester,
  ) async {
    for (final page in policyPages.entries) {
      final asset = await rootBundle.loadString(
        'assets/legal/${page.key}.html',
      );
      expect(page.value, asset);
    }
  });

  testWidgets('documents remain readable when a WebView is unavailable', (
    tester,
  ) async {
    for (final document in PolicyDocument.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PolicyView(key: ValueKey(document), document: document),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.data, contains(document.title));
      expect(text.data, contains(policyOperator));
      expect(text.data, contains(policyEmail));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
