import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../core/composition.dart';
import '../core/level.dart';
import '../core/scene_evidence.dart';
import '../core/pixel_buffer.dart';
import '../core/photo_filter.dart';
import '../core/vision.dart';
import 'gallery.dart';
import 'gallery_error.dart';
import 'camera_photo.dart';
import 'camera_zoom.dart';

enum CapturePhase {
  framing,
  analyzing,
  recommending,
  guiding,
  ready,
  capturing,
  captured,
}

typedef PhotoSaver = Future<void> Function(Uint8List, String);

// Native pixels and injected practice frames share one latest-frame queue.
// The raw plane is reduced in the same worker as tracking, not on the UI thread.
typedef _PreviewSource = ({GrayFrame? frame, CameraPlane? plane});
typedef _PreviewRequest = ({
  _PreviewSource source,
  SubjectTemplate? template,
  Point2? previous,
  bool selected,
  SubjectTrackSnapshot? tracking,
  double zoom,
});

GrayFrame _samplePreview(_PreviewSource source) =>
    source.frame ?? source.plane!.sample();

(GrayFrame, CompositionAnalysis) _analyzePreview(_PreviewRequest request) {
  final frame = _samplePreview(request.source);
  return (
    frame,
    analyzeComposition(
      AnalysisRequest(
        frame,
        request.template,
        request.previous,
        subjectLocked: request.selected,
        tracking: request.tracking,
        zoom: request.zoom,
      ),
    ),
  );
}

class CameraCoach extends ChangeNotifier {
  CameraCoach({
    bool? demo,
    PhotoSaver? saver,
    DateTime Function()? now,
    this.previewFrames,
    this.levelEvents,
  }) : isDemo = demo ?? (kIsWeb || const bool.fromEnvironment('DEMO_MODE')),
       _saver = saver ?? savePhoto,
       _now = now ?? DateTime.now {
    zoom = CameraZoomState(onChanged: _zoomChanged, onSettled: _zoomSettled);
  }
  final DateTime Function() _now;
  final PhotoSaver _saver;
  Future<bool> Function(bool explicit)? beforeSave;
  bool _saving = false;
  bool get saving => _saving;
  final Stream<GrayFrame>? previewFrames;
  final Stream<AccelerometerEvent>? levelEvents;
  StreamSubscription<GrayFrame>? _previewSubscription;
  bool isDemo,
      initialized = false,
      disposed = false,
      _busy = false,
      _opening = false;
  bool get canExitDemo =>
      !disposed &&
      isDemo &&
      !kIsWeb &&
      !const bool.fromEnvironment('DEMO_MODE');
  String? error, saveError;
  CapturePhase phase = CapturePhase.framing;
  CameraController? camera;
  late final CameraZoomState zoom;
  bool _zoomWasAdjusting = false, _zoomWasAvailable = false;
  List<CameraDescription> cameras = [];
  int cameraIndex = 0, _session = 0, _generation = 0;
  FlashMode flash = FlashMode.off;
  bool get canZoom =>
      !disposed &&
      !isDemo &&
      initialized &&
      camera?.description.lensDirection == CameraLensDirection.back &&
      zoom.available;
  SceneFeatures features = const SceneFeatures();
  List<CompositionPlan> plans = [];
  CompositionPlan? plan;
  SceneEvidence evidence = const SceneEvidence();
  String? get recommendationSummary {
    if (plans.isEmpty || plans.first.score < .4) return '适合度较低，可以重新点选主体或直接试拍。';
    if (plans.length > 1 && plans.first.score - plans[1].score < .08) {
      return '前两种构图分数接近，可以各试拍一张。';
    }
    return null;
  }

