import '../core/pose_alignment.dart';
import '../core/pose_pixels.dart';
export '../core/pose_alignment.dart';
export '../core/pose_pixels.dart';

abstract interface class PoseDetector {
  Future<BodyPose?> detect(PosePixels pixels);
  Future<void> close();
}
