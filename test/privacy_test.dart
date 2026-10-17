import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/services/camera_photo.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/permissions.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/services/policy_pages.g.dart'
    show policyOperator, policyEmail;
import 'package:framecoach/ui/privacy_flow.dart';

class MemoryStore implements ConsentStore {
  MemoryStore([this.revision]);
  String? revision;
  bool failWrite = false;
  final prompted = <String>{};
  @override
  Future<String?> readConsent() async => revision;
  @override
  Future<void> writeConsent(String? value) async {
    if (failWrite) throw StateError('storage unavailable');
    revision = value;
  }

  @override
  Future<bool> wasPrompted(String permission) async =>
      prompted.contains(permission);
  @override
  Future<void> markPrompted(String permission) async =>
      prompted.add(permission);
}

class TestPermissions implements PermissionBackend {
  int calls = 0, cameraRequests = 0, photoRequests = 0;
  bool camera = false, photos = false, blocked = false, grant = false;
  @override
  Future<bool> hasCamera() async {
    calls++;
    return camera;
  }

  @override
  Future<bool> cameraBlocked() async {
    calls++;
    return blocked;
  }

  @override
  Future<bool> requestCamera() async {
    cameraRequests++;
    camera = grant;
    return camera;
  }

  @override
  Future<bool> hasPhotoAccess() async {
    calls++;
    return photos;
  }

  @override
  Future<bool> requestPhotoAccess() async {
    photoRequests++;
    photos = grant;
    return photos;
  }

  @override
  Future<bool> openSettings() async => true;
}

