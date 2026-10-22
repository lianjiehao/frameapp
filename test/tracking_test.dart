import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/core/scene_evidence.dart';

const tree = Point2(190, 205);
GrayFrame treeView({
  double panX = 0,
  double panY = 0,
  double zoom = 1,
  double treeX = 0,
  bool hidden = false,
  double exposure = 0,
  double angle = 0,
}) {
  double world(double x, double y) {
    double value = 112 + 6 * math.sin(x / 13) + 7 * math.cos(y / 17);
    final tx = x - tree.x - treeX, ty = y - tree.y;
    final crown = tx * tx / (27 * 27) + ty * ty / (46 * 46) < 1;
    final trunk = tx.abs() < 7 && ty > 20 && ty < 85;
    if (!hidden && (crown || trunk)) {
      value =
          58 +
          35 * math.sin(tx / 3.5) * math.cos(ty / 4.1) +
          28 * math.cos((tx + ty) / 5.4) +
          12 * math.sin((tx - ty) / 2.5);
    }
    return (value + exposure).clamp(0.0, 255.0);
  }

  final pixels = Uint8List(192 * 256);
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 192; x++) {
      pixels[y * 192 + x] = world(
        80 +
            panX +
            ((x - 96) * math.cos(angle) + (y - 128) * math.sin(angle)) / zoom +
            96,
        80 +
            panY +
            (-(x - 96) * math.sin(angle) + (y - 128) * math.cos(angle)) / zoom +
            128,
      ).round();
    }
  }
  return GrayFrame(192, 256, pixels);
}

Point2 expected({
  double panX = 0,
  double panY = 0,
  double zoom = 1,
  double treeX = 0,
  double angle = 0,
}) => Point2(
  (((tree.x + treeX - 80 - panX - 96) * math.cos(angle) -
                  (tree.y - 80 - panY - 128) * math.sin(angle)) *
              zoom +
          96) /
      192,
  (((tree.x + treeX - 80 - panX - 96) * math.sin(angle) +
                  (tree.y - 80 - panY - 128) * math.cos(angle)) *
              zoom +
          128) /
      256,
);

Future<GrayFrame> parkView() async {
  final codec = await ui.instantiateImageCodec(
    await File('assets/images/park.jpg').readAsBytes(),
  );
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  final cropHeight = image.height / 1.25, cropWidth = cropHeight * .75;
  final cx = (image.width * .72 + .12 * cropWidth).clamp(
    cropWidth / 2,
    image.width - cropWidth / 2,
  );
  final cy = (image.height * .53 + .08 * cropHeight).clamp(
    cropHeight / 2,
    image.height - cropHeight / 2,
  );
  final pixels = Uint8List(192 * 256);
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 192; x++) {
      final sx = (cx - cropWidth / 2 + (x + .5) / 192 * cropWidth)
          .floor()
          .clamp(0, image.width - 1);
      final sy = (cy - cropHeight / 2 + (y + .5) / 256 * cropHeight)
          .floor()
          .clamp(0, image.height - 1);
      final i = (sy * image.width + sx) * 4;
      pixels[y * 192 + x] =
          (rgba[i] * 77 + rgba[i + 1] * 150 + rgba[i + 2] * 29) >> 8;
    }
  }
  image.dispose();
  return GrayFrame(192, 256, pixels);
}

/// A known camera displacement, with optional horizontal motion blur and a
/// brightness/contrast change. The selected pixels move by exactly (-dx, -dy).
GrayFrame handheldView(
  GrayFrame source, {
  double dx = 0,
  double dy = 0,
  int blur = 0,
  double gain = 1,
}) {
  final pixels = Uint8List(source.pixels.length);
  for (int y = 0; y < source.height; y++) {
    for (int x = 0; x < source.width; x++) {
      double value = 0;
      for (int offset = -blur; offset <= blur; offset++) {
        value += source.sample(x + dx + offset, y + dy);
      }
      value /= blur * 2 + 1;
      pixels[y * source.width + x] = ((value - 110) * gain + 110).round().clamp(
        0,
        255,
      );
    }
  }
  return GrayFrame(source.width, source.height, pixels);
}

