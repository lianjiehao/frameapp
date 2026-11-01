import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/core/pose_pixels.dart';

void main() {
  test(
    'camera pose pixels preserve padded BGRA orientation, crop and front mirror',
    () {
      for (final rotation in [0, 90, 180, 270]) {
        final rotated = rotation == 90 || rotation == 270;
        final w = rotated ? 256 : 192,
            h = rotated ? 192 : 256,
            row = w * 4 + 16;
        final bytes = Uint8List(row * h);
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final (u, v) = switch (rotation) {
              90 => (h - 1 - y, x),
              180 => (w - 1 - x, h - 1 - y),
              270 => (y, w - 1 - x),
              _ => (x, y),
            };
            final i = y * row + x * 4;
            bytes[i] = 33;
            bytes[i + 1] = v;
            bytes[i + 2] = u;
            bytes[i + 3] = 255;
          }
        }
        for (final mirror in [false, true]) {
          final pixels = samplePoseCamera(
            PoseCameraInput(
              width: w,
              height: h,
              planes: [PosePlane(bytes, row, 4)],
              bgra: true,
              rotation: rotation,
              mirror: mirror,
            ),
          );
          for (final (x, y) in [(0, 0), (30, 40), (191, 255)]) {
            final i = (y * 192 + x) * 3;
            expect(pixels.rgb.sublist(i, i + 3), [mirror ? 191 - x : x, y, 33]);
          }
        }
      }
    },
  );
  test('YUV separate planes respect chroma row and pixel strides', () {
    final y = Uint8List(196 * 256)..fillRange(0, 196 * 256, 126);
    final u = Uint8List(200 * 128), v = Uint8List(200 * 128);
    for (int row = 0; row < 128; row++) {
      for (int x = 0; x < 96; x++) {
        u[row * 200 + x * 2] = 128;
        v[row * 200 + x * 2] = 128;
      }
    }
    final pixels = samplePoseCamera(
      PoseCameraInput(
        width: 192,
        height: 256,
        planes: [
          PosePlane(y, 196, 1),
          PosePlane(u, 200, 2),
          PosePlane(v, 200, 2),
        ],
        bgra: false,
        rotation: 0,
        mirror: false,
      ),
    );
    expect(pixels.rgb, everyElement(128));
  });
  test('NV21 preserves padded luminance and interleaved chroma rows', () {
    const row = 200, height = 256;
    final bytes = Uint8List(row * height * 3 ~/ 2)
      ..fillRange(0, row * height, 126);
    bytes.fillRange(row * height, bytes.length, 128);
    final pixels = samplePoseCamera(
      PoseCameraInput(
        width: 192,
        height: height,
        planes: [PosePlane(bytes, row, 1)],
        bgra: false,
        nv21: true,
        rotation: 0,
        mirror: false,
      ),
    );
    expect(pixels.rgb, everyElement(128));
  });
  test(
    'reference fitHeight crops wide images, centers narrow images and mirrors pixels',
    () {
      for (final width in [96, 192, 384]) {
        final rgba = Uint8List(width * 256 * 4);
        for (int y = 0; y < 256; y++) {
          for (int x = 0; x < width; x++) {
            final i = (y * width + x) * 4;
            rgba[i] = x < width / 2 ? 240 : 20;
            rgba[i + 1] = y;
            rgba[i + 3] = 255;
          }
        }
        for (final mirror in [false, true]) {
          final out = samplePoseReference((
            width: width,
            height: 256,
            rgba: rgba,
            mirror: mirror,
          ));
          expect(out.rgb[(128 * 192 + 70) * 3], mirror ? 20 : 240);
          expect(out.rgb[(128 * 192 + 122) * 3], mirror ? 240 : 20);
          expect(out.rgb[(0 * 192 + 70) * 3 + 1], 0);
          expect(out.rgb[(255 * 192 + 70) * 3 + 1], 255);
          expect(
            out.rgb[(128 * 192) * 3],
            width == 96
                ? 0
                : mirror
                ? 20
                : 240,
          );
        }
      }
    },
  );
}
