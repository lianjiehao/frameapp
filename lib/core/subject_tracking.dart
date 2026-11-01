part of 'vision.dart';

/// Structure analysis remains lightweight; tracking uses the finer camera frame.
GrayFrame analysisFrame(GrayFrame f) {
  if (f.width <= 96 && f.height <= 128) return f;
  final pixels = Uint8List(96 * 128);
  for (int y = 0; y < 128; y++) {
    for (int x = 0; x < 96; x++) {
      pixels[y * 96 + x] = f
          .sample((x + .5) * f.width / 96 - .5, (y + .5) * f.height / 128 - .5)
          .round()
          .clamp(0, 255);
    }
  }
  return GrayFrame(96, 128, pixels);
}

List<GrayFrame> _pyramid(GrayFrame frame) {
  // A small symmetric blur suppresses fine texture that changes with camera
  // motion/focus without shifting the selected anchor. Flow and its appearance
  // checks use the same filtered pixels in both directions.
  final filtered = Uint8List(frame.pixels.length);
  for (int y = 0; y < frame.height; y++) {
    for (int x = 0; x < frame.width; x++) {
      double value = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          value +=
              frame.at(x + dx, y + dy) * (dx == 0 ? 2 : 1) * (dy == 0 ? 2 : 1);
        }
      }
      filtered[y * frame.width + x] = (value / 16).round();
    }
  }
  final levels = <GrayFrame>[GrayFrame(frame.width, frame.height, filtered)];
  while (levels.length < 4 &&
      levels.last.width >= 48 &&
      levels.last.height >= 48) {
    final previous = levels.last;
    final w = previous.width ~/ 2, h = previous.height ~/ 2;
    final bytes = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bytes[y * w + x] =
            ((previous.at(x * 2, y * 2) +
                        previous.at(x * 2 + 1, y * 2) +
                        previous.at(x * 2, y * 2 + 1) +
                        previous.at(x * 2 + 1, y * 2 + 1)) /
                    4)
                .round();
      }
    }
    levels.add(GrayFrame(w, h, bytes));
  }
  return levels;
}

/// A snapshot is immutable across isolates. Corner identities advance only with
/// forward/backward-consistent flow and a consensus transform, never on loss.
class SubjectTrackSnapshot {
  const SubjectTrackSnapshot._(
    this.pyramid,
    this.anchor,
    this.points,
    this.reference,
    this.scale,
    this.zoom,
  );
  final List<GrayFrame> pyramid;
  final Point2 anchor;
  final List<Point2> points;
  final SubjectTemplate? reference;
  final double scale;
  final double zoom;

  static SubjectTrackSnapshot? capture(
    GrayFrame frame,
    Point2 anchor, {
    double zoom = 1,
  }) {
    final points = _corners(frame, anchor, .14, .13);
    if (points.length < 4) {
      // A click on a smooth trunk can use nearby branches/corners while keeping
      // the original clicked anchor. A featureless region is still untrackable.
      points.addAll(
        _corners(
          frame,
          anchor,
          .22,
          .20,
        ).where((p) => points.every((old) => old.distanceTo(p) > .025)),
      );
    }
    final reference = SubjectTemplate.capture(frame, anchor);
    if (points.length < 3 && reference == null) return null;
    return SubjectTrackSnapshot._(
      _pyramid(frame),
      anchor,
      points.take(24).toList(),
      reference,
      1,
      zoom,
    );
  }

  SubjectTrackUpdate advance(GrayFrame frame, {double? zoom}) {
    if (zoom != null && zoom != this.zoom) {
      if (!zoom.isFinite || zoom <= 0) return SubjectTrackUpdate(null, 0, this);
      final projected = _atZoom(zoom);
      if (projected == null) return SubjectTrackUpdate(null, 0, this);
      // Reproject the verified old pixels, never seed an identity from the new
      // scene. A real image match is still required before showing a lock.
      final update = projected._advance(frame, predictMotion: false);
      if (update.point == null) return SubjectTrackUpdate(null, 0, this);
      // Lens resampling can introduce a small flow offset on each zoom step.
      // When the unchanged selection template still matches very closely,
      // anchor to it so repeated in/out adjustments cannot accumulate drift.
      final match = reference?.match(
        frame,
        update.point!,
        searchRadius: .02,
        scale: update.snapshot.scale,
      );
      if (match?.point != null && match!.confidence >= .9) {
        final next = update.snapshot;
        return SubjectTrackUpdate(
          match.point,
          update.confidence,
          SubjectTrackSnapshot._(
            next.pyramid,
            match.point!,
            next.points,
            reference,
            next.scale,
            next.zoom,
          ),
        );
      }
      return update;
    }
    return _advance(frame);
  }

