import 'dart:math' as math;
import 'dart:typed_data';
part 'subject_tracking.dart';

class Point2 {
  const Point2(this.x, this.y);
  final double x, y;
  double distanceTo(Point2 p) =>
      math.sqrt(math.pow((x - p.x) * .75, 2) + math.pow(y - p.y, 2));
}

/// Upright, unmirrored pixels cropped to exactly the displayed 3:4 viewport.
class GrayFrame {
  const GrayFrame(this.width, this.height, this.pixels);
  final int width, height;
  final Uint8List pixels;
  double at(int x, int y) =>
      pixels[y.clamp(0, height - 1) * width + x.clamp(0, width - 1)].toDouble();
  double sample(double x, double y) {
    final left = x.floor(), top = y.floor();
    final dx = x - left, dy = y - top;
    return at(left, top) * (1 - dx) * (1 - dy) +
        at(left + 1, top) * dx * (1 - dy) +
        at(left, top + 1) * (1 - dx) * dy +
        at(left + 1, top + 1) * dx * dy;
  }
}

class SceneFeatures {
  const SceneFeatures({
    this.subject,
    this.subjectConfidence = 0,
    this.subjectArea = .12,
    this.horizonY = .5,
    this.horizonAngle = 0,
    this.horizonConfidence = 0,
    this.symmetry = 0,
    this.leading = 0,
    this.vanishingPoint = const Point2(.5, .5),
    this.regions = const [],
  });
  final Point2? subject;
  final double subjectConfidence,
      subjectArea,
      horizonY,
      horizonAngle,
      horizonConfidence;
  final double symmetry, leading;
  final Point2 vanishingPoint;
  final List<SubjectRegion> regions;
  SceneFeatures withSubject(Point2? point, double confidence) => SceneFeatures(
    subject: point,
    subjectConfidence: confidence,
    subjectArea: subjectArea,
    horizonY: horizonY,
    horizonAngle: horizonAngle,
    horizonConfidence: horizonConfidence,
    symmetry: symmetry,
    leading: leading,
    vanishingPoint: vanishingPoint,
    regions: regions,
  );
}

class SubjectRegion {
  const SubjectRegion(
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.center,
    this.energy,
  );
  final double left, top, right, bottom, energy;
  final Point2 center;
  double get area => (right - left) * (bottom - top);
  bool contains(Point2 p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;
  double distanceTo(Point2 p) =>
      Point2(p.x.clamp(left, right), p.y.clamp(top, bottom)).distanceTo(p);
}

/// Lightweight visual heuristics, deliberately independent of the camera plugin.
/// Scores describe image structure; they are not semantic/object probabilities.
class FrameAnalyzer {
  const FrameAnalyzer();
  SceneFeatures analyze(GrayFrame f) {
    final w = f.width, h = f.height;
    final edge = Float64List(w * h);
    double mean = 0, variance = 0, mirrorError = 0;
    for (final p in f.pixels) {
      mean += p;
    }
    mean /= f.pixels.length;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final dx = f.at(x + 1, y) - f.at(x - 1, y);
        final dy = f.at(x, y + 1) - f.at(x, y - 1);
        edge[y * w + x] = math.sqrt(dx * dx + dy * dy);
        variance += math.pow(f.at(x, y) - mean, 2);
        mirrorError += (f.at(x, y) - f.at(w - x - 1, y)).abs();
      }
    }
    final std = math.sqrt(variance / (w * h));
    final symmetry = std < 8
        ? 0.0
        : (1 - mirrorError / (w * h) / (std * 1.5)).clamp(0.0, 1.0);