  AlignmentResult alignment = const AlignmentResult(
    false,
    0,
    0,
    '点一下想拍的主体',
    false,
  );
  final AlignmentTracker _alignment = AlignmentTracker();
  final SubjectLock subjectLock = SubjectLock();
  bool get _hasFreshFrame =>
      _frame != null &&
      _lastFrame != null &&
      _now().difference(_lastFrame!).inMilliseconds <= 850;
  bool get canRecommend =>
      !disposed &&
      initialized &&
      !zoom.isAdjusting &&
      phase == CapturePhase.framing &&
      subjectLock.state == SubjectState.tracking &&
      subjectLock.trackable &&
      _hasFreshFrame;
  final LevelFilter _levelFilter = LevelFilter();
  StreamSubscription<AccelerometerEvent>? _levelSubscription;
  LevelReading _level = const LevelReading(waiting: true);
  DateTime? _lastLevel, _lastLevelNotify;
  LevelReading get level {
    if (isDemo && levelEvents == null) return const LevelReading(angle: 0);
    if (!_level.available) return _level;
    if (_lastLevel == null ||
        _now().difference(_lastLevel!).inMilliseconds > 1000) {
      return const LevelReading(waiting: true);
    }
    return _level;
  }

  String get subjectLabel => switch (subjectLock.state) {
    SubjectState.unselected => '点选主体',
    SubjectState.tracking => '主体已锁定',
    SubjectState.lost => '主体跟丢了',
    SubjectState.needsDetail => '请点选清晰的轮廓',
  };
  String get subjectHint => switch (subjectLock.state) {
    SubjectState.unselected => '点一下画面中的人或物体',
    SubjectState.tracking =>
      plan == null
          ? '白框会跟随你选中的主体'
          : plan!.useHorizon
          ? '让横向分界对准虚线'
          : '移动手机，让绿圈中心进入选框',
    SubjectState.lost => '请点一下主体，重新锁定',
    SubjectState.needsDetail => '请点在主体清晰的轮廓上',
  };
  GrayFrame? _frame;
  Point2? _pendingSelection;
  bool get selectingSubject => _pendingSelection != null;
  double _frameZoom = 1;
  (_PreviewSource, DateTime)? _pendingFrame;
  DateTime? _lastFrame;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _demoTimer, _watchdog;
  ui.Image? demoImage;
  Uint8List? _demoPixels, photo;
  ui.Offset demoPan = const ui.Offset(-.12, -.08);
  bool saved = false;
  PhotoFilter _photoFilter = const PhotoFilter();
  PhotoFilter get photoFilter => _photoFilter;
  bool get canChangePhotoFilter =>
      !disposed &&
      initialized &&
      phase != CapturePhase.capturing &&
      phase != CapturePhase.captured;

  void selectPhotoStyle(PhotoStyle style) {
    if (!canChangePhotoFilter) return;
    _photoFilter = _photoFilter.copyWith(
      style: style,
      intensity: style == PhotoStyle.original ? 1 : _photoFilter.intensity,
    );
    _notify();
  }

  void setPhotoFilterIntensity(double value) {
    if (!canChangePhotoFilter || !value.isFinite) return;
    _photoFilter = _photoFilter.copyWith(intensity: value.clamp(0, 1));
    _notify();
  }

  void setPhotoAdjustment(PhotoAdjustment adjustment, double value) {
    if (!canChangePhotoFilter || !value.isFinite) return;
    final amount = value.clamp(-1.0, 1.0);
    _photoFilter = switch (adjustment) {
      PhotoAdjustment.brightness => _photoFilter.copyWith(brightness: amount),
      PhotoAdjustment.contrast => _photoFilter.copyWith(contrast: amount),
      PhotoAdjustment.saturation => _photoFilter.copyWith(saturation: amount),
      PhotoAdjustment.warmth => _photoFilter.copyWith(warmth: amount),
    };
    _notify();
  }

  void resetPhotoAdjustments() {
    if (!canChangePhotoFilter || !_photoFilter.hasAdjustments) return;
    _photoFilter = _photoFilter.copyWith(
      brightness: 0,
      contrast: 0,
      saturation: 0,
      warmth: 0,
    );
    _notify();
  }

