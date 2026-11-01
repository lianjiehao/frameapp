import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/privacy.dart';

import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'tracking_test.dart' show expected, treeView;
import 'widget_test.dart' show loadAppFonts, savePreview;

void main() {
  testWidgets('practice starts with only the composition mode entry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final consent = PrivacyConsent(store: MemoryStore(PolicyDocument.revision));
    final permissions = TestPermissions();
    final coach = CameraCoach(demo: true, previewFrames: const Stream.empty());
    await tester.runAsync(() async {
      await consent.load();
      await coach.initialize();
      if (const bool.fromEnvironment('EXPORT_PREVIEW')) await loadAppFonts();
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('app-preview'),
        child: FrameApp(
          coach: coach,
          consent: consent,
          permissionBackend: permissions,
        ),
      ),
    );
    for (final (size, scale) in [
      (const Size(390, 844), 1.0),
      (const Size(320, 568), 1.4),
    ]) {
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpAndSettle();
      expect(coach.shootingMode, ShootingMode.composition);
      expect(find.byKey(const Key('mode-composition')), findsOneWidget);
      expect(find.byKey(const Key('mode-pose')), findsNothing);
      expect(find.text('摆姿模式'), findsNothing);
      expect(find.byKey(const Key('composition-steps')), findsOneWidget);
      expect(find.byKey(const Key('pose-steps')), findsNothing);
      expect(find.byKey(const Key('open-references')), findsNothing);
      expect(find.byKey(const Key('reference-overlay')), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
        await savePreview(
          tester,
          '/tmp/frame-practice-composition-${size.width.toInt()}-$scale.png',
        );
      }
    }
    expect(permissions.calls, 0);
    expect(permissions.cameraRequests, 0);
    await tester.pumpWidget(const SizedBox());
    consent.dispose();
  });

  testWidgets('more menu exposes current flash and respects capture state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final consent = PrivacyConsent(store: MemoryStore(PolicyDocument.revision));
    final coach = _PracticeCoach(
      frames: const Stream.empty(),
      now: tester.binding.clock.now,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('app-preview'),
        child: FrameApp(
          coach: coach,
          consent: consent,
          permissionBackend: TestPermissions()..camera = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(coach.initialized, isTrue);
    expect(find.byTooltip('切换镜头'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.byTooltip('闪光灯'), findsNothing);
    expect(find.byTooltip('拍照指南'), findsNothing);
    expect(find.byKey(const Key('menu-flash')), findsNothing);
    for (final (label, next) in [
      ('关闭', FlashMode.auto),
      ('自动', FlashMode.always),
      ('开启', FlashMode.off),
    ]) {
      await tester.tap(find.byKey(const Key('camera-more')));
      await tester.pumpAndSettle();
      expect(find.text('闪光灯 · $label'), findsOneWidget);
      final item = find.byKey(const Key('menu-flash'));
      expect(item.hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('menu-help')).hitTestable(), findsOneWidget);
      if (const bool.fromEnvironment('EXPORT_PREVIEW') && label == '关闭') {
        await tester.runAsync(loadAppFonts);
        await tester.pumpAndSettle();
        await savePreview(tester, 'artifacts/references/camera-more-320.png');
      }
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(coach.flash, next);
      expect(item, findsNothing);
      expect(tester.takeException(), isNull);
    }
    expect(coach.flashChanges, 3);
    coach.phase = CapturePhase.capturing;
    coach.notifyListeners();
    await tester.pump();
    expect(
      tester.widget<TextButton>(find.byKey(const Key('mode-pose'))).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('camera-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final flash = find.byKey(const Key('menu-flash'));
    expect(tester.widget<PopupMenuItem<dynamic>>(flash).enabled, isFalse);
    await tester.tap(flash);
    await tester.pump();
    expect(coach.flashChanges, 3);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    consent.dispose();
  }, skip: const bool.fromEnvironment('DEMO_MODE'));

  for (final denied in [false, true]) {
    testWidgets(
      'help practice exits to ${denied ? 'permission retry' : 'camera'} and clears guidance',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final frames = StreamController<GrayFrame>();
        final coach = _PracticeCoach(
          frames: frames.stream,
          now: tester.binding.clock.now,
        );
        final store = MemoryStore(PolicyDocument.revision);
        final consent = PrivacyConsent(store: store);
        final permissions = TestPermissions()..camera = true;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('app-preview'),
            child: FrameApp(
              coach: coach,
              consent: consent,
              permissionBackend: permissions,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(coach.cameraStarts, 1);
        expect(find.byKey(const Key('exit-demo')), findsNothing);
        await tester.tap(find.byKey(const Key('mode-pose')));
        await tester.pumpAndSettle();
        expect(coach.isPose, isTrue);
        await tester.tap(find.byKey(const Key('camera-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('menu-help')));
        await tester.pumpAndSettle();
        final practiceButton = find.byKey(const Key('help-practice'));
        final helpContent = find.byKey(const Key('help-content'));
        final footer = find.byKey(const Key('help-footer'));
        expect(practiceButton, findsOneWidget);
        if (!denied && const bool.fromEnvironment('EXPORT_PREVIEW')) {
          await tester.runAsync(loadAppFonts);
        }
        for (final layout in [
          (const Size(390, 844), 1.0),
          (const Size(320, 640), 1.0),
          (const Size(320, 568), 1.4),
        ]) {
          tester.view.physicalSize = layout.$1;
          tester.platformDispatcher.textScaleFactorTestValue = layout.$2;
          await tester.pumpAndSettle();
          final button = tester.getRect(practiceButton);
          expect(button.left, 24);
          expect(button.right, layout.$1.width - 24);
          expect(button.bottom, lessThan(layout.$1.height));
          expect(button.height, greaterThanOrEqualTo(50));
          expect(
            tester.getRect(helpContent).bottom,
            lessThanOrEqualTo(tester.getRect(footer).top),
          );
          final footerBeforeScroll = tester.getRect(footer);
          await tester.drag(helpContent, const Offset(0, -240));
          await tester.pumpAndSettle();
          expect(tester.getRect(footer), footerBeforeScroll);
          expect(practiceButton.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (!denied && const bool.fromEnvironment('EXPORT_PREVIEW')) {
            // Return the readable guide to its beginning for the preview.
            tester
                .state<ScrollableState>(
                  find.descendant(
                    of: helpContent,
                    matching: find.byType(Scrollable),
                  ),
                )
                .position
                .jumpTo(0);
            await tester.pumpAndSettle();
            await savePreview(
              tester,
              '/tmp/frame-help-${layout.$1.width.toInt()}-${layout.$2}.png',
            );
          }
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await tester.tap(find.text('试试练习模式'));
        await tester.pump();
        await _pumpUntil(tester, () => coach.practiceLoaded.isCompleted);
        await tester.pumpAndSettle();
        expect(coach.isDemo, true);
        expect(coach.initialized, true);
        expect(frames.hasListener, true);
        expect(coach.shootingMode, ShootingMode.composition);
        expect(find.byKey(const Key('mode-composition')), findsOneWidget);
        expect(find.byKey(const Key('mode-pose')), findsNothing);
        expect(find.byKey(const Key('composition-steps')), findsOneWidget);
        expect(find.byKey(const Key('pose-steps')), findsNothing);
        expect(find.byKey(const Key('pose-import-hint')), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byTooltip('切换镜头'), findsNothing);
        expect(find.byTooltip('闪光灯'), findsNothing);
        final exit = find.byKey(const Key('exit-demo'));
        expect(exit, findsOneWidget);
        expect(tester.widget<TextButton>(exit).onPressed, isNotNull);
        if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
          await tester.runAsync(loadAppFonts);
        }
        for (final width in [390.0, 320.0]) {
          tester.view.physicalSize = Size(width, 844);
          await tester.pumpAndSettle();
          final header = tester.getRect(find.byKey(const Key('camera-header')));
          final button = tester.getRect(exit);
          expect(header.contains(button.topLeft), true);
          expect(header.contains(button.bottomRight), true);
          expect(button.height, greaterThanOrEqualTo(44));
          expect(tester.takeException(), isNull);
          if (!denied && const bool.fromEnvironment('EXPORT_PREVIEW')) {
            await savePreview(
              tester,
              '/tmp/frame-practice-${width.toInt()}.png',
            );
          }
        }

        final analyzed = Completer<void>();
        void changed() {
          if (!analyzed.isCompleted) analyzed.complete();
        }

        coach.addListener(changed);
        frames.add(treeView());
        await tester.pump();
        await _pumpUntil(tester, () => analyzed.isCompleted);
        coach.removeListener(changed);
        coach.selectSubject(expected());
        expect(coach.subjectLock.state, SubjectState.tracking);
        await tester.runAsync(coach.confirmScene);
        expect(coach.phase, CapturePhase.recommending);
        coach.startGuidance();
        expect(coach.phase, CapturePhase.guiding);
        await tester.pump();
        if (denied) {
          permissions.camera = false;
          await store.markPrompted('camera');
        }
        expect(tester.widget<TextButton>(exit).onPressed, isNotNull);
        await tester.tap(exit);
        await _pumpUntil(
          tester,
          () => !coach.isDemo && (coach.initialized || coach.error != null),
        );
        await tester.pumpAndSettle();
        expect(coach.isDemo, false);
        expect(frames.hasListener, false);
        expect(coach.subjectLock.state, SubjectState.unselected);
        expect(coach.features.subject, isNull);
        expect(coach.plan, isNull);
        expect(coach.plans, isEmpty);
        expect(coach.canRecommend, false);
        expect(coach.phase, CapturePhase.framing);
        expect(coach.initialized, !denied);
        expect(coach.cameraStarts, denied ? 1 : 2);
        expect(permissions.cameraRequests, 0);
        expect(exit, findsNothing);
        expect(find.byTooltip('切换镜头'), findsOneWidget);
        expect(
          find.byKey(const Key('mode-pose')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('camera-more')));
        await tester.pumpAndSettle();
        final flash = tester.widget<PopupMenuItem<dynamic>>(
          find.byKey(const Key('menu-flash')),
        );
        expect(flash.enabled, !denied);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        if (denied) {
          expect(find.text('重新开启相机'), findsOneWidget);
          expect(find.text('试试练习模式'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        unawaited(frames.close());
        await tester.pump();
        consent.dispose();
      },
      skip: const bool.fromEnvironment('DEMO_MODE'),
    );
  }

  test('practice-only builds cannot exit to a native camera', () async {
    final coach = CameraCoach(demo: true);
    expect(coach.canExitDemo, false);
    await coach.exitDemo();
    expect(coach.isDemo, true);
    expect(coach.camera, isNull);
    coach.dispose();
  }, skip: !const bool.fromEnvironment('DEMO_MODE'));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() completed) async {
  final deadline = Stopwatch()..start();
  while (!completed() && deadline.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
  }
  expect(completed(), true);
}

// Keep permission checks and practice analysis real; replace native camera I/O.
class _PracticeCoach extends CameraCoach {
  _PracticeCoach({required Stream<GrayFrame> frames, required super.now})
    : super(demo: false, previewFrames: frames);

  int cameraStarts = 0;
  int flashChanges = 0;
  final practiceLoaded = Completer<void>();

  @override
  Future<void> toggleFlash() async {
    flashChanges++;
    flash = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    notifyListeners();
  }

  @override
  Future<void> initialize() async {
    if (isDemo) {
      await super.initialize();
      if (!practiceLoaded.isCompleted) practiceLoaded.complete();
    } else {
      cameraStarts++;
      error = null;
      initialized = true;
      notifyListeners();
    }
  }
}
