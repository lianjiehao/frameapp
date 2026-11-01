import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:framecoach/services/pose_detector.dart';
import 'package:framecoach/services/pose_guide.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native detector finds packaged person, rejects empty input and preserves overlap coordinates',
    (tester) async {
      final detector = createPoseDetector();
      final bytes = (await rootBundle.load(
        'assets/reference_templates/03701949-9a36-4840-925c-f115331642de.jpg',
      )).buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final pixels = await compute(samplePoseReference, (
        width: image.width,
        height: image.height,
        rgba: data,
        mirror: false,
      ));
      final reference = await detector.detect(pixels);
      expect(
        reference?.usable,
        isTrue,
        reason: 'Packaged reference must produce usable native joints',
      );
      final live = await detector.detect(pixels);
      expect(compareBodyPoses(reference!, live!).aligned, isTrue);
      final shifted = Uint8List(pixels.rgb.length);
      for (int y = 0; y < 256; y++) {
        for (int x = 35; x < 192; x++) {
          for (int c = 0; c < 3; c++) {
            shifted[(y * 192 + x) * 3 + c] =
                pixels.rgb[(y * 192 + x - 35) * 3 + c];
          }
        }
      }
      final moved = await detector.detect(PosePixels(192, 256, shifted));
      expect(
        moved == null || !compareBodyPoses(reference, moved).aligned,
        isTrue,
      );
      final empty = await detector.detect(
        PosePixels(192, 256, Uint8List(192 * 256 * 3)),
      );
      expect(empty?.usable ?? false, isFalse);
      image.dispose();
      codec.dispose();
      await detector.close();

      // Real native results pass through the production readiness coordinator.
      // Timestamps are controlled; no wall-clock sleep can make a test ready.
      var now = DateTime(2026);
      final guide = PoseGuide(now: () => now);
      addTearDown(guide.dispose);
      Future<void> notification(
        void Function() action, {
        bool Function()? when,
      }) async {
        final complete = Completer<void>();
        void listener() {
          if (!complete.isCompleted && (when == null || when())) {
            complete.complete();
          }
        }

        guide.addListener(listener);
        try {
          action();
          await complete.future.timeout(const Duration(seconds: 20));
        } finally {
          guide.removeListener(listener);
        }
      }

      guide.setReference('native-reference', bytes);
      await notification(
        () => guide.setActive(true),
        when: () => guide.hint == '让身体与参考图重合，保持 1 秒',
      );
      expect(guide.ready, isFalse);
      for (final ms in [0, 200, 400, 600, 800, 999, 1000]) {
        now = DateTime(2026).add(Duration(milliseconds: ms));
        await notification(() => guide.submit(() async => pixels, now));
        expect(guide.progress, closeTo(ms / 1000, .001));
        expect(guide.ready, ms == 1000);
      }
      now = now.add(const Duration(milliseconds: 120));
      await notification(
        () => guide.submit(() async => PosePixels(192, 256, shifted), now),
      );
      expect(guide.ready, isFalse);
      expect(guide.progress, 0);
      guide.setActive(false);
      guide.setActive(true);
      expect(guide.ready, isFalse);
      now = now.add(const Duration(milliseconds: 120));
      await notification(() => guide.submit(() async => pixels, now));
      expect(guide.progress, 0);
      expect(guide.ready, isFalse);
    },
  );
}