  SubjectTrackUpdate _advance(GrayFrame frame, {bool predictMotion = true}) {
    if (frame.width != pyramid.first.width ||
        frame.height != pyramid.first.height) {
      return SubjectTrackUpdate(null, 0, this);
    }
    final current = _pyramid(frame), w = frame.width, h = frame.height;
    // Repeated keys/text can give coarse whole-frame registration a strong
    // match one or more rows away. Try short local flow at the last verified
    // positions first, before asking global registration to predict a fast pan.
    var pairs = _flowPairs(
      pyramid.take(2).toList(),
      current.take(2).toList(),
      const Point2(0, 0),
    );
    final localModel = _consensus(pairs, w, h);
    final localInliers = localModel == null
        ? 0
        : pairs
              .where((p) => localModel.apply(p.$1).distanceTo(p.$2) * h < 2)
              .length;
    final localReliable =
        localModel != null &&
        localInliers >= math.max(6, points.length * .65) &&
        localModel.apply(anchor).distanceTo(anchor) * h < 8;
    // Zooming out reveals pixels absent from the old image. Do not let that
    // unknown border bias whole-frame registration away from the known crop.
    final motion = predictMotion && !localReliable
        ? _cameraMotion(pyramid.last, current.last)
        : const Point2(0, 0);
    final factor = math.pow(2, pyramid.length - 1).toDouble();
    final predicted = Point2(motion.x * factor / w, motion.y * factor / h);
    if (!localReliable) {
      pairs = _flowPairs(pyramid, current, predicted);
    }
    final model = localReliable ? localModel : _consensus(pairs, w, h);
    if (pairs.length >= 3) {
      if (model != null) {
        var nextAnchor = model.apply(anchor);
        // Corners can sit on one side of a smooth subject. Extrapolating their
        // rotation/scale to the click accumulates drift during perspective or
        // focus changes. Verify the clicked patch itself in both directions;
        // use the surrounding consensus only if that patch has no clear match.
        final refined = _flow(pyramid, current, anchor, nextAnchor, radius: 7);
        if (refined != null &&
            refined.distanceTo(nextAnchor) * h < 3 &&
            _correlation(pyramid.first, current.first, anchor, refined, 7) >
                .85) {
          final back = _flow(current, pyramid, refined, anchor, radius: 7);
          if (back != null && back.distanceTo(anchor) * h < .75) {
            nextAnchor = refined;
          }
        }
        if (nextAnchor.x < 0 ||
            nextAnchor.x > 1 ||
            nextAnchor.y < 0 ||
            nextAnchor.y > 1) {
          return SubjectTrackUpdate(null, 0, this);
        }
        final inliers = pairs
            .where((pair) => model.apply(pair.$1).distanceTo(pair.$2) * h < 2)
            .toList();
        if (inliers.length >= 3 && inliers.length / pairs.length >= .6) {
          final confidence =
              (.55 + .4 * inliers.length / math.max(4, points.length)).clamp(
                0.0,
                .95,
              );
          final nextScale = scale * model.size;
          var nextPoints = inliers.map((p) => p.$2).toList();
          // Refresh texture only after a verified movement consensus. The fixed
          // reference remains available for recovery and is never replaced.
          if (inliers.length >= 5 &&
              confidence >= .7 &&
              nextPoints.length < 18) {
            for (final p in _corners(frame, nextAnchor, .14, .13)) {
              if (nextPoints.every((old) => old.distanceTo(p) > .025)) {
                nextPoints.add(p);
              }
              if (nextPoints.length >= 24) break;
            }
          }
          final snapshot = SubjectTrackSnapshot._(
            current,
            nextAnchor,
            nextPoints,
            reference,
            nextScale,
            zoom,
          );
          return SubjectTrackUpdate(nextAnchor, confidence, snapshot);
        }
      }
    }
    // Recovery searches around camera-compensated position, including faster
    // pans. A strict original appearance check guards against background drift.
    if (reference != null) {
      final center = Point2(anchor.x + predicted.x, anchor.y + predicted.y);
      final match = reference!.match(
        frame,
        center,
        searchRadius: .16,
        scale: scale,
      );
      if (match.point != null && match.confidence >= .72) {
        final next = SubjectTrackSnapshot.capture(
          frame,
          match.point!,
          zoom: zoom,
        );
        if (next != null) {
          return SubjectTrackUpdate(
            match.point,
            match.confidence,
            SubjectTrackSnapshot._(
              next.pyramid,
              next.anchor,
              next.points,
              reference,
              scale,
              zoom,
            ),
          );
        }
      }
    }
    return SubjectTrackUpdate(null, 0, this);
  }