    // Find the strongest broad horizontal transition, then fit its slope across strips.
    double bestRowEnergy = 0;
    int bestRow = h ~/ 2;
    for (int y = (h * .18).round(); y < h * .72; y++) {
      double sum = 0;
      for (int x = 3; x < w - 3; x++) {
        sum += (f.at(x, y + 1) - f.at(x, y - 1)).abs();
      }
      if (sum > bestRowEnergy) {
        bestRowEnergy = sum;
        bestRow = y;
      }
    }
    final xs = <double>[], ys = <double>[], strengths = <double>[];
    for (int s = 0; s < 8; s++) {
      final x0 = (w * (s + .15) / 8).round(), x1 = (w * (s + .85) / 8).round();
      double best = 0;
      int row = bestRow;
      for (
        int y = math.max(2, bestRow - 10);
        y < math.min(h - 2, bestRow + 11);
        y++
      ) {
        double sum = 0;
        for (int x = x0; x < x1; x++) {
          sum += (f.at(x, y + 1) - f.at(x, y - 1)).abs();
        }
        if (sum > best) {
          best = sum;
          row = y;
        }
      }
      xs.add((x0 + x1) / 2);
      ys.add(row.toDouble());
      strengths.add(best / math.max(1, x1 - x0));
    }
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;
    double numerator = 0, denominator = 0;
    for (int i = 0; i < xs.length; i++) {
      numerator += (xs[i] - mx) * (ys[i] - my);
      denominator += math.pow(xs[i] - mx, 2);
    }
    final slope = denominator == 0 ? 0.0 : numerator / denominator;
    double residual = 0;
    for (int i = 0; i < xs.length; i++) {
      residual += (ys[i] - (my + slope * (xs[i] - mx))).abs();
    }
    final coverage = strengths.where((v) => v > 14).length / 8;
    final horizonConfidence =
        (coverage * (1 - residual / 8 / 8).clamp(0.0, 1.0)).clamp(0.0, 1.0);

    // Connected salient regions. Suppress long horizon bands and border fragments.
    final mask = Uint8List(w * h);
    for (int y = 5; y < h - 5; y++) {
      for (int x = 5; x < w - 5; x++) {
        final surround =
            (f.at(x - 5, y) +
                f.at(x + 5, y) +
                f.at(x, y - 5) +
                f.at(x, y + 5)) /
            4;
        final highPass = (f.at(x, y) - surround).abs();
        if (highPass > 23 && edge[y * w + x] > 15) {
          for (int yy = y - 1; yy <= y + 1; yy++) {
            for (int xx = x - 1; xx <= x + 1; xx++) {
              mask[yy * w + xx] = 1;
            }
          }
        }
      }
    }
    Point2? subject;
    final regions = <SubjectRegion>[];
    double subjectConfidence = 0, subjectArea = .12, bestBlobScore = 0;
    for (int start = 0; start < mask.length; start++) {
      if (mask[start] != 1) {
        continue;
      }
      final queue = <int>[start];
      mask[start] = 2;
      int minX = w, maxX = 0, minY = h, maxY = 0;
      double weight = 0, cx = 0, cy = 0;
      for (int q = 0; q < queue.length; q++) {
        final i = queue[q], x = i % w, y = i ~/ w;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        final e = edge[i] + 1;
        weight += e;
        cx += x * e;
        cy += y * e;
        for (final next in [i - w, i + w, i - 1, i + 1]) {
          if (next >= 0 && next < mask.length && mask[next] == 1) {
            mask[next] = 2;
            queue.add(next);
          }
        }
      }
      final bw = maxX - minX + 1, bh = maxY - minY + 1;
      final area = bw * bh / (w * h);
      if (queue.length >= 12 && area < .65 && bh >= 4 && bw / bh < 4) {
        regions.add(
          SubjectRegion(
            minX / w,
            minY / h,
            (maxX + 1) / w,
            (maxY + 1) / h,
            Point2(cx / weight / w, cy / weight / h),
            weight,
          ),
        );
      }
      if (queue.length < 12 ||
          area > .32 ||
          bw > w * .65 ||
          bh < 4 ||
          bw / bh > 4) {
        continue;
      }
      final score = weight * (1 - area) * (bh >= bw ? 1.2 : 1.0);
      if (score > bestBlobScore) {
        bestBlobScore = score;
        subject = Point2(cx / weight / w, cy / weight / h);
        subjectConfidence = (.35 + queue.length / 130).clamp(0.0, .9);
        subjectArea = area;
      }
    }

