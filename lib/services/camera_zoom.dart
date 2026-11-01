import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

typedef CameraZoomApplier = Future<void> Function(double value);

class CameraZoomRange {
  const CameraZoomRange({required this.min, required this.max});

  final double min;
  final double max;

  bool get isAdjustable => max - min > .01;

  double clamp(double value) => value.clamp(min, max).toDouble();

  double toProgress(double value) {
    if (!isAdjustable) return 0;
    return (math.log(clamp(value)) - math.log(min)) /
        (math.log(max) - math.log(min));
  }

  double fromProgress(double progress) {
    if (!isAdjustable) return min;
    final logMin = math.log(min), logMax = math.log(max);
    return math.exp(logMin + (logMax - logMin) * progress.clamp(0.0, 1.0));
  }

  List<double> get quickStops {
    if (!isAdjustable) return [min];
    // Spread quick choices over the logarithmic range, rounding down to
    // familiar values. A 1–10× camera gets 1 / 2 / 4; a 1–20× camera 1 / 2 / 6.
    var middle = _roundStopDown(fromProgress(1 / 3));
    if (middle <= min) middle = clamp(min * 2);
    final last = clamp(
      math.max(_roundStopDown(fromProgress(2 / 3)), middle * 2),
    );
    if (middle >= last) return [min, (min + max) / 2, max];
    return [min, middle, last];
  }

  int slotFor(double value) {
    final stops = quickStops;
    if (stops.length < 3 || value < stops[1]) return 0;
    return value < stops[2] ? 1 : 2;
  }

  List<double> get dialStops {
    final values = <double>{...quickStops, min, max};
    if (!isAdjustable) return values.toList();
    final firstDecade = (math.log(min) / math.ln10).floor();
    final lastDecade = (math.log(max) / math.ln10).ceil();
    for (var decade = firstDecade; decade <= lastDecade; decade++) {
      final unit = math.pow(10, decade).toDouble();
      for (final factor in const [1, 2, 4, 6, 8]) {
        final candidate = factor * unit;
        if (candidate <= min || candidate >= max) continue;
        // Keep range endpoints and bar stops; avoid crowding them with labels.
        if (values.any(
          (v) => math.max(v, candidate) / math.min(v, candidate) < 1.45,
        )) {
          continue;
        }
        values.add(candidate);
      }
    }
    return values.toList()..sort();
  }

  static double _roundStopDown(double value) {
    final unit = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
    const factors = [1, 2, 3, 4, 5, 6, 8];
    return factors.lastWhere(
          (factor) => factor * unit <= value,
          orElse: () => 1,
        ) *
        unit;
  }

  String stopLabel(double value) => _trimZeros(value.toStringAsFixed(3));

  static String _trimZeros(String value) =>
      value.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  String format(double value) {
    final precision = max - min < .1 ? 3 : (max - min < 1 ? 2 : 1);
    return '${_trimZeros(clamp(value).toStringAsFixed(precision))}×';
  }
}

class CameraZoomState extends ChangeNotifier {
  CameraZoomState({this.onChanged, this.onSettled});

  final void Function()? onChanged;
  void Function(bool requested)? onSettled;
  CameraZoomRange range = const CameraZoomRange(min: 1, max: 1);
  double value = 1;
  double _applied = 1;
  double? _pending;
  CameraZoomApplier? _apply;
  bool busy = false, lastRequestFailed = false, _anyApplied = false;
  bool _gestureActive = false, _settledPending = false;
  int _epoch = 0;

  bool get available => range.isAdjustable;
  bool get isAdjusting => busy || _gestureActive;

  void configure(double min, double max, {double initial = 1}) {
    reset();
    if (!min.isFinite || !max.isFinite || min <= 0 || max < min) return;
    range = CameraZoomRange(min: min, max: max);
    value = _applied = range.clamp(initial);
    _changed();
  }

  void request(double requested, CameraZoomApplier apply) {
    if (!available || !requested.isFinite) return;
    final next = range.clamp(requested);
    // Every value accepted by the overlay must reach the camera. Even a tiny
    // delta can cross a displayed tenth or a preset-slot boundary.
    if (!busy && next == value) return;
    value = next;
    _pending = next;
    _apply = apply;
    lastRequestFailed = false;
    if (!busy) {
      busy = true;
      if (!_gestureActive) _anyApplied = false;
      unawaited(_drain(_epoch));
    }
    _changed();
  }

  void beginGesture() {
    if (!available || _gestureActive) return;
    _gestureActive = true;
    _settledPending = false;
    _anyApplied = false;
    _changed();
  }

  void endGesture() {
    if (!_gestureActive) return;
    _gestureActive = false;
    if (!busy && _settledPending) {
      _settledPending = false;
      onSettled?.call(_anyApplied);
    }
    _changed();
  }

  Future<void> _drain(int epoch) async {
    while (epoch == _epoch && _pending != null) {
      final target = _pending!;
      _pending = null;
      try {
        await _apply!(target);
        if (epoch != _epoch) return;
        _applied = target;
        _anyApplied = true;
      } catch (_) {
        if (epoch != _epoch) return;
        lastRequestFailed = true;
        if (_pending == null) value = _applied;
      }
    }
    if (epoch != _epoch) return;
    busy = false;
    value = _applied;
    if (_gestureActive) {
      _settledPending = true;
    } else {
      onSettled?.call(_anyApplied);
    }
    _changed();
  }

  void _changed() {
    notifyListeners();
    onChanged?.call();
  }

  @override
  void dispose() {
    _epoch++;
    _pending = null;
    _apply = null;
    super.dispose();
  }

  void reset() {
    _epoch++;
    _pending = null;
    _apply = null;
    range = const CameraZoomRange(min: 1, max: 1);
    value = _applied = 1;
    busy = false;
    lastRequestFailed = false;
    _anyApplied = false;
    _gestureActive = false;
    _settledPending = false;
    _changed();
  }
}