  Future<void> initialize() async {
    if (_opening || disposed) {
      return;
    }
    _opening = true;
    error = null;
    final session = ++_session;
    try {
      if (isDemo) {
        if (demoImage == null) {
          final data = await rootBundle.load('assets/images/park.jpg');
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(),
          );
          demoImage = (await codec.getNextFrame()).image;
          codec.dispose();
          _demoPixels = (await demoImage!.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
        }
        if (disposed || session != _session) {
          return;
        }
        initialized = true;
        if (levelEvents != null) _startLevel();
        _frame = _sampleDemo();
        _frameZoom = zoom.value;
        features = const FrameAnalyzer().analyze(analysisFrame(_frame!));
        _lastFrame = _now();
        _demoTimer?.cancel();
        final frameSource = previewFrames;
        if (frameSource != null) {
          await _previewSubscription?.cancel();
          _previewSubscription = frameSource.listen(_acceptFrame);
        } else {
          _demoTimer = Timer.periodic(
            const Duration(milliseconds: 120),
            (_) => _acceptFrame(_sampleDemo()),
          );
        }
      } else {
        cameras = await availableCameras();
        if (cameras.isEmpty) {
          throw CameraException('NoCamera', '没有找到可用的相机');
        }
        if (cameraIndex >= cameras.length) {
          cameraIndex = 0;
        }
        final controller = CameraController(
          cameras[cameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420,
        );
        camera = controller;
        await controller.initialize();
        if (disposed || session != _session) {
          await controller.dispose();
          return;
        }
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        initialized = true;
        if (controller.description.lensDirection != CameraLensDirection.back) {
          zoom.reset();
        } else {
          try {
            final limits = await Future.wait([
              controller.getMinZoomLevel(),
              controller.getMaxZoomLevel(),
            ]);
            if (disposed || session != _session || camera != controller) {
              await controller.dispose();
              return;
            }
            zoom.configure(limits[0], limits[1]);
          } catch (_) {
            if (!disposed && session == _session && camera == controller) {
              zoom.configure(1, 1);
            }
          }
        }
        _startLevel();
        await _startStream(controller);
      }
      _watchdog?.cancel();
      _watchdog = Timer.periodic(const Duration(milliseconds: 350), (_) {
        if (phase == CapturePhase.framing &&
            subjectLock.state == SubjectState.tracking &&
            !_hasFreshFrame) {
          subjectLock.markLost();
          features = features.withSubject(null, 0);
          _notify();
        }
        if ((phase == CapturePhase.ready || phase == CapturePhase.guiding) &&
            (_lastFrame == null ||
                _now().difference(_lastFrame!).inMilliseconds > 850)) {
          _alignment.reset();
          subjectLock.markLost();
          features = features.withSubject(null, 0);
          phase = CapturePhase.guiding;
          alignment = AlignmentResult(
            false,
            0,
            0,
            _pendingSelection == null ? '稳住手机，等待画面恢复' : '正在重新锁定主体',
            false,
          );
          _notify();
        }
      });
    } on CameraException catch (e) {
      error = e.code.contains('Access')
          ? '请在系统设置中允许相机访问，然后重试。'
          : '相机暂时无法开启，请重试。';
      initialized = false;
      final failed = camera;
      camera = null;
      if (failed != null) {
        await failed.dispose();
      }
    } catch (_) {
      error = '无法载入取景画面，请重试。';
      initialized = false;
    } finally {
      _opening = false;
      _notify();
    }
  }

  void _startLevel() {
    _levelSubscription?.cancel();
    _levelFilter.reset();
    _lastLevel = null;
    _lastLevelNotify = null;
    _level = const LevelReading(waiting: true);
    _levelSubscription =
        (levelEvents ??
                accelerometerEventStream(
                  samplingPeriod: const Duration(milliseconds: 50),
                ))
            .listen(
              (event) {
                if (disposed || !initialized) return;
                final now = _now();
                _lastLevel = now;
                _level = _levelFilter.add(
                  event.x,
                  event.y,
                  event.z,
                  now,
                  frontCamera:
                      camera?.description.lensDirection ==
                      CameraLensDirection.front,
                );
                // Motion can revoke readiness; a constant camera tilt cannot. Only
                // fresh image frames accumulate a stable hold, never sensor callbacks.
                if (_level.blocksAlignment &&
                    (phase == CapturePhase.ready ||
                        phase == CapturePhase.guiding)) {
                  _alignment.reset();
                  phase = CapturePhase.guiding;
                  alignment = AlignmentResult(
                    false,
                    0,
                    alignment.accuracy,
                    '请稳住手机',
                    alignment.valid,
                  );
                }
                if (_lastLevelNotify == null ||
                    now.difference(_lastLevelNotify!).inMilliseconds >= 100) {
                  _lastLevelNotify = now;
                  _notify();
                }
              },
              onError: (Object _) {
                _level = const LevelReading(available: false);
                _notify();
              },
              cancelOnError: true,
            );
  }

  Future<void> _startStream(CameraController controller) async {
    if (disposed ||
        camera != controller ||
        controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream((image) {
      if (disposed ||
          phase == CapturePhase.capturing ||
          zoom.isAdjusting ||
          _now().difference(_lastAnalysis).inMilliseconds < 120) {
        return;
      }
      try {
        if (image.format.group != ImageFormatGroup.yuv420 &&
            image.format.group != ImageFormatGroup.bgra8888 &&
            image.format.group != ImageFormatGroup.nv21) {
          throw StateError('Unsupported image format');
        }
        final plane = image.planes.first;
        // Portrait is locked. Landscape native buffers need sensor rotation.
        final rotation = image.width > image.height
            ? controller.description.sensorOrientation
            : 0;
        final source = CameraPlane(
          bytes: plane.bytes,
          width: image.width,
          height: image.height,
          rowStride: plane.bytesPerRow,
          pixelStride:
              plane.bytesPerPixel ??
              (image.format.group == ImageFormatGroup.bgra8888 ? 4 : 1),
          bgra: image.format.group == ImageFormatGroup.bgra8888,
          rotation: rotation,
          mirror:
              controller.description.lensDirection == CameraLensDirection.front,
        );
        unawaited(_acceptPreview((frame: null, plane: source)));
      } catch (_) {
        error = '当前相机暂时无法提供构图引导，请尝试切换镜头。';
        subjectLock.markLost();
        features = features.withSubject(null, 0);
        _alignment.reset();
        if (phase == CapturePhase.ready) {
          phase = CapturePhase.guiding;
        }
        _notify();
      }
    });
  }

  ui.Rect get demoCrop {
    final image = demoImage!;
    final ch = image.height / 1.25, cw = ch * .75;
    final cx = (image.width * .72 - demoPan.dx * cw).clamp(
      cw / 2,
      image.width - cw / 2,
    );
    final cy = (image.height * .53 - demoPan.dy * ch).clamp(
      ch / 2,
      image.height - ch / 2,
    );
    return ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: cw, height: ch);
  }

  GrayFrame _sampleDemo() {
    final crop = demoCrop, image = demoImage!, source = _demoPixels!;
    final pixels = Uint8List(192 * 256);
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 192; x++) {
        final sx = (crop.left + (x + .5) / 192 * crop.width).floor().clamp(
          0,
          image.width - 1,
        );
        final sy = (crop.top + (y + .5) / 256 * crop.height).floor().clamp(
          0,
          image.height - 1,
        );
        final i = (sy * image.width + sx) * 4;
        pixels[y * 192 + x] =
            (source[i] * 77 + source[i + 1] * 150 + source[i + 2] * 29) >> 8;
      }
    }
    return GrayFrame(192, 256, pixels);
  }

  Future<void> _acceptFrame(GrayFrame frame) =>
      _acceptPreview((frame: frame, plane: null));

  Future<void> _acceptPreview(
    _PreviewSource source, {
    DateTime? capturedAt,
  }) async {
    if (disposed ||
        zoom.isAdjusting ||
        phase == CapturePhase.capturing ||
        phase == CapturePhase.analyzing ||
        phase == CapturePhase.captured) {
      return;
    }
    final frameTime = capturedAt ?? _now();
    if (_busy) {
      _pendingFrame = (source, frameTime);
      return;
    }
    _busy = true;
    _lastAnalysis = _now();
    final generation = _generation, session = _session;
    final frameZoom = zoom.value;
    try {
      final selection = _pendingSelection;
      if (selection != null) {
        // A tap must be able to escape stale/slow recovery of the old subject.
        // Sample the newest queued pixels without running that old tracker.
        // Keep the original capture time: an expired sample cannot seed a lock.
        final frame = await compute(_samplePreview, source);
        if (disposed || generation != _generation || session != _session) {
          return;
        }
        _frame = frame;
        _frameZoom = frameZoom;
        _lastFrame = frameTime;
        if (_hasFreshFrame) selectSubject(selection);
        return;
      }
      final (frame, analysis) = await compute(_analyzePreview, (
        source: source,
        template: subjectLock.template,
        previous: subjectLock.position,
        selected: subjectLock.selected,
        tracking: subjectLock.tracking,
        zoom: frameZoom,
      ));
      if (disposed || generation != _generation || session != _session) {
        return;
      }
      _frame = frame;
      _frameZoom = frameZoom;
      _lastFrame = frameTime;
      features = analysis.features;
      evidence = analysis.evidence;
      if (analysis.tracking != null) {
        subjectLock.acceptTracking(analysis.tracking!);
      } else {
        subjectLock.accept(features);
      }
      if (!_hasFreshFrame) {
        subjectLock.markLost();
        features = features.withSubject(null, 0);
        _alignment.reset();
        if (phase == CapturePhase.guiding || phase == CapturePhase.ready) {
          phase = CapturePhase.guiding;
          alignment = const AlignmentResult(false, 0, 0, '稳住手机，等待画面恢复', false);
        }
      } else if (phase == CapturePhase.guiding || phase == CapturePhase.ready) {
        _updateAlignment();
      }
      _notify();
    } catch (_) {
      if (disposed || generation != _generation || session != _session) return;
      subjectLock.markLost();
      features = features.withSubject(null, 0);
      _alignment.reset();
      alignment = const AlignmentResult(false, 0, 0, '请重新点选主体，再调整构图', false);
      if (phase == CapturePhase.ready) {
        phase = CapturePhase.guiding;
      }
      _notify();
    } finally {
      _busy = false;
      final pending = _pendingFrame;
      _pendingFrame = null;
      if (pending != null && !disposed && session == _session) {
        unawaited(_acceptPreview(pending.$1, capturedAt: pending.$2));
      }
    }
  }

  Future<void> confirmScene() async {
    if (disposed || phase != CapturePhase.framing) return;
    if (!canRecommend) {
      error = subjectLock.state == SubjectState.tracking
          ? '等待画面恢复后，再点「推荐构图」。'
          : subjectLock.state == SubjectState.unselected
          ? '先点选想拍的主体，再推荐构图。'
          : subjectHint;
      _notify();
      return;
    }
    error = null;
    phase = CapturePhase.analyzing;
    _pendingFrame = null;
    _notify();
    final generation = ++_generation;
    final frozenFrame = _frame!;
    late final CompositionAnalysis analysis;
    try {
      analysis = await compute(
        analyzeComposition,
        AnalysisRequest(
          frozenFrame,
          subjectLock.template,
          subjectLock.position,
          subjectLocked: subjectLock.selected,
          tracking: subjectLock.tracking,
          zoom: _frameZoom,
        ),
      );
    } catch (_) {
      if (!disposed && generation == _generation) {
        phase = CapturePhase.framing;
        error = '暂时没有得到构图建议，请再试一次。';
        _notify();
      }
      return;
    }
    if (disposed ||
        generation != _generation ||
        phase != CapturePhase.analyzing) {
      return;
    }
    final result = analysis.features;
    features = result;
    evidence = analysis.evidence;
    if (analysis.tracking != null) {
      subjectLock.acceptTracking(analysis.tracking!);
    } else {
      subjectLock.accept(result);
    }
    // Recheck the selected subject against the frozen image. A newer frame can
    // arrive before its live tracking result, so the initial lock alone is not enough.
    if (subjectLock.state != SubjectState.tracking || !_hasFreshFrame) {
      subjectLock.markLost();
      features = result.withSubject(null, 0);
      phase = CapturePhase.framing;
      error = subjectHint;
      _notify();
      return;
    }
    plans = const CompositionRecommender().recommend(
      features,
      selectedSubject: subjectLock.position,
      evidence: evidence,
    );
    plan = plans.first;
    phase = CapturePhase.recommending;
    _notify();
  }

  void _zoomChanged() {
    // Per-frame values repaint only the zoom overlay. The rest of the page
    // needs a rebuild only when availability or capture eligibility changes.
    final adjusting = zoom.isAdjusting, available = zoom.available;
    if (adjusting && !_zoomWasAdjusting && selectingSubject) {
      _generation++;
      _pendingSelection = null;
    }
    final invalidated = zoom.busy && subjectLock.state == SubjectState.tracking;
    if (invalidated) {
      // The preview is already changing scale. Its old box and ready state
      // must not remain visible while analysis waits for the gesture to end.
      _generation++;
      _pendingFrame = null;
      subjectLock.markLost();
      features = features.withSubject(null, 0);
      _alignment.reset();
      if (phase == CapturePhase.ready || phase == CapturePhase.guiding) {
        phase = CapturePhase.guiding;
        alignment = const AlignmentResult(false, 0, 0, '稳住手机，等待画面恢复', false);
      }
    }
    if (!invalidated &&
        _zoomWasAdjusting == adjusting &&
        _zoomWasAvailable == available) {
      return;
    }
    _zoomWasAdjusting = adjusting;
    _zoomWasAvailable = available;
    _notify();
  }

  void requestZoom(double value) {
    final controller = camera;
    if (!canZoom ||
        controller == null ||
        phase == CapturePhase.capturing ||
        phase == CapturePhase.captured) {
      return;
    }
    final next = zoom.range.clamp(value);
    if (!zoom.busy && next == zoom.value) return;
    if (!zoom.busy) {
      _generation++;
      _pendingFrame = null;
    }
    zoom.request(next, (level) async {
      if (disposed || camera != controller || !initialized) {
        throw StateError('Camera session changed during zoom adjustment');
      }
      await controller.setZoomLevel(level);
    });
  }

  void beginZoomGesture() {
    if (!canZoom) return;
    zoom.beginGesture();
  }

  void endZoomGesture() {
    zoom.endGesture();
  }

  void _zoomSettled(bool requested) {
    if (!requested || disposed) return;
    _generation++;
    _frame = null;
    _lastFrame = null;
    _pendingFrame = null;
    plans = [];
    plan = null;
    _alignment.reset();
    alignment = const AlignmentResult(false, 0, 0, '倍率已更新，等待主体重新跟踪', false);
    if (subjectLock.selected) subjectLock.markLost();
    features = features.withSubject(null, 0);
    if (phase != CapturePhase.framing) phase = CapturePhase.framing;
    error = null;
  }

  void choosePlan(CompositionPlan next) {
    plan = next;
    _alignment.reset();
    if (phase == CapturePhase.ready) {
      phase = CapturePhase.guiding;
    }
    _notify();
  }

  void startGuidance() {
    if (plan == null) {
      return;
    }
    phase = CapturePhase.guiding;
    _alignment.reset();
    _updateAlignment();
    _notify();
  }

  void _updateAlignment() {
    if (plan == null) {
      return;
    }
    final wasReady = phase == CapturePhase.ready;
    final liveFeatures =
        subjectLock.selected && subjectLock.state != SubjectState.tracking
        ? features.withSubject(null, 0)
        : features;
    alignment = _alignment.update(
      plan!,
      liveFeatures,
      _now(),
      level: level,
      evidence: evidence,
    );
    phase = alignment.ready ? CapturePhase.ready : CapturePhase.guiding;
    if (!wasReady && alignment.ready && !isDemo) {
      HapticFeedback.mediumImpact();
    }
  }

  void selectSubject(Point2 p) {
    if (disposed ||
        !initialized ||
        zoom.isAdjusting ||
        phase == CapturePhase.analyzing ||
        phase == CapturePhase.capturing ||
        phase == CapturePhase.captured) {
      return;
    }
    _generation++;
    if (!_hasFreshFrame) {
      // Retain only the latest explicit tap. The next camera sample services
      // this request before tracking; do not silently ignore it or use old pixels.
      _pendingSelection = p;
      subjectLock.markLost();
      features = features.withSubject(null, 0);
      _alignment.reset();
      if (phase == CapturePhase.ready) phase = CapturePhase.guiding;
      alignment = const AlignmentResult(false, 0, 0, '正在重新锁定主体', false);
      _notify();
      return;
    }
    _pendingSelection = null;
    subjectLock.select(_frame!, p, zoom: _frameZoom);
    features = features.withSubject(
      subjectLock.trackable ? subjectLock.position : null,
      subjectLock.trackable ? 1 : 0,
    );
    error = !subjectLock.trackable ? '请点在主体清晰的轮廓上。' : null;
    if (plan != null) {
      plan = CompositionPlan(
        plan!.kind,
        plan!.score,
        plan!.target,
        plan!.horizonTarget,
        plan!.reason,
      );
    }
    _alignment.reset();
    if (phase == CapturePhase.ready) {
      phase = CapturePhase.guiding;
    }
    if (phase == CapturePhase.guiding) {
      _updateAlignment();
    }
    _notify();
    if (plan != null) _refreshPlansForSubject();
  }

  Future<void> _refreshPlansForSubject() async {
    final generation = _generation, kind = plan?.kind;
    if (_frame == null || kind == null) return;
    try {
      final analysis = await compute(
        analyzeComposition,
        AnalysisRequest(
          _frame!,
          subjectLock.template,
          subjectLock.position,
          subjectLocked: true,
          tracking: subjectLock.tracking,
          zoom: _frameZoom,
        ),
      );
      if (disposed ||
          generation != _generation ||
          phase == CapturePhase.captured ||
          phase == CapturePhase.capturing) {
        return;
      }
      evidence = analysis.evidence;
      plans = const CompositionRecommender().recommend(
        analysis.features,
        selectedSubject: subjectLock.position,
        evidence: evidence,
      );
      plan = phase == CapturePhase.recommending
          ? plans.first
          : plans.firstWhere((p) => p.kind == kind);
      _alignment.reset();
      if (phase == CapturePhase.ready) phase = CapturePhase.guiding;
      _notify();
    } catch (_) {
      // Keep the chosen method usable; never invent a new score after a failure.
    }
  }

  void panDemo(ui.Offset delta) {
    if (!isDemo ||
        phase == CapturePhase.capturing ||
        phase == CapturePhase.captured) {
      return;
    }
    demoPan = ui.Offset(
      (demoPan.dx + delta.dx).clamp(-.45, .45),
      (demoPan.dy + delta.dy).clamp(-.12, .12),
    );
    _notify();
  }

  Future<void> alignDemo() async {
    if (!isDemo || plan == null || features.subject == null) {
      return;
    }
    final dx = plan!.target.x - features.subject!.x,
        dy = plan!.target.y - features.subject!.y;
    // Move the real demo pixels over several frames, then let the normal tracker judge.
    for (int i = 0; i < 10; i++) {
      if (disposed ||
          phase == CapturePhase.capturing ||
          phase == CapturePhase.captured) {
        return;
      }
      panDemo(ui.Offset(dx / 10, dy / 10));
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
  }

  void resetFraming() {
    _generation++;
    _pendingSelection = null;
    phase = CapturePhase.framing;
    plans = [];
    plan = null;
    _alignment.reset();
    error = null;
    saveError = null;
    subjectLock.reset();
    features = features.withSubject(null, 0);
    _notify();
  }

  Future<void> enableDemo() async {
    await suspend();
    if (disposed) return;
    isDemo = true;
    resetFraming();
    await initialize();
  }

  Future<void> exitDemo() async {
    if (!canExitDemo) return;
    await suspend();
    if (disposed) return;
    isDemo = false;
    resetFraming();
    // CameraPage must check consent and permissions before reopening the camera.
  }

  Future<void> switchCamera() async {
    if (isDemo || cameras.length < 2 || phase == CapturePhase.capturing) {
      return;
    }
    await suspend();
    cameraIndex = (cameraIndex + 1) % cameras.length;
    resetFraming();
    await initialize();
  }

  Future<void> toggleFlash() async {
    final controller = camera;
    if (controller == null || phase == CapturePhase.capturing) {
      return;
    }
    final next = switch (flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await controller.setFlashMode(next);
      flash = next;
      _notify();
    } catch (_) {
      error = '当前镜头不支持此闪光模式。';
      _notify();
    }
  }

  Future<void> takePhoto({bool overrideGuidance = false}) async {
    if (phase == CapturePhase.capturing ||
        phase == CapturePhase.captured ||
        zoom.isAdjusting ||
        !initialized) {
      return;
    }
    if (!overrideGuidance &&
        (phase != CapturePhase.ready ||
            _lastFrame == null ||
            _now().difference(_lastFrame!).inMilliseconds > 850)) {
      return;
    }
    _generation++;
    final session = _session;
    final filter = _photoFilter;
    _pendingSelection = null;
    phase = CapturePhase.capturing;
    saved = false;
    saveError = null;
    _notify();
    try {
      final Uint8List captured;
      if (isDemo) {
        captured = await _cropImage(demoImage!, demoCrop, filter: filter);
      } else {
        final controller = camera!;
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        final shot = await controller.takePicture();
        final codec = await ui.instantiateImageCodec(
          await readAndRemovePhoto(shot),
        );
        final image = (await codec.getNextFrame()).image;
        final cw = math.min(image.width.toDouble(), image.height * .75),
            ch = cw / .75;
        try {
          captured = await _cropImage(
            image,
            ui.Rect.fromCenter(
              center: ui.Offset(image.width / 2, image.height / 2),
              width: cw,
              height: ch,
            ),
            filter: filter,
            mirror:
                controller.description.lensDirection ==
                CameraLensDirection.front,
          );
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
      if (disposed || session != _session) {
        return;
      }
      photo = captured;
      phase = CapturePhase.captured;
      await retrySave(explicit: false);
    } catch (_) {
      if (!disposed && session == _session) {
        phase = CapturePhase.guiding;
        error = '未能拍下照片，请再试一次。';
      }
    } finally {
      final controller = camera;
      if (!disposed &&
          session == _session &&
          controller != null &&
          controller.value.isInitialized) {
        try {
          await _startStream(controller);
        } catch (_) {
          error = '相机已暂停，请重新开启。';
        }
      }
      _notify();
    }
  }

  Future<Uint8List> _cropImage(
    ui.Image image,
    ui.Rect source, {
    required PhotoFilter filter,
    bool mirror = false,
  }) async {
    final result = await renderPhoto(
      image,
      source,
      filter: filter,
      mirror: mirror,
    );
    try {
      return (await result.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      result.dispose();
    }
  }

  Future<void> retrySave({bool explicit = true}) async {
    if (photo == null || saved || disposed || _saving) {
      return;
    }
    _saving = true;
    try {
      if (beforeSave != null && !await beforeSave!(explicit)) {
        throw const PhotoSaveException('照片尚未保存，允许保存权限后点「重新保存」。');
      }
      if (disposed || photo == null) return;
      await _saver(photo!, 'frame_${_now().millisecondsSinceEpoch}.png');
      if (!disposed) {
        saved = true;
        saveError = null;
      }
    } catch (e) {
      if (!disposed) {
        saveError = e is PhotoSaveException
            ? e.message
            : kIsWeb
            ? '下载未开始，请点「重新保存」再试一次。'
            : '保存未完成，请点「重新保存」再试一次。';
      }
    } finally {
      _saving = false;
    }
    _notify();
  }

  Future<void> suspend() async {
    _session++;
    _generation++;
    _pendingSelection = null;
    zoom.reset();
    initialized = false;
    _demoTimer?.cancel();
    await _previewSubscription?.cancel();
    _previewSubscription = null;
    _watchdog?.cancel();
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    _levelFilter.reset();
    _lastLevel = null;
    _alignment.reset();
    if (phase == CapturePhase.ready ||
        phase == CapturePhase.guiding ||
        phase == CapturePhase.recommending ||
        phase == CapturePhase.analyzing ||
        phase == CapturePhase.capturing) {
      phase = CapturePhase.framing;
      plan = null;
      plans = [];
    }
    final controller = camera;
    camera = null;
    _frame = null;
    _pendingFrame = null;
    _lastFrame = null;
    subjectLock.reset();
    features = features.withSubject(null, 0);
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
    _notify();
  }

  void _notify() {
    if (!disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    initialized = false;
    photo = null;
    _frame = null;
    _pendingFrame = null;
    _demoPixels = null;
    _pendingSelection = null;
    subjectLock.reset();
    beforeSave = null;
    _session++;
    _generation++;
    _demoTimer?.cancel();
    _previewSubscription?.cancel();
    _watchdog?.cancel();
    _levelSubscription?.cancel();
    camera?.dispose();
    demoImage?.dispose();
    zoom.dispose();
    super.dispose();
  }
}