// Repeated keys and small unique label strokes, without a private camera photo.
GrayFrame keyboardView() {
  final pixels = Uint8List(192 * 256);
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 192; x++) {
      final kx = (x + 8) % 24, ky = (y + 5) % 28;
      final key = (x + 8) ~/ 24 + ((y + 5) ~/ 28) * 8;
      var value = kx > 1 && kx < 22 && ky > 1 && ky < 26 ? 205 : 65;
      if (kx >= 4 &&
          kx <= 9 &&
          ky >= 5 &&
          ky <= 12 &&
          (kx == 4 ||
              ky == 5 ||
              ky == 12 ||
              ((key >> ((ky - 5) ~/ 2)) & 1 == 1 && kx == 9))) {
        value = 38;
      }
      pixels[y * 192 + x] = value;
    }
  }
  return GrayFrame(192, 256, pixels);
}

// A plane under known side/up/down perspective changes, with centered digital
// zoom. Its inverse maps output pixels; the forward map is the anchor oracle.
Point2 perspectivePoint(Point2 p, double yaw, double pitch, double zoom) {
  final x = p.x - .5, y = p.y - .5;
  final denominator = 1 + math.sin(yaw) * x + math.sin(pitch) * y;
  return Point2(
    .5 + zoom * math.cos(yaw) * x / denominator,
    .5 + zoom * math.cos(pitch) * y / denominator,
  );
}

