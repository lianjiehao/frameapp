import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/services/coach.dart';

import 'coach_test_support.dart';
import 'tracking_test.dart' show expected, treeView;

// A real frame with a deterministic guard, rather than a wall-clock performance
// threshold: any pixel sampling on the controller's isolate fails the test.
class _WorkerOnlyFrame extends GrayFrame {
  _WorkerOnlyFrame(GrayFrame frame)
    : uiPort = Isolate.current.controlPort,
      super(frame.width, frame.height, frame.pixels);

  final SendPort uiPort;

  @override
  double at(int x, int y) {
    if (Isolate.current.controlPort == uiPort) {
      throw StateError('Pixel analysis must not run on the UI isolate');
    }
    return super.at(x, y);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<GrayFrame> frames;
  late CameraCoach coach;
  late DateTime now;

  setUp(() async {
    frames = StreamController<GrayFrame>.broadcast(sync: true);
    now = DateTime(2026, 11, 1);
    coach = CameraCoach(
      demo: true,
      previewFrames: frames.stream,
      now: () => now,
      saver: (_, _) async {},
    );
    await coach.initialize();
  });

  tearDown(() async {
    coach.dispose();
    await frames.close();
  });

  Future<void> feed(GrayFrame frame) {
    final previous = coach.features;
    return waitForCoach(
      coach,
      () => !identical(coach.features, previous),
      () => frames.add(frame),
    );
  }

  test(
    'fresh taps sample pixels off the UI isolate and reuse their analysis',
    () async {
      await feed(_WorkerOnlyFrame(treeView()));
      final revision = coach.subjectLock.revision;
      coach.selectSubject(expected());
      expect(coach.selectingSubject, true);
      expect(coach.subjectLock.revision, revision);
      expect(coach.canRecommend, false);
      await waitForCoach(coach, () => !coach.selectingSubject, () {});
      expect(coach.subjectLock.state, SubjectState.tracking);
      expect(coach.canRecommend, true);
      final features = coach.features, evidence = coach.evidence;
      final recommendation = coach.confirmScene();
      // No extra analysis job or spinner is needed for the already verified frame.
      expect(coach.phase, CapturePhase.recommending);
      await recommendation;
      expect(identical(coach.features, features), true);
      expect(identical(coach.evidence, evidence), true);
      expect(coach.plan, isNotNull);
    },
  );

  test(
    'rapid fresh taps publish only the last selection on the latest frame',
    () async {
      await feed(_WorkerOnlyFrame(treeView()));
      await selectAndWait(coach, expected());
      await coach.confirmScene();
      coach.startGuidance();
      final revision = coach.subjectLock.revision;
      final selectedKind = coach.plan!.kind;
      final positions = <Point2>[];
      void changed() {
        if (coach.subjectLock.state == SubjectState.tracking) {
          positions.add(coach.subjectLock.position!);
        }
      }

      coach.addListener(changed);
      await waitForCoach(coach, () => !coach.selectingSubject, () {
        // All these interactions arrive before a worker can publish its result.
        for (var i = 0; i < 12; i++) {
          coach.selectSubject(expected(panX: i.toDouble()));
          frames.add(_WorkerOnlyFrame(treeView(panX: i.toDouble())));
        }
        expect(coach.subjectLock.revision, revision);
        expect(coach.subjectLock.state, SubjectState.lost);
        expect(coach.alignment.progress, 0);
      });
      coach.removeListener(changed);
      expect(coach.subjectLock.revision, revision + 1);
      expect(positions, hasLength(1));
      expect(positions.single.distanceTo(expected(panX: 11)), lessThan(.001));
      expect(
        coach.subjectLock.template!.values,
        SubjectTemplate.capture(treeView(panX: 11), expected(panX: 11))!.values,
      );
      expect(coach.plan!.kind, selectedKind);
      expect(
        coach.evidence.subject!.distanceTo(expected(panX: 11)),
        lessThan(.001),
      );
      expect(coach.phase, CapturePhase.guiding);
      expect(coach.alignment.progress, 0);
    },
  );

  test(
    'an expired selection waits for fresh pixels without restoring the old lock',
    () async {
      await feed(treeView());
      await selectAndWait(coach, expected());
      final revision = coach.subjectLock.revision;
      coach.selectSubject(expected(panX: 8));
      final selectingFeatures = coach.features;
      now = now.add(const Duration(seconds: 2));
      await waitForCoach(
        coach,
        () => !identical(coach.features, selectingFeatures),
        () {},
      );
      expect(coach.subjectLock.revision, revision);
      expect(coach.subjectLock.state, SubjectState.lost);
      expect(coach.selectingSubject, true);
      expect(coach.canRecommend, false);
      await feed(treeView(panX: 8));
      expect(coach.selectingSubject, false);
      expect(
        coach.subjectLock.position!.distanceTo(expected(panX: 8)),
        lessThan(.001),
      );
    },
  );

  for (final cancel in [
    'reset',
    'suspend',
    'capture',
    'mode',
    'zoom',
    'zoom request',
  ]) {
    test('$cancel cancels an in-flight fresh selection', () async {
      await feed(treeView());
      coach.selectSubject(expected());
      switch (cancel) {
        case 'reset':
          coach.resetFraming();
        case 'suspend':
          await coach.suspend();
          await coach.initialize();
        case 'capture':
          await coach.takePhoto(overrideGuidance: true);
        case 'mode':
          coach.setShootingMode(ShootingMode.pose);
          coach.setShootingMode(ShootingMode.composition);
        case 'zoom':
          coach.zoom.configure(1, 4);
          coach.zoom.beginGesture();
          coach.zoom.endGesture();
        case 'zoom request':
          coach.zoom.configure(1, 4);
          await waitForCoach(coach, () => !coach.zoom.busy, () {
            coach.zoom.request(2, (_) async {});
          });
      }
      expect(coach.selectingSubject, false);
      final revision = coach.subjectLock.revision;
      if (cancel == 'capture') coach.resetFraming();
      await feed(treeView());
      expect(coach.subjectLock.state, SubjectState.unselected);
      expect(coach.canRecommend, false);
      expect(
        coach.subjectLock.revision,
        revision + (cancel == 'capture' ? 1 : 0),
      );
    });
  }

  test(
    'an obsolete worker error cannot discard a newer explicit selection',
    () async {
      await feed(treeView());
      await selectAndWait(coach, expected());
      final revision = coach.subjectLock.revision;
      await waitForCoach(coach, () => !coach.selectingSubject, () {
        frames.add(GrayFrame(192, 256, Uint8List(0)));
        coach.selectSubject(expected(panX: 5));
        frames.add(treeView(panX: 5));
      });
      expect(coach.subjectLock.revision, revision + 1);
      expect(coach.subjectLock.state, SubjectState.tracking);
      expect(
        coach.subjectLock.position!.distanceTo(expected(panX: 5)),
        lessThan(.001),
      );
      expect(coach.error, isNull);
      expect(coach.canRecommend, true);
    },
  );

  test(
    'a low-detail tap stays untrackable and cannot use an automatic subject',
    () async {
      await feed(
        GrayFrame(192, 256, Uint8List(192 * 256)..fillRange(0, 192 * 256, 110)),
      );
      await selectAndWait(coach, const Point2(.5, .5));
      expect(coach.subjectLock.state, SubjectState.needsDetail);
      expect(coach.canRecommend, false);
      await feed(treeView());
      expect(coach.subjectLock.state, SubjectState.needsDetail);
      expect(coach.canRecommend, false);
      await coach.confirmScene();
      expect(coach.phase, CapturePhase.framing);
      expect(coach.plans, isEmpty);
    },
  );
}