void main() {
  test('no permission API or explanation runs before consent', () async {
    final consent = PrivacyConsent(store: MemoryStore());
    await consent.load();
    final backend = TestPermissions();
    final permissions = AppPermissions(consent, backend: backend);
    var explanations = 0;
    Future<bool> explain(PermissionPurpose _) async {
      explanations++;
      return true;
    }

    expect(await permissions.ensureCamera(explain: explain), false);
    expect(await permissions.ensurePhotoSave(explain: explain), false);
    expect(backend.calls, 0);
    expect(backend.cameraRequests + backend.photoRequests, 0);
    expect(explanations, 0);
    consent.dispose();
  });

  test(
    'denied and cancelled requests do not repeat on relaunch; explicit retry works',
    () async {
      final store = MemoryStore(PolicyDocument.revision);
      final consent = PrivacyConsent(store: store);
      await consent.load();
      final backend = TestPermissions();
      final permissions = AppPermissions(consent, backend: backend);
      var explanations = 0;
      Future<bool> explain(PermissionPurpose _) async {
        explanations++;
        return true;
      }

      expect(await permissions.ensureCamera(explain: explain), false);
      expect(backend.cameraRequests, 1);
      final relaunch = AppPermissions(consent, backend: backend);
      expect(await relaunch.ensureCamera(explain: explain), false);
      expect(explanations, 1);
      backend.grant = true;
      expect(
        await relaunch.ensureCamera(explain: explain, explicit: true),
        true,
      );
      expect(backend.cameraRequests, 2);
      expect(
        await relaunch.ensurePhotoSave(explain: (_) async => false),
        false,
      );
      expect(await relaunch.ensurePhotoSave(explain: explain), false);
      expect(backend.photoRequests, 0);
      expect(
        await relaunch.ensurePhotoSave(explain: explain, explicit: true),
        true,
      );
      expect(backend.photoRequests, 1);
      consent.dispose();
    },
  );

  test(
    'permanently blocked camera does not issue another system request',
    () async {
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await consent.load();
      final backend = TestPermissions()..blocked = true;
      expect(
        await AppPermissions(consent, backend: backend).ensureCamera(
          explicit: true,
          explain: (_) async => throw StateError('must not explain'),
        ),
        false,
      );
      expect(backend.cameraRequests, 0);
      consent.dispose();
    },
  );

  test(
    'revocation while explanation is open prevents native authorization',
    () async {
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await consent.load();
      final backend = TestPermissions()..grant = true;
      final explanation = Completer<bool>();
      final opened = Completer<void>();
      final result = AppPermissions(consent, backend: backend).ensureCamera(
        explain: (_) {
          opened.complete();
          return explanation.future;
        },
      );
      await opened.future;
      await consent.withdraw();
      explanation.complete(true);
      expect(await result, false);
      expect(backend.cameraRequests, 0);
      consent.dispose();
    },
  );

  test(
    'failed persistence never grants consent and old revision requires confirmation',
    () async {
      final store = MemoryStore('old-policy')..failWrite = true;
      final consent = PrivacyConsent(store: store);
      await consent.load();
      expect(consent.accepted, false);
      await consent.accept();
      expect(consent.accepted, false);
      expect(consent.error, isNotNull);
      store.failWrite = false;
      await consent.accept();
      final reopened = PrivacyConsent(store: store);
      await reopened.load();
      expect(reopened.accepted, true);
      await reopened.withdraw();
      expect(store.revision, isNull);
      reopened.dispose();
      consent.dispose();
    },
  );

  testWidgets('declining keeps camera uncreated; documents remain accessible', (
    tester,
  ) async {
    final consent = PrivacyConsent(store: MemoryStore());
    var cameraBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyGate(
          consent: consent,
          builder: (_) {
            cameraBuilds++;
            return const Text('camera');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(cameraBuilds, 0);
    expect(find.textContaining('运营者：$policyOperator'), findsOneWidget);
    await tester.tap(find.byKey(const Key('privacy-decline')));
    await tester.pumpAndSettle();
    expect(cameraBuilds, 0);
    await tester.tap(find.text('隐私政策'));
    await tester.pumpAndSettle();
    expect(find.byType(PolicyPage), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(cameraBuilds, 0);
    await tester.pumpWidget(const SizedBox());
    consent.dispose();
  });

  testWidgets('privacy hub uses the configured contact and consent revision', (
    tester,
  ) async {
    final consent = PrivacyConsent(store: MemoryStore());
    await tester.pumpWidget(MaterialApp(home: PrivacyHub(consent: consent)));
    final contact = find.text(
      '隐私联系：$policyEmail\n同意版本：${PolicyDocument.revision}',
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(contact, 200);
    expect(contact, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    consent.dispose();
  });

  testWidgets(
    'acceptance starts camera; withdrawing clears current photo and disposes camera',
    (tester) async {
      final consent = PrivacyConsent(store: MemoryStore());
      final coach = CameraCoach(demo: true);
      await tester.pumpWidget(FrameApp(coach: coach, consent: consent));
      await tester.pumpAndSettle();
      expect(coach.initialized, false);
      await tester.tap(find.byKey(const Key('privacy-accept')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(coach.initialized, true);
      coach.photo = Uint8List.fromList([1, 2, 3]);
      await consent.withdraw();
      await tester.pump();
      expect(coach.disposed, true);
      expect(coach.initialized, false);
      expect(coach.photo, isNull);
      expect(find.byKey(const Key('privacy-accept')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  test(
    'denied saving retains bytes without calling saver, later retry saves once',
    () async {
      var saves = 0, allowed = false;
      final coach = CameraCoach(
        demo: true,
        saver: (bytes, _) async {
          saves++;
        },
      );
      final photo = Uint8List.fromList([1, 2, 3]);
      coach.photo = photo;
      coach.beforeSave = (_) async => allowed;
      await coach.retrySave(explicit: false);
      expect(saves, 0);
      expect(coach.photo, same(photo));
      expect(coach.saved, false);
      allowed = true;
      await coach.retrySave();
      await coach.retrySave();
      expect(saves, 1);
      expect(coach.saved, true);
      coach.dispose();
    },
  );

  testWidgets('privacy hub pauses camera and returning restores it', (
    tester,
  ) async {
    final consent = PrivacyConsent(store: MemoryStore(PolicyDocument.revision));
    final coach = CameraCoach(demo: true);
    await tester.pumpWidget(FrameApp(coach: coach, consent: consent));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(coach.initialized, true);
    await tester.tap(find.byTooltip('拍照指南'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final help = find.byType(BottomSheet);
    expect(help, findsOneWidget);
    expect(
      find.descendant(
        of: help,
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: help, matching: find.text('隐私与权限')),
      findsOneWidget,
    );
    await tester.tap(find.text('隐私与权限'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(coach.initialized, false);
    expect(find.byType(PrivacyHub), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(coach.initialized, true);
    await tester.pumpWidget(const SizedBox());
    consent.dispose();
  });

  testWidgets(
    'next photo restores a camera suspended during photo authorization',
    (tester) async {
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      final coach = CameraCoach(demo: true);
      await tester.pumpWidget(FrameApp(coach: coach, consent: consent));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      coach.phase = CapturePhase.captured;
      coach.saved = true;
      await coach.suspend();
      await tester.pump();
      expect(coach.initialized, false);
      await tester.tap(find.byKey(const Key('next-photo')));
      await tester.pump();
      expect(coach.phase, CapturePhase.framing);
      expect(coach.initialized, true);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  test('camera temporary file is removed after reading its contents', () async {
    final directory = await Directory.systemTemp.createTemp(
      'frame-photo-test-',
    );
    try {
      final file = File('${directory.path}/shot.jpg');
      await file.writeAsBytes([1, 2, 3]);
      expect(await readAndRemovePhoto(XFile(file.path)), [1, 2, 3]);
      expect(await file.exists(), false);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
