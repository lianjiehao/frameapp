import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/services/references.dart';
import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'widget_test.dart' show loadAppFonts;
import 'package:framecoach/services/pose_guide.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/core/vision.dart';
import 'reference_test.dart'
    show referencePng, MemoryReferences, exportReferencePreview;

BodyPose body({
  double x = 0,
  double y = 0,
  double scale = 1,
  bool hiddenWrist = false,
}) => BodyPose([
  for (final (i, p) in const [
    (.4, .3),
    (.6, .3),
    (.3, .43),
    (.7, .43),
    (.2, .5),
    (.8, .5),
    (.44, .6),
    (.56, .6),
    (.43, .75),
    (.57, .75),
    (.42, .92),
    (.58, .92),
  ].indexed)
    BodyPoint(
      (p.$1 - .5) * scale + .5 + x,
      (p.$2 - .5) * scale + .5 + y,
      hiddenWrist && i == 4 ? .1 : .9,
    ),
]);

class ControlledDetector implements PoseDetector {
  final requests = <Completer<BodyPose?>>[];
  final samples = <PosePixels>[];
  int closes = 0;
  @override
  Future<BodyPose?> detect(PosePixels pixels) {
    samples.add(pixels);
    final request = Completer<BodyPose?>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

Future<void> until(WidgetTester tester, bool Function() condition) async {
  final deadline = Stopwatch()..start();
  while (!condition() && deadline.elapsed < const Duration(seconds: 8)) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
  }
  expect(condition(), isTrue);
}

void main() {
  test(
    'matches actual overlap, rejects translation, scale, lost limbs and invalid confidence',
    () {
      expect(compareBodyPoses(body(), body()).aligned, isTrue);
      expect(compareBodyPoses(body(), body(x: .18)).aligned, isFalse);
      expect(compareBodyPoses(body(), body(y: -.18)).aligned, isFalse);
      expect(compareBodyPoses(body(), body(scale: .65)).aligned, isFalse);
      expect(
        compareBodyPoses(body(), body(hiddenWrist: true)).aligned,
        isFalse,
      );
      expect(compareBodyPoses(const BodyPose([]), body()).aligned, isFalse);
      expect(const BodyPoint(double.nan, .3, .9).usable, isFalse);
      final reclining = BodyPose([
        for (final p in body().points) BodyPoint(p.y, p.x, p.confidence),
      ]);
      expect(compareBodyPoses(reclining, reclining).aligned, isTrue);
    },
  );
  test(
    'requires a full second of fresh ordered aligned frames, revokes on gaps and loss',
    () {
      final hold = PoseHold(), start = DateTime(2026);
      for (final ms in [0, 200, 400, 600, 800, 999]) {
        final now = start.add(Duration(milliseconds: ms));
        hold.accept(aligned: true, capturedAt: now, now: now);
        expect(hold.ready, isFalse);
      }
      hold.accept(
        aligned: true,
        capturedAt: start.add(const Duration(seconds: 1)),
        now: start.add(const Duration(seconds: 1)),
      );
      expect(hold.ready, isTrue);
      expect(
        hold.fresh(start.add(const Duration(milliseconds: 1851))),
        isFalse,
      );
      hold.accept(
        aligned: true,
        capturedAt: start.add(const Duration(seconds: 2)),
        now: start.add(const Duration(seconds: 2)),
      );
      expect(hold.progress, 0);
      hold.accept(
        aligned: false,
        capturedAt: start.add(const Duration(milliseconds: 2200)),
        now: start.add(const Duration(milliseconds: 2200)),
      );
      expect(hold.progress, 0);
      hold.accept(
        aligned: true,
        capturedAt: start,
        now: start.add(const Duration(seconds: 3)),
      );
      expect(hold.ready, isFalse);
    },
  );
  testWidgets(
    'pose guide detects only after activation and keeps latest frame timestamps',
    (tester) async {
      var now = DateTime(2026);
      final detector = ControlledDetector();
      final guide = PoseGuide(detector: detector, now: () => now);
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await referencePng();
      });
      guide.setReference('reference', bytes);
      expect(detector.requests, isEmpty);
      guide.setActive(true);
      await until(tester, () => detector.requests.length == 1);
      detector.requests[0].complete(body());
      await tester.pump();
      Future<PosePixels> sample(int n) async =>
          PosePixels(192, 256, Uint8List(192 * 256 * 3)..[0] = n);
      guide.submit(() => sample(1), now);
      await until(tester, () => detector.requests.length == 2);
      now = now.add(const Duration(milliseconds: 200));
      guide.submit(() => sample(2), now);
      now = now.add(const Duration(milliseconds: 200));
      guide.submit(() => sample(3), now);
      detector.requests[1].complete(body());
      await until(tester, () => detector.requests.length == 3);
      expect(detector.samples.last.rgb.first, 3);
      detector.requests[2].complete(body());
      await tester.pump();
      expect(guide.progress, closeTo(.4, .001));
      for (final ms in [200, 200, 200]) {
        now = now.add(Duration(milliseconds: ms));
        final count = detector.requests.length;
        guide.submit(() => sample(4), now);
        await until(tester, () => detector.requests.length > count);
        detector.requests.last.complete(body());
        await tester.pump();
      }
      expect(guide.ready, isTrue);
      guide.setShaking(true);
      expect(guide.ready, isFalse);
      expect(guide.progress, 0);
      guide.setShaking(false);
      now = now.add(const Duration(milliseconds: 200));
      guide.submit(() => sample(5), now);
      await until(tester, () => detector.samples.last.rgb.first == 5);
      guide.setReference('other', bytes, mirror: true);
      detector.requests.last.complete(body());
      await until(tester, () => detector.samples.last.rgb.first != 5);
      expect(guide.ready, isFalse);
      guide.setActive(false);
      detector.requests.last.complete(body());
      await tester.pump();
      expect(guide.ready, isFalse);
      expect(guide.progress, 0);
      guide.dispose();
    },
  );
  testWidgets(
    'failed references and delayed live results cannot enable capture',
    (tester) async {
      var now = DateTime(2026);
      final detector = ControlledDetector();
      final guide = PoseGuide(detector: detector, now: () => now);
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await referencePng();
      });
      guide.setReference('first', bytes);
      guide.setActive(true);
      await until(tester, () => detector.requests.length == 1);
      detector.requests.last.complete(null);
      await tester.pump();
      expect(guide.ready, isFalse);
      expect(guide.hint, contains('参考图人体不清晰'));
      Future<PosePixels> sample() async =>
          PosePixels(192, 256, Uint8List(192 * 256 * 3));
      guide.submit(sample, now);
      await tester.pump();
      expect(detector.requests.length, 1);
      guide.setReference('second', bytes);
      await until(tester, () => detector.requests.length == 2);
      detector.requests.last.completeError(
        StateError('offline detector failed'),
      );
      await tester.pump();
      expect(guide.hint, contains('暂不可用'));
      expect(guide.ready, isFalse);
      guide.setReference('third', bytes);
      await until(tester, () => detector.requests.length == 3);
      detector.requests.last.complete(body());
      await tester.pump();
      for (final ms in [0, 250, 500]) {
        now = DateTime(2026).add(Duration(milliseconds: ms));
        final count = detector.requests.length;
        guide.submit(sample, now);
        await until(tester, () => detector.requests.length > count);
        detector.requests.last.complete(body());
        await tester.pump();
      }
      expect(guide.progress, .5);
      now = DateTime(2026).add(const Duration(milliseconds: 750));
      final count = detector.requests.length;
      guide.submit(sample, now);
      await until(tester, () => detector.requests.length > count);
      now = now.add(const Duration(milliseconds: 851));
      detector.requests.last.complete(body());
      await tester.pump();
      expect(guide.ready, isFalse);
      expect(guide.progress, 0);
      guide.setActive(false);
      expect(detector.closes, greaterThan(0));
      guide.dispose();
    },
  );
  testWidgets(
    'pose shutter captures without detection and suspension still blocks capture',
    (tester) async {
      final detector = ControlledDetector();
      final frames = StreamController<GrayFrame>.broadcast();
      var saves = 0;
      final coach = CameraCoach(
        demo: true,
        previewFrames: frames.stream,
        poseDetector: detector,
        now: tester.binding.clock.now,
        saver: (_, _) async {
          saves++;
        },
      );
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      final library = ReferenceLibrary(store: MemoryReferences());
      await tester.runAsync(() async {
        await consent.load();
        await coach.initialize();
        library.selectTemplate(
          'ref',
          await File('test/fixtures/pose_person.png').readAsBytes(),
        );
        await loadAppFonts();
      });
      coach.setShootingMode(ShootingMode.pose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('reference-preview'),
          child: FrameApp(
            coach: coach,
            consent: consent,
            references: library,
            permissionBackend: TestPermissions()..photos = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      frames.add(GrayFrame(192, 256, Uint8List(192 * 256)));
      await tester.pump();
      expect(detector.requests, isEmpty);
      expect(coach.poseGuide.ready, isFalse);
      expect(find.byKey(const Key('pose-hold-progress')), findsNothing);
      expect(find.byKey(const Key('pose-direct-capture')), findsNothing);
      expect(find.byKey(const Key('pose-shooting-hint')), findsNothing);
      expect(
        tester.widget<GestureDetector>(find.byKey(const Key('shutter'))).onTap,
        isNotNull,
      );
      expect(find.byKey(const Key('toggle-reference')), findsNothing);
      tester
          .widget<Slider>(find.byKey(const Key('reference-opacity')))
          .onChanged!(0);
      await tester.tap(find.byKey(const Key('mirror-reference')));
      await tester.pumpAndSettle();
      expect(library.opacity, 0);
      expect(library.mirror, isTrue);
      expect(detector.requests, isEmpty);
      await exportReferencePreview(tester, 'pose-manual-shutter');
      await tester.tap(find.byKey(const Key('shutter')));
      expect(coach.phase, CapturePhase.capturing);
      await until(
        tester,
        () => coach.phase == CapturePhase.captured && !coach.saving,
      );
      expect(saves, 1);
      expect(coach.photo, isNotNull);
      await tester.tap(find.byKey(const Key('next-photo')));
      await tester.pumpAndSettle();
      expect(library.selected, isNotNull);
      expect(detector.requests, isEmpty);
      expect(
        tester.widget<GestureDetector>(find.byKey(const Key('shutter'))).onTap,
        isNotNull,
      );
      await tester.runAsync(coach.suspend);
      await tester.pump();
      expect(coach.canCapturePose, isFalse);
      await tester.runAsync(coach.takePhoto);
      expect(saves, 1);
      await tester.runAsync(coach.initialize);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pose-restart')));
      await tester.pumpAndSettle();
      expect(library.selected, isNull);
      expect(find.byKey(const Key('pose-select-controls')), findsOneWidget);
      expect(find.byKey(const Key('shutter')), findsNothing);
      expect(detector.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
      await tester.runAsync(() => frames.close());
    },
  );
}