  List<(Point2, Point2)> _flowPairs(
    List<GrayFrame> from,
    List<GrayFrame> to,
    Point2 predicted,
  ) {
    final pairs = <(Point2, Point2)>[];
    for (final point in points) {
      final next = _flow(
        from,
        to,
        point,
        Point2(point.x + predicted.x, point.y + predicted.y),
      );
      if (next == null) continue;
      final back = _flow(to, from, next, point);
      if (back == null || back.distanceTo(point) * from.first.height > 1.5) {
        continue;
      }
      if (_correlation(from.first, to.first, point, next, 3) < .7) continue;
      pairs.add((point, next));
    }
    return pairs;
  }

  SubjectTrackSnapshot? _atZoom(double nextZoom) {
    final ratio = nextZoom / zoom;
    Point2 project(Point2 p) =>
        Point2(.5 + (p.x - .5) * ratio, .5 + (p.y - .5) * ratio);
    final nextAnchor = project(anchor);
    if (nextAnchor.x < 0 ||
        nextAnchor.x > 1 ||
        nextAnchor.y < 0 ||
        nextAnchor.y > 1) {
      return null;
    }
    final warped = [for (final level in pyramid) _zoomFrame(level, ratio)];
    return SubjectTrackSnapshot._(
      warped,
      nextAnchor,
      points
          .map(project)
          .where((p) => p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1)
          .toList(),
      reference,
      scale * ratio,
      nextZoom,
    );
  }
}

GrayFrame _zoomFrame(GrayFrame frame, double ratio) {
  final pixels = Uint8List(frame.pixels.length);
  for (int y = 0; y < frame.height; y++) {
    for (int x = 0; x < frame.width; x++) {
      final sx = frame.width / 2 + (x - frame.width / 2) / ratio;
      final sy = frame.height / 2 + (y - frame.height / 2) / ratio;
      pixels[y * frame.width +
          x] = sx < 0 || sy < 0 || sx >= frame.width || sy >= frame.height
          ? 128
          : frame.sample(sx, sy).round().clamp(0, 255);
    }
  }
  return GrayFrame(frame.width, frame.height, pixels);
}

class SubjectTrackUpdate {
  const SubjectTrackUpdate(this.point, this.confidence, this.snapshot);
  final Point2? point;
  final double confidence;
  final SubjectTrackSnapshot snapshot;
}

List<Point2> _corners(GrayFrame f, Point2 center, double rx, double ry) {
  final scored = <(double, Point2)>[];
  for (
    int y = math.max(4, ((center.y - ry) * f.height).round());
    y < math.min(f.height - 4, (center.y + ry) * f.height);
    y += 2
  ) {
    for (
      int x = math.max(4, ((center.x - rx) * f.width).round());
      x < math.min(f.width - 4, (center.x + rx) * f.width);
      x += 2
    ) {
      double xx = 0, xy = 0, yy = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final gx = (f.at(x + dx + 1, y + dy) - f.at(x + dx - 1, y + dy)) / 2;
          final gy = (f.at(x + dx, y + dy + 1) - f.at(x + dx, y + dy - 1)) / 2;
          xx += gx * gx;
          xy += gx * gy;
          yy += gy * gy;
        }
      }
      final eigen =
          (xx + yy - math.sqrt(math.pow(xx - yy, 2) + 4 * xy * xy)) / 2;
      if (eigen > 60) scored.add((eigen, Point2(x / f.width, y / f.height)));
    }
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  final points = <Point2>[];
  for (final pair in scored) {
    if (points.every((p) => p.distanceTo(pair.$2) * f.height >= 4)) {
      points.add(pair.$2);
    }
    if (points.length == 24) break;
  }
  return points;
}

