import 'dart:math' as math;

/// Shared anatomical order for the native detectors; no aesthetic score.
enum BodyJoint {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

class BodyPoint {
  const BodyPoint(this.x, this.y, this.confidence);
  final double x, y, confidence;
  bool get usable =>
      x.isFinite &&
      y.isFinite &&
      confidence.isFinite &&
      confidence >= .45 &&
      x >= 0 &&
      x <= 1 &&
      y >= 0 &&
      y <= 1;
}

class BodyPose {
  const BodyPose(this.points);
  final List<BodyPoint> points;
  bool get usable =>
      points.length == BodyJoint.values.length &&
      [0, 1, 6, 7].every((i) => points[i].usable) &&
      points.where((p) => p.usable).length >= 8 &&
      _torsoLength(points[0], points[6]) + _torsoLength(points[1], points[7]) >=
          .18;

  static double _torsoLength(BodyPoint a, BodyPoint b) =>
      math.sqrt(math.pow((a.x - b.x) * .75, 2) + math.pow(a.y - b.y, 2));
}

class PoseMatch {
  const PoseMatch(this.aligned, this.hint);
  final bool aligned;
  final String hint;
}

PoseMatch compareBodyPoses(BodyPose reference, BodyPose live) {
  if (!reference.usable) return const PoseMatch(false, '参考图人体不清晰，请换图或直接拍照');
  if (!live.usable) return const PoseMatch(false, '请让一个人完整进入画面');
  double total = 0, maximum = 0, dx = 0, dy = 0;
  int count = 0;
  for (int i = 0; i < reference.points.length; i++) {
    final target = reference.points[i], point = live.points[i];
    if (!target.usable) continue;
    if (!point.usable) return const PoseMatch(false, '请露出被遮挡的手臂或双腿');
    final x = point.x - target.x, y = point.y - target.y;
    final distance = math.sqrt(x * x * .75 * .75 + y * y);
    total += distance;
    maximum = math.max(maximum, distance);
    dx += x;
    dy += y;
    count++;
  }
  // Distances are in preview-height units, deliberately retaining translation
  // and scale: a matching pose elsewhere in the frame must not unlock capture.
  if (total / count <= .045 && maximum <= .09) {
    return const PoseMatch(true, '已重合，保持 1 秒');
  }
  if (dx.abs() / count > .06) {
    return PoseMatch(false, dx > 0 ? '身体向画面左侧移动' : '身体向画面右侧移动');
  }
  if (dy.abs() / count > .06) {
    return PoseMatch(false, dy > 0 ? '身体向画面上方对齐' : '身体向画面下方对齐');
  }
  return const PoseMatch(false, '调整距离和四肢，与参考图重合');
}

class PoseHold {
  static const freshness = Duration(milliseconds: 850);
  DateTime? _start, _last;
  double progress = 0;
  bool get ready => progress >= 1;
  void reset() {
    _start = null;
    _last = null;
    progress = 0;
  }

  bool fresh(DateTime now) =>
      _last != null &&
      now.difference(_last!) >= Duration.zero &&
      now.difference(_last!) <= freshness;
  void accept({
    required bool aligned,
    required DateTime capturedAt,
    required DateTime now,
  }) {
    if (!aligned ||
        capturedAt.isAfter(now) ||
        now.difference(capturedAt) > freshness ||
        (_last != null && !capturedAt.isAfter(_last!))) {
      reset();
      return;
    }
    if (_last != null && capturedAt.difference(_last!) > freshness) reset();
    _start ??= capturedAt;
    _last = capturedAt;
    progress =
        (capturedAt.difference(_start!).inMicroseconds /
                Duration.microsecondsPerSecond)
            .clamp(0, 1);
  }
}
