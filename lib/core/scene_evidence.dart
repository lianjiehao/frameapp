import 'dart:math' as math;
import 'dart:typed_data';
import 'vision.dart';

/// Measured image evidence, not a semantic label or an aesthetic probability.
class SceneEvidence {
  const SceneEvidence({
    this.detail = 0,
    this.subject,
    this.subjectArea,
    this.subjectConfidence = 0,
    this.isolation = 0,
    this.environment = 0,
    this.symmetry = 0,
    this.leading = 0,
    this.vanishingPoint = const Point2(.5, .5),
    this.leftSpace = 0,
    this.rightSpace = 0,
    this.goldenBalance = 0,
    this.horizon = 0,
    this.horizonY = .5,
  });
  final Point2? subject;
  final double? subjectArea;
  final double detail,
      subjectConfidence,
      isolation,
      environment,
      symmetry,
      leading,
      leftSpace,
      rightSpace,
      goldenBalance,
      horizon,
      horizonY;
  final Point2 vanishingPoint;

  static SceneEvidence measure(
    GrayFrame f,
    SceneFeatures features, {
    Point2? selectedSubject,
  }) {
    final w = f.width, h = f.height;
    final gx = Float64List(w * h),
        gy = Float64List(w * h),
        edge = Float64List(w * h);
    double sum = 0, squares = 0, totalEdge = 0, vertical = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x, value = f.at(x, y);
        sum += value;
        squares += value * value;
        gx[i] = f.at(x + 1, y) - f.at(x - 1, y);
        gy[i] = f.at(x, y + 1) - f.at(x, y - 1);
        edge[i] = math.sqrt(gx[i] * gx[i] + gy[i] * gy[i]);
        totalEdge += edge[i];
        if (gx[i].abs() > gy[i].abs() * 1.5) vertical += edge[i];
      }
    }
    final count = (w - 2) * (h - 2);
    final std = math.sqrt(
      math.max(0, squares / count - math.pow(sum / count, 2)),
    );
    final detail = ((std - 5) / 25).clamp(0.0, 1.0);
    final subject = features.subject ?? selectedSubject;
    final confidence = features.subject == null
        ? 0.0
        : features.subjectConfidence;
    SubjectRegion? region;
    if (subject != null) {
      final nearby = features.regions
          .where((r) => r.distanceTo(subject) < .035)
          .toList();
      nearby.sort((a, b) {
        final ac = a.contains(subject), bc = b.contains(subject);
        if (ac != bc) return ac ? -1 : 1;
        return a.center
            .distanceTo(subject)
            .compareTo(b.center.distanceTo(subject));
      });
      if (nearby.isNotEmpty) region = nearby.first;
    }
    double quiet(double x0, double x1) {
      double energy = 0;
      int pixels = 0;
      for (int y = (h * .12).round(); y < h * .88; y++) {
        for (
          int x = math.max(1, (w * x0).round());
          x < math.min(w - 1, w * x1);
          x++
        ) {
          if (region != null && region.contains(Point2(x / w, y / h))) continue;
          energy += edge[y * w + x].clamp(0, 80);
          pixels++;
        }
      }
      return pixels == 0 ? 0 : (1 - energy / pixels / 22).clamp(0.0, 1.0);
    }

    final left = quiet(.03, .42),
        right = quiet(.58, .97),
        background = quiet(.03, .97);
    double inside = 0, outside = 0, mx = 0, my = 0;
    int insideCount = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final e = edge[y * w + x];
        if (region != null && region.contains(Point2(x / w, y / h))) {
          inside += e;
          insideCount++;
        } else {
          outside += e;
          mx += x / w * e;
          my += y / h * e;
        }
      }
    }
    final density = insideCount == 0 ? 0.0 : inside / insideCount;
    final outsideDensity = outside / math.max(1, count - insideCount);
    final contrast = density == 0
        ? 0.0
        : ((density / math.max(2, outsideDensity) - 1) / 3).clamp(0.0, 1.0);
    final isolation = region == null
        ? 0.0
        : (.55 * contrast + .45 * background) * confidence;
    double pairError = 0, pairEnergy = 0;
    for (int y = 2; y < h - 2; y++) {
      for (int x = 2; x < w ~/ 2 - 2; x++) {
        final a = edge[y * w + x], b = edge[y * w + w - 1 - x];
        pairError += (a - b).abs();
        pairEnergy += a + b;
      }
    }
    final pairSimilarity = pairEnergy < 100
        ? 0.0
        : (1 - pairError / pairEnergy).clamp(0.0, 1.0);
    // A blank wall or a horizontal sky/ground boundary is not facade symmetry.
    final structuralSymmetry =
        pairSimilarity *
        (vertical / math.max(1, totalEdge) / .35).clamp(0.0, 1.0) *
        detail;
    double bestLeading = 0;
    var vanishing = const Point2(.5, .5);
    for (final vx in [.25, .5, .75]) {
      for (final vy in [.25, .4, .55, .7]) {
        double leftVote = 0, rightVote = 0, leftTotal = 0, rightTotal = 0;
        for (int y = (h * vy + 8).round(); y < h - 2; y += 2) {
          for (int x = 2; x < w - 2; x += 2) {
            final i = y * w + x, strength = edge[i];
            final dx = x - vx * w, dy = y - vy * h;
            if (strength < 25 || dx.abs() < w * .10) continue;
            // Purely vertical/horizontal lines cannot become diagonal leading arms.
            if (gx[i].abs() < strength * .15 || gy[i].abs() < strength * .15) {
              continue;
            }
            final parallel =
                ((-gy[i] * dx + gx[i] * dy) /
                        (strength * math.sqrt(dx * dx + dy * dy)))
                    .abs();
            if (dx < 0) {
              leftTotal += strength;
              if (parallel > .985) leftVote += strength;
            } else {
              rightTotal += strength;
              if (parallel > .985) rightVote += strength;
            }
          }
        }
        final leftSupport = leftVote / math.max(250, leftTotal);
        final rightSupport = rightVote / math.max(250, rightTotal);
        final score =
            (math.sqrt(leftSupport * rightSupport) * 1.4).clamp(0.0, 1.0) *
            detail;
        if (score > bestLeading) {
          bestLeading = score;
          vanishing = Point2(vx, vy);
        }
      }
    }
    double goldenBalance = 0;
    if (subject != null && outside > 100) {
      final other = Point2(mx / outside, my / outside);
      final opposing = ((subject.x - .5) * (other.x - .5) < 0) ? 1.0 : .25;
      final separation = (subject.distanceTo(other) / .35).clamp(0.0, 1.0);
      final environmentShare = (outside / math.max(1, totalEdge)).clamp(
        0.0,
        1.0,
      );
      goldenBalance = opposing * separation * environmentShare * confidence;
    }
    return SceneEvidence(
      detail: detail,
      subject: subject,
      subjectArea: region?.area,
      subjectConfidence: confidence,
      isolation: isolation,
      environment: (outsideDensity / 22).clamp(0.0, 1.0),
      symmetry: structuralSymmetry,
      leading: bestLeading,
      vanishingPoint: vanishing,
      // Low global contrast is expected for an isolated subject on a quiet
      // background; it must not erase the measured empty-space evidence.
      leftSpace: left,
      rightSpace: right,
      goldenBalance: goldenBalance,
      // Existing broad-edge fit still needs a nearly horizontal orientation.
      horizon:
          features.horizonConfidence *
          (1 - features.horizonAngle.abs() / 12).clamp(0.0, 1.0) *
          detail,
      horizonY: features.horizonY,
    );
  }
}

class CompositionAnalysis {
  const CompositionAnalysis(this.features, this.evidence, [this.tracking]);
  final SceneFeatures features;
  final SceneEvidence evidence;
  final SubjectTrackUpdate? tracking;
}

CompositionAnalysis analyzeComposition(AnalysisRequest r) {
  final tracking = r.tracking?.advance(r.frame, zoom: r.zoom);
  final features = analyzeRequest(r, update: tracking);
  final evidence = SceneEvidence.measure(
    analysisFrame(r.frame),
    features,
    selectedSubject: r.subjectLocked ? r.previous : null,
  );
  final measured = SceneFeatures(
    subject: features.subject,
    subjectConfidence: features.subjectConfidence,
    subjectArea: evidence.subjectArea ?? features.subjectArea,
    horizonY: features.horizonY,
    horizonAngle: features.horizonAngle,
    horizonConfidence: features.horizonConfidence,
    symmetry: evidence.symmetry,
    leading: evidence.leading,
    vanishingPoint: evidence.vanishingPoint,
    regions: features.regions,
  );
  return CompositionAnalysis(measured, evidence, tracking);
}