    // Vote for diagonal edges pointing toward a common vanishing point.
    double bestLeading = 0;
    Point2 vanishing = const Point2(.5, .5);
    for (final vy in [.35, .45, .55, .65]) {
      double aligned = 0, total = 0;
      final vx = w * .5, targetY = h * vy;
      for (int y = h ~/ 3; y < h - 2; y += 3) {
        for (int x = 2; x < w - 2; x += 3) {
          if ((x - vx).abs() < w * .1) {
            continue;
          }
          final dx = f.at(x + 1, y) - f.at(x - 1, y),
              dy = f.at(x, y + 1) - f.at(x, y - 1);
          final strength = math.sqrt(dx * dx + dy * dy);
          if (strength < 35) {
            continue;
          }
          final rx = vx - x,
              ry = targetY - y,
              length = math.sqrt(rx * rx + ry * ry);
          if (length < 5 || ry.abs() < 8) {
            continue;
          }
          final parallel = ((-dy * rx + dx * ry) / (strength * length)).abs();
          total += strength;
          if (parallel > .97) {
            aligned += strength;
          }
        }
      }
      final vote = total < 500 ? 0.0 : (aligned / total * 1.8).clamp(0.0, 1.0);
      if (vote > bestLeading) {
        bestLeading = vote;
        vanishing = Point2(.5, vy);
      }
    }
    return SceneFeatures(
      subject: subject,
      subjectConfidence: subjectConfidence,
      subjectArea: subjectArea,
      horizonY: (my / h).clamp(0.0, 1.0),
      horizonAngle: math.atan(slope) * 180 / math.pi,
      horizonConfidence: horizonConfidence,
      symmetry: symmetry,
      leading: bestLeading,
      vanishingPoint: vanishing,
      regions: regions,
    );
  }
}

/// Immutable appearance template. Never replace it with an unmatched background.
class SubjectTemplate {
  SubjectTemplate._(
    this.values,
    this.mean,
    this.std,
    this.radiusX,
    this.radiusY,
    this.offsetX,
    this.offsetY,
  );
  final List<double> values;
  final double mean, std, radiusX, radiusY, offsetX, offsetY;
  static SubjectTemplate? capture(GrayFrame f, Point2 point) {
    const rx = .07, ry = .065;
    // Keep the patch inside the image while preserving the clicked anchor.
    final center = Point2(point.x.clamp(rx, 1 - rx), point.y.clamp(ry, 1 - ry));
    final values = _patch(f, center, rx, ry);
    final mean = values.reduce((a, b) => a + b) / values.length;
    final std = math.sqrt(
      values.fold(0.0, (s, v) => s + math.pow(v - mean, 2)) / values.length,
    );
    if (std < 7) {
      return null;
    }
    return SubjectTemplate._(
      values,
      mean,
      std,
      rx,
      ry,
      center.x - point.x,
      center.y - point.y,
    );
  }

