import 'pose_detector_api.dart';

PoseDetector createPoseDetector() => _UnavailablePoseDetector();

class _UnavailablePoseDetector implements PoseDetector {
  @override
  Future<BodyPose?> detect(PosePixels pixels) =>
      Future.error(UnsupportedError('Native pose detection only'));
  @override
  Future<void> close() async {}
}