GrayFrame perspectiveView(
  GrayFrame source,
  double yaw,
  double pitch,
  double zoom,
) {
  final pixels = Uint8List(source.pixels.length);
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final u = (x / source.width - .5) / zoom;
      final v = (y / source.height - .5) / zoom;
      final a = math.cos(yaw) - u * math.sin(yaw);
      final b = -u * math.sin(pitch);
      final c = -v * math.sin(yaw);
      final d = math.cos(pitch) - v * math.sin(pitch);
      final det = a * d - b * c;
      pixels[y * source.width + x] = source
          .sample(
            (.5 + (u * d - b * v) / det) * source.width,
            (.5 + (a * v - u * c) / det) * source.height,
          )
          .round()
          .clamp(0, 255);
    }
  }
  return GrayFrame(source.width, source.height, pixels);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final axes in [(true, false), (false, true), (true, true)]) {
    test(
      'clicked anchor resists perspective drift (yaw/pitch: $axes)',
      () async {
        final source = await parkView();
        const anchor = Point2(.2, .72);
        final lock = SubjectLock()..select(source, anchor);
        final reference = lock.tracking!.reference;
        for (int i = 1; i <= 45; i++) {
          final angle = math.sin(i * .2) * .5;
          final yaw = axes.$1 ? angle : 0.0, pitch = axes.$2 ? angle : 0.0;
          lock.acceptTracking(
            lock.tracking!.advance(perspectiveView(source, yaw, pitch, 1)),
          );
          expect(lock.state, SubjectState.tracking, reason: 'angle frame $i');
          expect(
            lock.position!.distanceTo(perspectivePoint(anchor, yaw, pitch, 1)) *
                256,
            lessThan(1.5),
            reason: 'anchor drift at angle frame $i',
          );
          expect(lock.tracking!.reference, same(reference));
        }
      },
    );
  }
  test('repeated keys and small labels do not jump to a neighboring key', () {
    final source = keyboardView();
    const anchor = Point2(52 / 192, 177 / 256);
    final lock = SubjectLock()..select(source, anchor);
    for (int i = 1; i <= 40; i++) {
      final angle = math.sin(i * .2) * .35;
      final dx = math.sin(i * 1.2) * 2, dy = math.cos(i * .8) * 2;
      final target = perspectivePoint(anchor, angle, angle, 1);
      final frame = handheldView(
        perspectiveView(source, angle, angle, 1),
        dx: dx,
        dy: dy,
        blur: i.isOdd ? 1 : 0,
        gain: i.isOdd ? .8 : 1,
      );
      lock.acceptTracking(lock.tracking!.advance(frame));
      expect(lock.state, SubjectState.tracking, reason: 'key frame $i');
      expect(
        lock.position!.distanceTo(
              Point2(target.x - dx / 192, target.y - dy / 256),
            ) *
            256,
        lessThan(2),
        reason: 'neighbor-key drift at frame $i',
      );
    }
  });
  for (final initialZoom in [1.0, 2.0]) {
    test(
      'actual zoom pixels recover the same anchor from $initialZoom× selection',
      () {
        const anchor = Point2(.5, .5);
        final lock = SubjectLock()
          ..select(
            treeView(panX: 14, panY: -3, zoom: initialZoom),
            anchor,
            zoom: initialZoom,
          );
        final reference = lock.tracking!.reference;
        final revision = lock.revision;
        for (final zoom in [2.0, 4.0, 2.0, 1.0, 2.0, 4.0, 1.0]) {
          lock.acceptTracking(
            lock.tracking!.advance(
              treeView(panX: 14, panY: -3, zoom: zoom),
              zoom: zoom,
            ),
          );
          expect(lock.state, SubjectState.tracking, reason: 'zoom $zoom');
          expect(lock.position!.distanceTo(anchor) * 256, lessThan(2));
          expect(lock.tracking!.zoom, zoom);
          expect(lock.tracking!.reference, same(reference));
          expect(lock.revision, revision);
        }
      },
    );
  }
  test(
    'repeated zoom in/out does not accumulate a new subject position',
    () async {
      final source = await parkView();
      const anchor = Point2(.5, .5);
      final lock = SubjectLock()..select(source, anchor);
      for (int i = 1; i <= 24; i++) {
        final zoom = i.isOdd ? 2.0 : 1.0;
        lock.acceptTracking(
          lock.tracking!.advance(
            perspectiveView(source, 0, 0, zoom),
            zoom: zoom,
          ),
        );
        expect(lock.state, SubjectState.tracking);
        expect(lock.position!.distanceTo(anchor) * 256, lessThan(1.5));
      }
    },
  );
  test(
    'zoom cannot replace a hidden or cropped-out subject with background',
    () {
      final lock = SubjectLock()..select(treeView(), expected());
      final snapshot = lock.tracking;
      lock.acceptTracking(
        lock.tracking!.advance(treeView(zoom: 2, hidden: true), zoom: 2),
      );
      expect(lock.state, SubjectState.lost);
      expect(lock.tracking, same(snapshot));
      lock.acceptTracking(lock.tracking!.advance(treeView(zoom: 10), zoom: 10));
      expect(lock.state, SubjectState.lost);
      expect(lock.tracking, same(snapshot));
      lock.acceptTracking(lock.tracking!.advance(treeView(zoom: 2), zoom: 2));
      expect(lock.state, SubjectState.tracking);
      expect(lock.position!.distanceTo(expected(zoom: 2)) * 256, lessThan(2));
      expect(lock.tracking!.reference, same(snapshot!.reference));
    },
  );
  for (final blurredSelection in [false, true]) {
    test(
      'outdoor texture stays locked through handheld blur and exposure changes '
      '(blurred selection: $blurredSelection)',
      () async {
        final source = await parkView();
        const anchor = Point2(.2, .72);
        final lock = SubjectLock()
          ..select(
            blurredSelection ? handheldView(source, blur: 3, gain: .8) : source,
            anchor,
          );
        final reference = lock.tracking!.reference;
        for (int i = 1; i <= 12; i++) {
          final dx = math.sin(i * 1.2) * 4, dy = math.cos(i * .8) * 3;
          final update = lock.tracking!.advance(
            handheldView(
              source,
              dx: dx,
              dy: dy,
              blur: i.isOdd ? 3 : 0,
              gain: i.isOdd ? .8 : 1,
            ),
          );
          lock.acceptTracking(update);
          expect(
            lock.state,
            SubjectState.tracking,
            reason: 'handheld frame $i',
          );
          expect(lock.position!.x, closeTo(anchor.x - dx / 192, .012));
          expect(lock.position!.y, closeTo(anchor.y - dy / 256, .012));
          expect(lock.tracking!.reference, same(reference));
        }
      },
    );
  }
  test(
    'selected tree follows consecutive camera pans instead of its screen coordinate',
    () {
      final lock = SubjectLock()..select(treeView(), expected());
      expect(lock.tracking, isNotNull);
      final original = lock.position!;
      for (int i = 1; i <= 8; i++) {
        final frame = treeView(panX: i * 6, panY: i * -3, exposure: i * 2);
        final result = analyzeComposition(
          AnalysisRequest(
            frame,
            lock.template,
            lock.position,
            subjectLocked: true,
            tracking: lock.tracking,
          ),
        );
        lock.acceptTracking(result.tracking!);
        expect(lock.state, SubjectState.tracking, reason: 'pan frame $i');
        expect(
          lock.position!.x,
          closeTo(expected(panX: i * 6, panY: i * -3).x, .018),
        );
        expect(
          lock.position!.y,
          closeTo(expected(panX: i * 6, panY: i * -3).y, .018),
        );
        expect(result.features.subject!.x, closeTo(lock.position!.x, .001));
      }
      expect(lock.position!.x, lessThan(original.x - .20));
    },
  );
  test(
    'camera-motion prediction handles a pan beyond the old 12 percent search',
    () {
      final snapshot = SubjectTrackSnapshot.capture(treeView(), expected())!;
      final update = snapshot.advance(treeView(panX: 38, panY: 28));
      expect(update.point, isNotNull);
      expect(update.point!.x, closeTo(expected(panX: 38, panY: 28).x, .025));
      expect(update.point!.y, closeTo(expected(panX: 38, panY: 28).y, .025));
    },
  );
  test(
    'slow zoom retains the same tree anchor while its appearance changes',
    () {
      var snapshot = SubjectTrackSnapshot.capture(treeView(), expected())!;
      for (int i = 1; i <= 6; i++) {
        final zoom = 1 + i * .035;
        final result = snapshot.advance(treeView(zoom: zoom, panX: i * 2));
        expect(result.point, isNotNull, reason: 'zoom $zoom');
        expect(
          result.point!.x,
          closeTo(expected(zoom: zoom, panX: i * 2).x, .025),
        );
        expect(
          result.point!.y,
          closeTo(expected(zoom: zoom, panX: i * 2).y, .025),
        );
        snapshot = result.snapshot;
      }
    },
  );
  test('gentle rotation preserves the clicked anchor on a portrait frame', () {
    var snapshot = SubjectTrackSnapshot.capture(treeView(), expected())!;
    for (int i = 1; i <= 5; i++) {
      final angle = i * .02;
      final update = snapshot.advance(treeView(angle: angle, panX: i * 2));
      expect(update.point, isNotNull);
      final target = expected(angle: angle, panX: i * 2);
      expect(update.point!.x, closeTo(target.x, .02));
      expect(update.point!.y, closeTo(target.y, .02));
      snapshot = update.snapshot;
    }
  });
  test(
    'local subject motion follows the tree even when the background stays still',
    () {
      var snapshot = SubjectTrackSnapshot.capture(treeView(), expected())!;
      for (int i = 1; i <= 5; i++) {
        final result = snapshot.advance(treeView(treeX: i * 5));
        expect(result.point, isNotNull);
        expect(result.point!.x, closeTo(expected(treeX: i * 5).x, .025));
        snapshot = result.snapshot;
      }
    },
  );
  test(
    'occlusion revokes tracking, preserves identity, and recovers the returning tree',
    () {
      final lock = SubjectLock()..select(treeView(), expected());
      final first = lock.tracking!.advance(treeView(panX: 12));
      lock.acceptTracking(first);
      final last = lock.position;
      final lost = lock.tracking!.advance(treeView(panX: 18, hidden: true));
      expect(lost.point, isNull);
      lock.acceptTracking(lost);
      expect(lock.state, SubjectState.lost);
      expect(lock.position, same(last));
      final found = lock.tracking!.advance(treeView(panX: 24));
      lock.acceptTracking(found);
      expect(lock.state, SubjectState.tracking);
      expect(lock.position!.x, closeTo(expected(panX: 24).x, .025));
    },
  );
  test(
    'a tree outside the viewport is not reported as a stationary live lock',
    () {
      final snapshot = SubjectTrackSnapshot.capture(treeView(), expected())!;
      final result = snapshot.advance(treeView(panX: 160));
      expect(result.point, isNull);
    },
  );
}
