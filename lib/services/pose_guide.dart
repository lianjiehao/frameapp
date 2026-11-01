import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'pose_detector.dart';
export 'pose_detector_api.dart';

typedef PoseSample = Future<PosePixels> Function();

/// One running job and one latest pending camera frame. Reference changes,
/// pauses, lens/zoom changes and disposal invalidate in-flight results.
class PoseGuide extends ChangeNotifier {
  PoseGuide({PoseDetector? detector, DateTime Function()? now})
    : _detector = detector ?? createPoseDetector(),
      _now = now ?? DateTime.now;
  final PoseDetector _detector;
  final DateTime Function() _now;
  final PoseHold _hold = PoseHold();
  bool _active = false,
      _disposed = false,
      _busy = false,
      _referenceResolved = false;
  int _epoch = 0;
  String? _id;
  Uint8List? _bytes;
  bool _mirror = false;
  BodyPose? _reference;
  (PoseSample, DateTime)? _pending;
  String _hint = '选择参考图后对齐人体';
  bool get hasReference => _bytes != null;
  bool get ready => _active && _hold.ready && _hold.fresh(_now());
  double get progress => _active && _hold.fresh(_now()) ? _hold.progress : 0;
  String get hint => _hint;
  bool shaking = false;

  void setReference(String? id, Uint8List? bytes, {bool mirror = false}) {
    if (_disposed ||
        (id == _id && identical(bytes, _bytes) && mirror == _mirror)) {
      return;
    }
    _id = id;
    _bytes = bytes;
    _mirror = mirror;
    _reference = null;
    _referenceResolved = false;
    invalidate();
    _hint = bytes == null ? '选择参考图后对齐人体' : '正在识别参考图人体';
    _notify();
    unawaited(_drain());
  }

  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    shaking = false;
    invalidate();
    if (value) {
      if (_reference == null) _referenceResolved = false;
      unawaited(_drain());
    } else if (!_busy) {
      unawaited(_detector.close());
    }
  }

  void invalidate() {
    _epoch++;
    _hold.reset();
    _pending = null;
    if (_reference?.usable == true) _hint = '让身体与参考图重合，保持 1 秒';
    _notify();
  }

  void setShaking(bool value) {
    if (shaking == value) return;
    shaking = value;
    if (value) {
      invalidate();
      _hint = '请稳住手机，再对齐人体';
      _notify();
    }
  }

  void checkFreshness() {
    if (_hold.progress > 0 && !_hold.fresh(_now())) {
      _hold.reset();
      _hint = '等待新画面，请保持人体入镜';
      _notify();
    }
  }

  void submit(PoseSample sample, DateTime capturedAt) {
    if (!_active || _disposed || _bytes == null) return;
    _pending = (sample, capturedAt);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_busy || !_active || _disposed || _bytes == null) return;
    _busy = true;
    try {
      while (_active && !_disposed && _bytes != null) {
        final epoch = _epoch;
        if (!_referenceResolved) {
          final bytes = _bytes!, mirror = _mirror;
          try {
            final codec = await ui.instantiateImageCodec(bytes);
            ui.Image? image;
            late PosePixels pixels;
            try {
              image = (await codec.getNextFrame()).image;
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              if (data == null) throw StateError('Unable to decode reference');
              pixels = await compute(samplePoseReference, (
                width: image.width,
                height: image.height,
                rgba: data.buffer.asUint8List(),
                mirror: mirror,
              ));
            } finally {
              image?.dispose();
              codec.dispose();
            }
            if (epoch != _epoch || !_active || _disposed) continue;
            final body = await _detector.detect(pixels);
            if (epoch != _epoch || !_active || _disposed) continue;
            _reference = body;
            _referenceResolved = true;
            _hint = body?.usable == true
                ? '让身体与参考图重合，保持 1 秒'
                : '参考图人体不清晰，请换图或直接拍照';
          } catch (_) {
            if (epoch != _epoch || !_active || _disposed) continue;
            _referenceResolved = true;
            _hint = '人体识别暂不可用，可直接拍照';
          }
          _notify();
        }
        final pending = _pending;
        _pending = null;
        if (pending == null || _reference?.usable != true) break;
        if (_now().difference(pending.$2) > PoseHold.freshness) continue;
        try {
          final pixels = await pending.$1();
          if (epoch != _epoch || !_active || _disposed) continue;
          final body = await _detector.detect(pixels);
          if (epoch != _epoch || !_active || _disposed) continue;
          if (_now().difference(pending.$2) > PoseHold.freshness) {
            _hold.reset();
            _hint = '等待新画面，请保持人体入镜';
          } else {
            final match = body == null
                ? const PoseMatch(false, '请让一个人完整进入画面')
                : compareBodyPoses(_reference!, body);
            _hold.accept(
              aligned: match.aligned && !shaking,
              capturedAt: pending.$2,
              now: _now(),
            );
            _hint = shaking
                ? '请稳住手机，再对齐人体'
                : ready
                ? '已对齐，可以拍照'
                : match.hint;
          }
        } catch (_) {
          if (epoch != _epoch || !_active || _disposed) continue;
          _hold.reset();
          _hint = '人体识别暂不可用，可直接拍照';
        }
        _notify();
      }
    } finally {
      _busy = false;
      if (!_active || _disposed) await _detector.close();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _epoch++;
    _pending = null;
    _bytes = null;
    _reference = null;
    _hold.reset();
    if (!_busy) unawaited(_detector.close());
    super.dispose();
  }
}