  static List<double> _patch(GrayFrame f, Point2 p, double rx, double ry) => [
    for (int y = 0; y < 11; y++)
      for (int x = 0; x < 11; x++)
        f.sample(
          (p.x + (x / 10 * 2 - 1) * rx) * f.width,
          (p.y + (y / 10 * 2 - 1) * ry) * f.height,
        ),
  ];
  TrackMatch match(
    GrayFrame f,
    Point2 previous, {
    double searchRadius = .12,
    double scale = 1,
  }) {
    final rx = radiusX * scale, ry = radiusY * scale;
    if (rx >= .5 || ry >= .5) return const TrackMatch(null, 0);
    double best = double.infinity;
    Point2? point;
    // Wide enough to recover from ordinary panning; fixed template prevents drift.
    for (
      int yy = -(f.height * searchRadius).ceil();
      yy <= (f.height * searchRadius).ceil();
      yy++
    ) {
      for (
        int xx = -(f.width * searchRadius).ceil();
        xx <= (f.width * searchRadius).ceil();
        xx++
      ) {
        final p = Point2(previous.x + xx / f.width, previous.y + yy / f.height);
        final center = Point2(p.x + offsetX * scale, p.y + offsetY * scale);
        if (p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) {
          continue;
        }
        if (center.x < rx ||
            center.x > 1 - rx ||
            center.y < ry ||
            center.y > 1 - ry) {
          continue;
        }
        final patch = _patch(f, center, rx, ry);
        final pm = patch.reduce((a, b) => a + b) / patch.length;
        final ps = math.sqrt(
          patch.fold(0.0, (s, v) => s + math.pow(v - pm, 2)) / patch.length,
        );
        if (ps < 5) {
          continue;
        }
        double error = 0;
        for (int i = 0; i < patch.length; i++) {
          error += math.pow((patch[i] - pm) / ps - (values[i] - mean) / std, 2);
        }
        error /= patch.length;
        if (error < best) {
          best = error;
          point = p;
        }
      }
    }
    final confidence = (1 - best / .75).clamp(0.0, 1.0);
    return TrackMatch(confidence >= .45 ? point : null, confidence);
  }
}

class TrackMatch {
  const TrackMatch(this.point, this.confidence);
  final Point2? point;
  final double confidence;
}

class AnalysisRequest {
  const AnalysisRequest(
    this.frame,
    this.template,
    this.previous, {
    this.subjectLocked = false,
    this.tracking,
    this.zoom = 1,
  });
  final GrayFrame frame;
  final SubjectTemplate? template;
  final Point2? previous;
  final bool subjectLocked;
  final SubjectTrackSnapshot? tracking;
  final double zoom;
}

SceneFeatures analyzeRequest(AnalysisRequest r, {SubjectTrackUpdate? update}) {
  final features = const FrameAnalyzer().analyze(analysisFrame(r.frame));
  if (r.tracking != null) {
    final match = update ?? r.tracking!.advance(r.frame, zoom: r.zoom);
    return features.withSubject(match.point, match.confidence);
  }
  if (r.template != null && r.previous != null) {
    final match = r.template!.match(r.frame, r.previous!);
    return features.withSubject(match.point, match.confidence);
  }
  if (r.subjectLocked) {
    return features.withSubject(null, 0);
  }
  return features;
}

enum SubjectState { unselected, tracking, lost, needsDetail }

/// Selection survives an uncertain frame, without presenting its old position
/// as a successful live match or letting saliency choose a different subject.
class SubjectLock {
  SubjectTemplate? template;
  SubjectTrackSnapshot? tracking;
  Point2? position;
  SubjectState state = SubjectState.unselected;
  int revision = 0;
  bool get selected => position != null;
  bool get trackable => tracking != null || template != null;

  void select(GrayFrame frame, Point2 point, {double zoom = 1}) {
    revision++;
    position = Point2(point.x.clamp(0.0, 1.0), point.y.clamp(0.0, 1.0));
    template = SubjectTemplate.capture(frame, position!);
    tracking = SubjectTrackSnapshot.capture(frame, position!, zoom: zoom);
    state = trackable ? SubjectState.tracking : SubjectState.needsDetail;
  }

  void accept(SceneFeatures result) {
    if (!selected || !trackable) return;
    if (result.subject != null && result.subjectConfidence >= .45) {
      position = result.subject;
      state = SubjectState.tracking;
    } else {
      markLost();
    }
  }

  void acceptTracking(SubjectTrackUpdate update) {
    if (!selected) return;
    if (update.point != null && update.confidence >= .45) {
      tracking = update.snapshot;
      position = update.point;
      state = SubjectState.tracking;
    } else {
      markLost();
    }
  }

  void markLost() {
    if (selected && trackable) state = SubjectState.lost;
  }

  void reset() {
    revision++;
    template = null;
    tracking = null;
    position = null;
    state = SubjectState.unselected;
  }
}
