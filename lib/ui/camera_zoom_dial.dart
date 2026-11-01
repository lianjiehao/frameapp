import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, lerpDouble;

import 'package:flutter/material.dart';

import '../services/camera_zoom.dart';

// Painting and gestures share the same angular scale. Finger travel therefore
// moves the graduations by the same distance, regardless of the camera limits.
const _wheelRadiusFactor = .56;
const _radiansPerLog = .58;
const _zoomAccent = Color(0xFFFFC129);
const _zoomPaper = Color(0xFFF2F0E7);

/// Zoom gestures and controls layered over the entire native viewfinder.
class CameraZoomDial extends StatefulWidget {
  const CameraZoomDial({
    super.key,
    required this.range,
    required this.value,
    required this.onChanged,
    this.onPreviewTap,
    this.onGestureStart,
    this.onGestureEnd,
    this.bottomTrailing,
  });

  final CameraZoomRange range;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<Offset>? onPreviewTap;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;
  // Passive preview information gives way to the arc's outer graduations.
  final Widget? bottomTrailing;

  @override
  State<CameraZoomDial> createState() => _CameraZoomDialState();
}

class _CameraZoomDialState extends State<CameraZoomDial>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 160),
  );
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final AnimationController _selection = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 2,
    value: _selectedIndex.toDouble(),
    duration: const Duration(milliseconds: 150),
  );
  late final Listenable _animations = Listenable.merge([
    _reveal,
    _collapse,
    _selection,
  ]);
  Timer? _dismissTimer;
  final _pointers = <int>{};
  bool _expanded = false;
  bool _pinching = false;
  bool _dragEligible = false;
  bool _zoomGestureActive = false;
  bool _dismissOnTap = false;
  Offset _origin = Offset.zero;
  Offset _lastFocal = Offset.zero;
  late double _displayValue = widget.value;
  double _lastPinchScale = 1;

  static const _barBottom = 46.0;
  static const _barHeight = 32.0;
  static const _slotWidth = 34.0;
  static const _barWidth = _slotWidth * 3 + 8;
  static const _selectedWidth = _barWidth - 2 * _slotWidth;
  List<double> get _presets => widget.range.quickStops;
  static const _digits = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  int get _selectedIndex => widget.range.slotFor(_displayValue);
  bool _supported(double value) =>
      value >= widget.range.min && value <= widget.range.max;

  Rect _barRect(Size size) => Rect.fromLTWH(
    (size.width - _barWidth) / 2,
    size.height - _barBottom - _barHeight,
    _barWidth,
    _barHeight,
  );

  double _arcHeight(Size size) => size.width * .34 + 12;

  bool _overArc(Offset point, Size size) {
    final local = point - Offset(0, size.height - _arcHeight(size));
    final radius = size.width * _wheelRadiusFactor;
    return local.dy >= 0 &&
        (local - Offset(size.width / 2, radius + 8)).distance <= radius;
  }

  @override
  void didUpdateWidget(covariant CameraZoomDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Native acknowledgements may arrive after a newer pointer event. During
    // a gesture, only the latest finger position drives the displayed value.
    final rangeChanged =
        oldWidget.range.min != widget.range.min ||
        oldWidget.range.max != widget.range.max;
    if (!_zoomGestureActive &&
        (_displayValue != widget.value || rangeChanged)) {
      _displayValue = widget.value;
      _selection.animateTo(
        _selectedIndex.toDouble(),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _setExpanded(bool value) {
    _dismissTimer?.cancel();
    if (_expanded == value) return;
    setState(() => _expanded = value);
    if (value) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
  }

  void _changeZoom(double value) {
    final next = widget.range.clamp(value);
    if (next == _displayValue) return;
    final oldIndex = _selectedIndex;
    setState(() => _displayValue = next);
    if (oldIndex != _selectedIndex) {
      _selection.animateTo(
        _selectedIndex.toDouble(),
        curve: Curves.easeOutCubic,
      );
    }
    widget.onChanged(next);
  }

  void _choosePreset(double value) {
    if (!_supported(value) || value == _displayValue) return;
    _beginZoomGesture();
    _changeZoom(value);
    _finishZoomGesture();
  }

  void _pointerDown(PointerDownEvent event, Size size) {
    _dismissTimer?.cancel();
    if (_pointers.isEmpty) {
      _origin = _lastFocal = event.localPosition;
      _dismissOnTap = _expanded;
      _dragEligible = _expanded
          ? _overArc(_origin, size)
          : _barRect(size).inflate(8).contains(_origin);
    }
    _pointers.add(event.pointer);
    if (_pointers.length > 1 && !_pinching) {
      setState(() => _pinching = true);
      _collapse.forward();
      _setExpanded(false);
    }
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;
    _finishZoomGesture();
    if (_pinching) {
      setState(() => _pinching = false);
      _collapse.reverse();
    }
    if (_expanded) {
      _dismissTimer = Timer(const Duration(seconds: 1), () {
        if (mounted && _pointers.isEmpty) _setExpanded(false);
      });
    }
  }

  void _beginZoomGesture() {
    if (_zoomGestureActive) return;
    _zoomGestureActive = true;
    widget.onGestureStart?.call();
  }

  void _finishZoomGesture() {
    if (!_zoomGestureActive) return;
    _zoomGestureActive = false;
    widget.onGestureEnd?.call();
  }

  void _scaleStart(ScaleStartDetails details, Size size) {
    _lastFocal = details.localFocalPoint;
    _lastPinchScale = 1;
    if (details.pointerCount >= 2) {
      _beginZoomGesture();
    } else if (!_pinching && _dragEligible) {
      final delta = details.localFocalPoint - _origin;
      if (!_expanded && delta.dx.abs() <= delta.dy.abs()) return;
      _beginZoomGesture();
      // Expand at the exact current value. The touch-slop distance is not a
      // zoom command; applying it here would visibly jump on first contact.
      _setExpanded(true);
    }
  }

  void _scaleUpdate(ScaleUpdateDetails details, Size size) {
    if (details.pointerCount >= 2) {
      _beginZoomGesture();
      if (_lastPinchScale > 0 && details.scale > 0) {
        _changeZoom(_displayValue * details.scale / _lastPinchScale);
      }
      _lastPinchScale = details.scale;
    } else if (!_pinching && _dragEligible && _zoomGestureActive) {
      final dx = details.localFocalPoint.dx - _lastFocal.dx;
      final radius = size.width * _wheelRadiusFactor;
      if (radius > 0) {
        // Incremental, clamped input allows immediate reversal at either end.
        // Dragging left rotates the scale left and brings larger values in.
        _changeZoom(_displayValue * math.exp(-dx / (radius * _radiansPerLog)));
      }
    }
    _lastFocal = details.localFocalPoint;
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _reveal.dispose();
    _collapse.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.range.isAdjustable) return const SizedBox.shrink();
    return TapRegion(
      onTapOutside: (_) => _setExpanded(false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final barRect = _barRect(size);
          return Listener(
            onPointerDown: (event) => _pointerDown(event, size),
            onPointerUp: _pointerUp,
            onPointerCancel: _pointerUp,
            child: GestureDetector(
              key: const Key('camera-zoom-dial'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (_dismissOnTap || _expanded) {
                  _setExpanded(false);
                } else if (!barRect
                    .inflate(8)
                    .contains(details.localPosition)) {
                  widget.onPreviewTap?.call(details.localPosition);
                }
              },
              onScaleStart: (details) => _scaleStart(details, size),
              onScaleUpdate: (details) => _scaleUpdate(details, size),
              child: AnimatedBuilder(
                animation: _animations,
                builder: (context, _) {
                  final progress = Curves.easeOutCubic.transform(_reveal.value);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.bottomTrailing != null)
                        Positioned(
                          right: 13,
                          bottom: 13,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 1 - progress,
                              child: widget.bottomTrailing,
                            ),
                          ),
                        ),
                      Positioned.fromRect(
                        rect: barRect,
                        child: IgnorePointer(
                          ignoring: _expanded || _pinching,
                          child: Opacity(
                            opacity: 1 - progress,
                            child: _quickButtons(),
                          ),
                        ),
                      ),
                      if (_expanded || _reveal.value > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _arcHeight(size),
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: progress,
                              child: Transform.translate(
                                offset: Offset(0, 16 * (1 - progress)),
                                child: RepaintBoundary(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CustomPaint(
                                        key: const Key('camera-zoom-arc'),
                                        painter: _ZoomArcPainter(
                                          range: widget.range,
                                          value: _displayValue,
                                        ),
                                      ),
                                      Positioned(
                                        top: 34,
                                        left: 0,
                                        right: 0,
                                        child: Center(
                                          child: Text(
                                            widget.range.format(_displayValue),
                                            key: const Key('camera-zoom-value'),
                                            style: _digits.copyWith(
                                              color: _zoomAccent,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _quickButtons() {
    final collapse = Curves.easeInOutCubic.transform(_collapse.value);
    final width = lerpDouble(_barWidth, _selectedWidth, collapse)!;
    final activeX = lerpDouble(
      (_selection.value - 1) * _slotWidth,
      0,
      collapse,
    )!;
    return Center(
      child: Semantics(
        label: '相机倍率 ${widget.range.format(_displayValue)}',
        child: SizedBox(
          key: const Key('camera-zoom-bar'),
          width: width,
          height: _barHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(_barHeight / 2),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left:
                        width / 2 +
                        (i - 1) * _slotWidth * (1 - collapse) -
                        _slotWidth / 2,
                    top: 0,
                    width: _slotWidth,
                    height: _barHeight,
                    child: Semantics(
                      button: true,
                      enabled: _supported(_presets[i]),
                      selected: i == _selectedIndex,
                      label: '${_presets[i]}×',
                      child: GestureDetector(
                        key: Key('zoom-quick-${_presets[i]}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _supported(_presets[i])
                            ? () => _choosePreset(_presets[i])
                            : null,
                        child: Center(
                          child: i == _selectedIndex || collapse == 1
                              ? const SizedBox.shrink()
                              : Opacity(
                                  opacity:
                                      (1 - collapse) *
                                      ((i - 1) * _slotWidth - activeX)
                                          .abs()
                                          .clamp(0, _slotWidth) /
                                      _slotWidth,
                                  child: Text(
                                    widget.range.stopLabel(_presets[i]),
                                    style: _digits.copyWith(
                                      color: _zoomPaper.withValues(
                                        alpha: _supported(_presets[i]) ? 1 : .3,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(activeX, 0),
                  child: IgnorePointer(
                    child: Container(
                      key: Key('zoom-active-slot-$_selectedIndex'),
                      width: _selectedWidth,
                      height: _barHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_barHeight / 2),
                        color: Colors.black.withValues(
                          alpha: .24 * (1 - collapse),
                        ),
                      ),
                      child: Text(
                        widget.range.format(_displayValue),
                        key: const Key('camera-zoom-bar-value'),
                        style: _digits.copyWith(color: _zoomAccent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomArcPainter extends CustomPainter {
  const _ZoomArcPainter({required this.range, required this.value});

  final CameraZoomRange range;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width * _wheelRadiusFactor;
    final center = Offset(size.width / 2, radius + 8);
    final disc = Rect.fromCircle(center: center, radius: radius);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Only the circular silhouette is tinted; the preview remains visible
    // through the disc and completely clear outside its curved edge.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: .28),
            Colors.black.withValues(alpha: .48),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawArc(
      disc,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = _zoomPaper.withValues(alpha: .10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5,
    );

    final logValue = math.log(value);
    double angleFor(double logTick) => (logTick - logValue) * _radiansPerLog;
    Offset point(double angle, double distance) =>
        center + Offset(math.sin(angle), -math.cos(angle)) * distance;

    // Dense, evenly spaced logarithmic graduations rotate beneath the fixed
    // index. Relative drag input preserves the value when re-grabbing the arc.
    final minLog = math.log(range.min), maxLog = math.log(range.max);
    const step = .025;
    for (var i = (minLog / step).ceil(); i <= (maxLog / step).floor(); i++) {
      final angle = angleFor(i * step);
      if (angle.abs() > 1.3) continue;
      final major = i % 10 == 0;
      final medium = i % 5 == 0;
      final fade = (1 - angle.abs() / 1.7).clamp(.15, 1.0);
      final length = major ? 11.0 : (medium ? 8.0 : 5.0);
      canvas.drawLine(
        point(angle, radius - 7),
        point(angle, radius - 7 - length),
        Paint()
          ..color = _zoomPaper.withValues(alpha: (major ? .7 : .34) * fade)
          ..strokeWidth = major ? .9 : .55,
      );
    }

    for (final preset in range.dialStops) {
      final angle = angleFor(math.log(preset));
      if (angle.abs() > 1.25) continue;
      canvas.drawLine(
        point(angle, radius - 7),
        point(angle, radius - 21),
        Paint()
          ..color = _zoomPaper.withValues(alpha: .82)
          ..strokeWidth = 1.1,
      );
      // Leave room for the live value beneath the central yellow index.
      if (angle.abs() < .2) continue;
      final label = TextPainter(
        text: TextSpan(
          text: range.stopLabel(preset),
          style: TextStyle(
            color: _zoomPaper.withValues(alpha: .9),
            fontFamily: 'FrameSans',
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final position = point(angle, radius - 35);
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle);
      label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
      canvas.restore();
      label.dispose();
    }

    canvas.drawLine(
      Offset(center.dx, 16),
      Offset(center.dx, 28),
      Paint()
        ..color = _zoomAccent
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ZoomArcPainter oldDelegate) =>
      oldDelegate.range.min != range.min ||
      oldDelegate.range.max != range.max ||
      oldDelegate.value != value;
}