/// Coarse normalized image registration predicts camera panning; local flow
/// then measures the selected region independently of the rest of the scene.
Point2 _cameraMotion(GrayFrame a, GrayFrame b) {
  double best = -.2;
  var motion = const Point2(0, 0);
  final radiusX = (a.width * .35).round(), radiusY = (a.height * .35).round();
  for (int dy = -radiusY; dy <= radiusY; dy++) {
    for (int dx = -radiusX; dx <= radiusX; dx++) {
      double sa = 0, sb = 0, aa = 0, bb = 0, ab = 0;
      int count = 0;
      for (int y = 1; y < a.height - 1; y += 2) {
        for (int x = 1; x < a.width - 1; x += 2) {
          if (x + dx < 1 ||
              x + dx >= b.width - 1 ||
              y + dy < 1 ||
              y + dy >= b.height - 1) {
            continue;
          }
          final av = a.at(x, y), bv = b.at(x + dx, y + dy);
          sa += av;
          sb += bv;
          aa += av * av;
          bb += bv * bv;
          ab += av * bv;
          count++;
        }
      }
      if (count < a.width * a.height * .1) continue;
      final va = aa - sa * sa / count, vb = bb - sb * sb / count;
      if (va < count * 4 || vb < count * 4) continue;
      final corr = (ab - sa * sb / count) / math.sqrt(va * vb);
      // Tiny overlap can coincidentally match; prefer well-supported shifts.
      final score = corr - .03 * (dx.abs() / a.width + dy.abs() / a.height);
      if (score > best) {
        best = score;
        motion = Point2(dx.toDouble(), dy.toDouble());
      }
    }
  }
  return best > .45 ? motion : const Point2(0, 0);
}

Point2? _flow(
  List<GrayFrame> from,
  List<GrayFrame> to,
  Point2 source,
  Point2 guess, {
  int radius = 3,
}) {
  double px = 0, py = 0;
  for (int level = from.length - 1; level >= 0; level--) {
    final a = from[level], b = to[level];
    final sx = source.x * a.width, sy = source.y * a.height;
    if (level == from.length - 1) {
      px = guess.x * b.width;
      py = guess.y * b.height;
    } else {
      px *= 2;
      py *= 2;
    }
    if (sx < radius + 1 ||
        sy < radius + 1 ||
        sx > a.width - radius - 2 ||
        sy > a.height - radius - 2) {
      continue;
    }
    double xx = 0, xy = 0, yy = 0;
    final values = <double>[], gradients = <Point2>[];
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        values.add(a.sample(sx + dx, sy + dy));
        final gx =
            (a.sample(sx + dx + 1, sy + dy) - a.sample(sx + dx - 1, sy + dy)) /
            2;
        final gy =
            (a.sample(sx + dx, sy + dy + 1) - a.sample(sx + dx, sy + dy - 1)) /
            2;
        gradients.add(Point2(gx, gy));
        xx += gx * gx;
        xy += gx * gy;
        yy += gy * gy;
      }
    }
    final determinant = xx * yy - xy * xy;
    if (determinant < 100) continue;
    final sourceMean = values.reduce((a, b) => a + b) / values.length;
    final sourceEnergy = values.fold(
      0.0,
      (sum, value) => sum + math.pow(value - sourceMean, 2),
    );
    for (int iteration = 0; iteration < 15; iteration++) {
      if (px < radius ||
          py < radius ||
          px > b.width - radius - 1 ||
          py > b.height - radius - 1) {
        return null;
      }
      final samples = <double>[];
      double mean = 0;
      for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
          final value = b.sample(px + dx, py + dy);
          samples.add(value);
          mean += value;
        }
      }
      mean /= samples.length;
      final energy = samples.fold(
        0.0,
        (sum, value) => sum + math.pow(value - mean, 2),
      );
      if (energy < samples.length * 4) return null;
      // Normalize both brightness and contrast. Camera auto-exposure and a
      // brief blur can change contrast while the selected texture stays put.
      final gain = math.sqrt(sourceEnergy / energy);
      double bx = 0, by = 0;
      for (int i = 0; i < samples.length; i++) {
        final error = (samples[i] - mean) * gain - (values[i] - sourceMean);
        bx += gradients[i].x * error;
        by += gradients[i].y * error;
      }
      final dx = ((xy * by - yy * bx) / determinant).clamp(-3.0, 3.0);
      final dy = ((xy * bx - xx * by) / determinant).clamp(-3.0, 3.0);
      px += dx;
      py += dy;
      if (dx * dx + dy * dy < .0025) break;
    }
  }
  if (px < 0 || py < 0 || px >= to.first.width || py >= to.first.height) {
    return null;
  }
  return Point2(px / to.first.width, py / to.first.height);
}

