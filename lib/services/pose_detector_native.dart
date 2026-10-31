import 'package:flutter/services.dart';
import 'pose_detector_api.dart';

PoseDetector createPoseDetector() => _NativePoseDetector();

class _NativePoseDetector implements PoseDetector {
  static const _channel = MethodChannel('frame/pose_detector');
  @override
  Future<BodyPose?> detect(PosePixels pixels) async {
    final result = await _channel.invokeListMethod<Object?>('detect', {
      'rgb': pixels.rgb,
      'width': pixels.width,
      'height': pixels.height,
    });
    if (result == null) return null;
    if (result.length != BodyJoint.values.length) {
      throw const FormatException('Invalid body joints');
    }
    return BodyPose(
      result.map((value) {
        final p = value as List<Object?>;
        return BodyPoint(
          (p[0] as num).toDouble(),
          (p[1] as num).toDouble(),
          (p[2] as num).toDouble(),
        );
      }).toList(),
    );
  }

  @override
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      /* Unsupported host. */
    } on PlatformException {
      /* The engine may already be detaching during shutdown. */
    }
  }
}
