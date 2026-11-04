import 'dart:math' as math;
import 'dart:typed_data';

class PosePixels {
  const PosePixels(this.width, this.height, this.rgb);
  final int width, height;
  final Uint8List rgb;
}

class PosePlane {
  const PosePlane(this.bytes, this.rowStride, this.pixelStride);
  final Uint8List bytes;
  final int rowStride, pixelStride;
  int at(int x, int y) => bytes[y * rowStride + x * pixelStride];
}

class PoseCameraInput {
  const PoseCameraInput({
    required this.width,
    required this.height,
    required this.planes,
    required this.bgra,
    required this.rotation,
    required this.mirror,
    this.nv21 = false,
  });
  final int width, height, rotation;
  final List<PosePlane> planes;
  final bool bgra, mirror, nv21;
}

/// Camera input uses the same upright, mirrored, centered 3:4 crop as capture.
/// Only this small RGB result crosses the platform channel. Runs in compute.
PosePixels samplePoseCamera(PoseCameraInput input) {
  const outW = 192, outH = 256;
  final rotated = input.rotation == 90 || input.rotation == 270;
  final uprightW = rotated ? input.height : input.width;
  final uprightH = rotated ? input.width : input.height;
  final cropW = math.min(uprightW.toDouble(), uprightH * .75),
      cropH = math.min(uprightH.toDouble(), uprightW / .75);
  final rgb = Uint8List(outW * outH * 3);
  for (int y = 0; y < outH; y++) {
    for (int x = 0; x < outW; x++) {
      final u =
          ((uprightW - cropW) / 2 +
                  ((input.mirror ? outW - 1 - x : x) + .5) / outW * cropW)
              .floor()
              .clamp(0, uprightW - 1);
      final v = ((uprightH - cropH) / 2 + (y + .5) / outH * cropH)
          .floor()
          .clamp(0, uprightH - 1);
      final (sx, sy) = switch (input.rotation) {
        90 => (v, input.height - 1 - u),
        180 => (input.width - 1 - u, input.height - 1 - v),
        270 => (input.width - 1 - v, u),
        _ => (u, v),
      };
      final index = (y * outW + x) * 3;
      if (input.bgra) {
        final plane = input.planes.first,
            i =
                sy * input.planes.first.rowStride +
                sx * input.planes.first.pixelStride;
        rgb[index] = plane.bytes[i + 2];
        rgb[index + 1] = plane.bytes[i + 1];
        rgb[index + 2] = plane.bytes[i];
      } else {
        final luminance = input.planes.first.at(sx, sy);
        final double u, v;
        if (input.nv21 && input.planes.length == 1) {
          final bytes = input.planes.first.bytes;
          final i =
              input.planes.first.rowStride * input.height +
              (sy ~/ 2) * input.planes.first.rowStride +
              (sx ~/ 2) * 2;
          v = bytes[i] - 128.0;
          u = bytes[i + 1] - 128.0;
        } else {
          u = input.planes[1].at(sx ~/ 2, sy ~/ 2) - 128.0;
          v = input.planes[2].at(sx ~/ 2, sy ~/ 2) - 128.0;
        }
        final yy = 1.164 * (luminance - 16);
        rgb[index] = (yy + 1.596 * v).round().clamp(0, 255);
        rgb[index + 1] = (yy - .392 * u - .813 * v).round().clamp(0, 255);
        rgb[index + 2] = (yy + 2.017 * u).round().clamp(0, 255);
      }
    }
  }
  return PosePixels(outW, outH, rgb);
}

/// Reference-image fitHeight mapping exactly matches ReferenceOverlay.
PosePixels samplePoseReference(
  ({int width, int height, Uint8List rgba, bool mirror}) input,
) {
  const w = 192, h = 256;
  final rgb = Uint8List(w * h * 3),
      fittedWidth = input.width * h / input.height;
  final left = (w - fittedWidth) / 2;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final px = input.mirror ? w - x - .5 : x + .5;
      if (px < left || px >= left + fittedWidth) continue;
      final sx = ((px - left) * input.height / h).floor().clamp(
        0,
        input.width - 1,
      );
      final sy = ((y + .5) * input.height / h).floor().clamp(
        0,
        input.height - 1,
      );
      final i = (sy * input.width + sx) * 4, o = (y * w + x) * 3;
      for (int c = 0; c < 3; c++) {
        rgb[o + c] = (input.rgba[i + c] * input.rgba[i + 3] / 255).round();
      }
    }
  }
  return PosePixels(w, h, rgb);
}