double _correlation(GrayFrame a, GrayFrame b, Point2 p, Point2 q, int radius) {
  double sa = 0, sb = 0, aa = 0, bb = 0, ab = 0;
  final count = (radius * 2 + 1) * (radius * 2 + 1);
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      final av = a.sample(p.x * a.width + x, p.y * a.height + y);
      final bv = b.sample(q.x * b.width + x, q.y * b.height + y);
      sa += av;
      sb += bv;
      aa += av * av;
      bb += bv * bv;
      ab += av * bv;
    }
  }
  final va = aa - sa * sa / count, vb = bb - sb * sb / count;
  return va <= 1 || vb <= 1 ? 0 : (ab - sa * sb / count) / math.sqrt(va * vb);
}

class _Similarity {
  const _Similarity(this.a, this.b, this.tx, this.ty, {this.aspect = 1});
  final double a, b, tx, ty, aspect;
  double get size => math.sqrt(a * a + b * b);
  Point2 apply(Point2 p) =>
      Point2(a * p.x - b * p.y * aspect + tx, b * p.x / aspect + a * p.y + ty);
}

_Similarity? _consensus(List<(Point2, Point2)> pairs, int w, int h) {
  // Work in pixels for an isotropic rotation/scale fit on a 3:4 viewport.
  final pixelPairs = pairs
      .map(
        (p) => (Point2(p.$1.x * w, p.$1.y * h), Point2(p.$2.x * w, p.$2.y * h)),
      )
      .toList();
  _Similarity? best;
  var bestInliers = <(Point2, Point2)>[];
  for (int i = 0; i < pixelPairs.length; i++) {
    for (int j = i + 1; j < pixelPairs.length; j++) {
      final p = pixelPairs[i], q = pixelPairs[j];
      final dx = q.$1.x - p.$1.x, dy = q.$1.y - p.$1.y;
      final ex = q.$2.x - p.$2.x, ey = q.$2.y - p.$2.y;
      final denominator = dx * dx + dy * dy;
      if (denominator < 36) continue;
      final a = (dx * ex + dy * ey) / denominator,
          b = (dx * ey - dy * ex) / denominator;
      final model = _Similarity(
        a,
        b,
        p.$2.x - a * p.$1.x + b * p.$1.y,
        p.$2.y - b * p.$1.x - a * p.$1.y,
      );
      if (model.size < .75 || model.size > 1.3 || b.abs() > .3) continue;
      final inliers = pixelPairs.where((pair) {
        final prediction = model.apply(pair.$1);
        return math.pow(prediction.x - pair.$2.x, 2) +
                math.pow(prediction.y - pair.$2.y, 2) <
            4;
      }).toList();
      if (inliers.length > bestInliers.length) {
        best = model;
        bestInliers = inliers;
      }
    }
  }
  if (best == null || bestInliers.length < 3) return null;
  final cx =
      bestInliers.map((p) => p.$1.x).reduce((a, b) => a + b) /
      bestInliers.length;
  final cy =
      bestInliers.map((p) => p.$1.y).reduce((a, b) => a + b) /
      bestInliers.length;
  final qx =
      bestInliers.map((p) => p.$2.x).reduce((a, b) => a + b) /
      bestInliers.length;
  final qy =
      bestInliers.map((p) => p.$2.y).reduce((a, b) => a + b) /
      bestInliers.length;
  double numeratorA = 0, numeratorB = 0, denominator = 0;
  for (final p in bestInliers) {
    final x = p.$1.x - cx, y = p.$1.y - cy, u = p.$2.x - qx, v = p.$2.y - qy;
    numeratorA += x * u + y * v;
    numeratorB += x * v - y * u;
    denominator += x * x + y * y;
  }
  if (denominator < 1) return null;
  final a = numeratorA / denominator, b = numeratorB / denominator;
  return _Similarity(
    a,
    b,
    (qx - a * cx + b * cy) / w,
    (qy - b * cx - a * cy) / h,
    aspect: h / w,
  );
}
