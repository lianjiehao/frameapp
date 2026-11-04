import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'core/composition.dart';
import 'core/vision.dart';
import 'services/coach.dart';
import 'services/privacy.dart';
import 'services/permissions.dart';
import 'ui/guides.dart';
import 'ui/privacy_flow.dart';
import 'ui/photo_filters.dart';
import 'ui/camera_zoom_dial.dart';
import 'ui/camera_help.dart';
import 'services/references.dart';
import 'ui/reference_overlay.dart';
import 'ui/reference_library.dart';
import 'ui/pose_controls.dart';
import 'ui/pose_import_hint.dart';
import 'ui/photo_viewer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ink,
    ),
  );
  runApp(const FrameApp());
}

class FrameApp extends StatelessWidget {
  const FrameApp({
    super.key,
    this.coach,
    this.consent,
    this.permissionBackend,
    this.references,
  });
  final CameraCoach? coach;
  final PrivacyConsent? consent;
  final PermissionBackend? permissionBackend;
  final ReferenceLibrary? references;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '取景 · FRAME',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      fontFamily: 'FrameSans',
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: acid,
        brightness: Brightness.dark,
        surface: ink,
        primary: acid,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: paper,
        displayColor: paper,
        fontFamily: 'FrameSans',
      ),
    ),
    home: PrivacyGate(
      consent: consent,
      builder: (consent) => CameraPage(
        coach: coach,
        consent: consent,
        permissionBackend: permissionBackend,
        references: references,
      ),
    ),
  );
}

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    this.coach,
    required this.consent,
    this.permissionBackend,
    this.references,
  });
  final CameraCoach? coach;
  final PrivacyConsent consent;
  final PermissionBackend? permissionBackend;
  final ReferenceLibrary? references;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

enum _CameraMenuAction { flash, filters, help }

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late final CameraCoach coach;
  late final ReferenceLibrary references;
  late final AppPermissions permissions;
  bool _openingCamera = false;
  bool _changingMode = false;
  bool _infoPageOpen = false;
  bool _showImportHint = false;
  bool _referenceSheetOpen = false;
  bool _photoViewerOpen = false;
  final _importReferenceLink = LayerLink();
  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    coach = widget.coach ?? CameraCoach();
    references = widget.references ?? ReferenceLibrary();
    references.addListener(_changed);
    permissions = AppPermissions(
      widget.consent,
      backend: widget.permissionBackend,
    );
    coach.beforeSave = (explicit) async =>
        mounted &&
        widget.consent.accepted &&
        (!_mobile ||
            await permissions.ensurePhotoSave(
              explicit: explicit,
              explain: (purpose) => explainPermission(context, purpose),
            ));
    coach.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startCamera());
    });
  }

  Future<void> _startCamera({bool explicit = false}) async {
    if (_openingCamera ||
        _infoPageOpen ||
        !mounted ||
        !widget.consent.accepted) {
      return;
    }
    _openingCamera = true;
    try {
      final granted =
          coach.isDemo ||
          !_mobile ||
          await permissions.ensureCamera(
            explicit: explicit,
            explain: (purpose) => explainPermission(context, purpose),
          );
      if (!mounted || _infoPageOpen || !widget.consent.accepted) return;
      if (granted) {
        await coach.initialize();
      } else {
        coach.error = '相机尚未开启，允许后即可取景。';
        _changed();
      }
    } catch (_) {
      if (mounted) {
        coach.error = '相机暂时无法开启，请重试或检查系统权限。';
        _changed();
      }
    } finally {
      _openingCamera = false;
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        coach.initialized) {
      _dismissImportHint();
      unawaited(coach.suspend());
    } else if (state == AppLifecycleState.resumed) {
      if (coach.phase != CapturePhase.captured) unawaited(_startCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    coach.removeListener(_changed);
    references.removeListener(_changed);
    references.dispose();
    coach.dispose();
    super.dispose();
  }

  bool get guiding =>
      coach.phase == CapturePhase.guiding || coach.phase == CapturePhase.ready;
  bool get _canUseCameraControls =>
      !coach.isDemo &&
      coach.initialized &&
      coach.phase != CapturePhase.capturing &&
      coach.phase != CapturePhase.captured;

  void _resetFraming() {
    coach.resetFraming();
    if (!coach.initialized) unawaited(_startCamera());
  }

  Future<void> _setDemoMode(bool enabled) async {
    if (_changingMode || coach.isDemo == enabled) return;
    setState(() => _changingMode = true);
    try {
      if (enabled) {
        _dismissImportHint();
        await coach.enableDemo();
      } else {
        await coach.exitDemo();
        await _startCamera();
      }
    } finally {
      if (mounted) setState(() => _changingMode = false);
    }
  }

  Future<void> _showPrivacy() async {
    await _showInfoPage(PrivacyHub(consent: widget.consent));
  }

  Future<void> _showInfoPage(Widget page) async {
    _dismissImportHint();
    _infoPageOpen = true;
    final pausing = coach.suspend();
    final route = Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    try {
      await pausing;
      await route;
    } finally {
      _infoPageOpen = false;
    }
    if (mounted &&
        widget.consent.accepted &&
        coach.phase != CapturePhase.captured) {
      await _startCamera();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, box) {
        final phone = SafeArea(child: _cameraLayout());
        if (box.maxWidth < 760) {
          return phone;
        }
        return Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-.4, -.3),
              radius: 1.4,
              colors: [Color(0xFF293328), Color(0xFF111713), Color(0xFF0C100D)],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 26),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (box.maxWidth > 1050)
                    SizedBox(width: 340, child: _desktopIntro()),
                  if (box.maxWidth > 1050) const SizedBox(width: 70),
                  Container(
                    width: 390,
                    constraints: const BoxConstraints(maxHeight: 840),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: paper.withValues(alpha: .15)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .35),
                          blurRadius: 60,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: phone,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  bool get _preparingReference => coach.isPose && references.selected == null;

  bool get _hasPreviousPoseStep =>
      coach.isPose &&
      references.selected != null &&
      coach.phase == CapturePhase.framing;

  void _previousPoseStep() {
    if (!_hasPreviousPoseStep ||
        !coach.canChangeShootingMode ||
        references.busy) {
      return;
    }
    _dismissImportHint();
    references.clearSelection();
  }

  Widget _cameraLayout() => PopScope<void>(
    canPop: !_hasPreviousPoseStep,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _previousPoseStep();
    },
    child: Stack(
      children: [
        Column(
          children: [
            _header(),
            _steps(),
            Expanded(child: _viewfinder()),
            _controls(),
          ],
        ),
        if (_showImportHint &&
            coach.isPose &&
            coach.phase == CapturePhase.framing &&
            references.selected == null)
          Positioned.fill(
            child: PoseImportHint(
              link: _importReferenceLink,
              onImport: _showReferences,
              onDismiss: _dismissImportHint,
            ),
          ),
      ],
    ),
  );

  void _dismissImportHint() {
    if (mounted && _showImportHint) setState(() => _showImportHint = false);
  }

  Widget _desktopIntro() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            'f.',
            style: TextStyle(
              fontFamily: 'Editorial',
              fontSize: 68,
              color: acid,
            ),
          ),
          const SizedBox(width: 20),
          Text(
            'FRAME / 取景',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 3,
              color: paper.withValues(alpha: .7),
            ),
          ),
        ],
      ),
      const SizedBox(height: 30),
      const Text(
        '点选主体，\n按提示拍照。',
        style: TextStyle(
          fontSize: 47,
          fontWeight: FontWeight.w300,
          height: 1.4,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 38),
      Container(width: 32, height: 1, color: acid),
      const SizedBox(height: 24),
      const Text(
        '01  点选主体\n02  调整构图\n03  拍照保存',
        style: TextStyle(fontSize: 13, color: paper, height: 2.7),
      ),
      if (coach.isDemo) ...[
        const SizedBox(height: 36),
        const Text(
          '拖动画面，练习调整构图。',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ],
  );

  Widget _header() => Padding(
    key: const Key('camera-header'),
    padding: const EdgeInsets.fromLTRB(20, 13, 14, 9),
    child: LayoutBuilder(
      builder: (context, bounds) => Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: _modeSwitch()),
          ),
          if (coach.isDemo && bounds.maxWidth >= 430)
            _pill('练习模式', color: acid),
          if (coach.canExitDemo)
            TextButton.icon(
              key: const Key('exit-demo'),
              onPressed:
                  _changingMode ||
                      coach.phase == CapturePhase.capturing ||
                      coach.saving
                  ? null
                  : () => _setDemoMode(false),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('退出练习', style: TextStyle(fontSize: 12)),
            ),
          if (!coach.isDemo)
            IconButton(
              tooltip: '切换镜头',
              onPressed: _canUseCameraControls ? coach.switchCamera : null,
              constraints: const BoxConstraints.tightFor(width: 38, height: 38),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.cameraswitch_outlined, size: 20),
            ),
          _moreMenu(),
        ],
      ),
    ),
  );

  Widget _moreMenu() => PopupMenuButton<_CameraMenuAction>(
    key: const Key('camera-more'),
    tooltip: '更多',
    onOpened: _dismissImportHint,
    icon: const Icon(Icons.menu_rounded, size: 22),
    color: const Color(0xFF1A201A),
    surfaceTintColor: Colors.transparent,
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: paper.withValues(alpha: .12)),
    ),
    onSelected: (action) {
      switch (action) {
        case _CameraMenuAction.flash:
          if (_canUseCameraControls) unawaited(coach.toggleFlash());
        case _CameraMenuAction.filters:
          _showFilters();
        case _CameraMenuAction.help:
          _showHelp();
      }
    },
    itemBuilder: (_) => [
      if (!coach.isDemo)
        PopupMenuItem(
          key: const Key('menu-flash'),
          value: _CameraMenuAction.flash,
          enabled: _canUseCameraControls,
          child: Row(
            children: [
              Icon(
                switch (coach.flash) {
                  FlashMode.off => Icons.flash_off,
                  FlashMode.auto => Icons.flash_auto,
                  _ => Icons.flash_on,
                },
                size: 19,
                color: _canUseCameraControls ? paper : muted,
              ),
              const SizedBox(width: 12),
              Text(
                '闪光灯 · ${switch (coach.flash) {
                  FlashMode.off => '关闭',
                  FlashMode.auto => '自动',
                  _ => '开启',
                }}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      if (coach.isPose && references.selected != null)
        PopupMenuItem(
          key: const Key('menu-filters'),
          value: _CameraMenuAction.filters,
          enabled: coach.canChangePhotoFilter,
          child: Row(
            children: [
              const PhotoFilterIcon(),
              const SizedBox(width: 12),
              Text(
                '滤镜 · ${coach.photoFilter.style.label}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      const PopupMenuItem(
        key: Key('menu-help'),
        value: _CameraMenuAction.help,
        child: Row(
          children: [
            Icon(Icons.help_outline, size: 19),
            SizedBox(width: 12),
            Text('拍照指南', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ],
  );

  Widget _modeSwitch() => Row(
    key: const Key('shooting-mode-switch'),
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final mode in ShootingMode.values.where(
        (mode) => !coach.isDemo || mode == ShootingMode.composition,
      ))
        Flexible(
          child: Semantics(
            selected: coach.shootingMode == mode,
            child: TextButton(
              key: ValueKey('mode-${mode.name}'),
              onPressed: coach.canChangeShootingMode
                  ? () => _setShootingMode(mode)
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: coach.shootingMode == mode ? acid : muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 7),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      mode == ShootingMode.composition ? '构图模式' : '摆姿模式',
                      maxLines: 1,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    key: ValueKey('mode-indicator-${mode.name}'),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    width: 18,
                    height: 2,
                    decoration: BoxDecoration(
                      color: coach.shootingMode == mode
                          ? acid
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> _setShootingMode(ShootingMode mode) async {
    if (!coach.canChangeShootingMode || coach.shootingMode == mode) return;
    coach.setShootingMode(mode);
    if (!coach.isPose) {
      setState(() => _showImportHint = false);
      return;
    }
    if (references.selected != null || !await references.needsImportHint()) {
      return;
    }
    if (!mounted ||
        !coach.isPose ||
        references.selected != null ||
        _referenceSheetOpen) {
      return;
    }
    setState(() => _showImportHint = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && coach.isPose && _showImportHint) {
        unawaited(references.markImportHintSeen());
      }
    });
  }

  Widget _steps() {
    final labels = coach.isPose ? ['选图', '摆姿', '成片'] : ['取景', '构图', '拍照'];
    final current = coach.isPose
        ? coach.phase == CapturePhase.captured
              ? 2
              : _preparingReference
              ? 0
              : 1
        : switch (coach.phase) {
            CapturePhase.capturing || CapturePhase.captured => 2,
            CapturePhase.framing || CapturePhase.analyzing => 0,
            _ => 1,
          };
    return Padding(
      key: const Key('shooting-subtitle'),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Row(
        key: Key(coach.isPose ? 'pose-steps' : 'composition-steps'),
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  key: ValueKey('step-connector-$i'),
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: paper.withValues(alpha: .12),
                ),
              ),
            Text(
              '0${i + 1}',
              key: coach.isPose ? ValueKey('pose-step-${i + 1}') : null,
              style: TextStyle(
                color: current == i ? acid : muted,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              labels[i],
              style: TextStyle(
                color: current == i ? paper : muted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _needsSubjectAttention =>
      coach.subjectLock.state == SubjectState.lost ||
      coach.subjectLock.state == SubjectState.needsDetail;
  String get _viewfinderSubjectLabel => coach.isPose
      ? references.selected == null
            ? '导入一张参考图'
            : '对照参考图摆姿'
      : switch (coach.phase) {
          CapturePhase.framing when coach.selectingSubject => '正在重新锁定主体',
          CapturePhase.framing => switch (coach.subjectLock.state) {
            SubjectState.unselected => coach.subjectHint,
            SubjectState.tracking => '主体已锁定',
            SubjectState.lost => '主体跟丢了，请点一下重新锁定',
            SubjectState.needsDetail => '主体轮廓不清晰，请重新点选',
          },
          CapturePhase.analyzing => '正在分析构图',
          CapturePhase.recommending => '已生成构图建议',
          CapturePhase.guiding => coach.alignment.message,
          CapturePhase.ready => '可以拍照了',
          CapturePhase.capturing => '正在拍摄',
          CapturePhase.captured => coach.subjectLabel,
        };

  Widget _viewfinder() {
    final recommendation =
        !coach.isPose && coach.phase == CapturePhase.recommending;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, recommendation ? 16 : 0, 10, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Let the natural footer height determine the available preview
          // space, then take the largest 3:4 size that fits inside it.
          final height = (constraints.maxWidth / .75)
              .clamp(0.0, constraints.maxHeight)
              .toDouble();
          return Align(
            alignment: recommendation ? Alignment.topCenter : Alignment.center,
            child: SizedBox(
              key: const Key('viewfinder-frame'),
              width: height * .75,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, bounds) => GestureDetector(
                    key: const Key('viewfinder'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      coach.selectSubject(
                        Point2(
                          d.localPosition.dx / bounds.maxWidth,
                          d.localPosition.dy / bounds.maxHeight,
                        ),
                      );
                    },
                    onPanUpdate: coach.isDemo && !coach.isPose
                        ? (d) => coach.panDemo(
                            Offset(
                              d.delta.dx / bounds.maxWidth,
                              d.delta.dy / bounds.maxHeight,
                            ),
                          )
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (coach.phase == CapturePhase.captured &&
                            coach.photo != null)
                          Image.memory(coach.photo!, fit: BoxFit.cover)
                        else if (coach.isDemo && coach.demoImage != null)
                          FilteredPhoto(
                            filter: coach.photoFilter,
                            child: CustomPaint(
                              painter: DemoPhotoPainter(
                                coach.demoImage!,
                                coach.demoCrop,
                              ),
                            ),
                          )
                        else if (coach.camera?.value.isInitialized ?? false)
                          FilteredPhoto(
                            filter: coach.photoFilter,
                            child: _cameraPreview(),
                          )
                        else
                          Container(
                            color: const Color(0xFF20261F),
                            child: _cameraPlaceholder(),
                          ),
                        if (coach.phase != CapturePhase.captured &&
                            !coach.isPose)
                          IgnorePointer(child: _guideLayer()),
                        if (coach.isPose && coach.phase == CapturePhase.framing)
                          Positioned.fill(
                            child: ReferenceOverlay(
                              key: const Key('reference-overlay'),
                              library: references,
                            ),
                          ),
                        if ((!coach.isPose || coach.initialized) &&
                            coach.phase != CapturePhase.captured &&
                            (!coach.isPose || references.selected == null))
                          Positioned(
                            top: 13,
                            left: 13,
                            right: 13,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: _glassLabel(
                                _viewfinderSubjectLabel,
                                key: const Key('viewfinder-status'),
                                icon: coach.isPose
                                    ? Icons.add_photo_alternate_outlined
                                    : _needsSubjectAttention
                                    ? Icons.touch_app_outlined
                                    : coach.phase == CapturePhase.ready
                                    ? Icons.check_circle_outline
                                    : Icons.center_focus_weak,
                              ),
                            ),
                          ),
                        if (coach.canZoom &&
                            coach.phase != CapturePhase.captured)
                          Positioned.fill(
                            child: ListenableBuilder(
                              listenable: coach.zoom,
                              builder: (context, _) => CameraZoomDial(
                                range: coach.zoom.range,
                                value: coach.zoom.value,
                                onChanged: coach.requestZoom,
                                onGestureStart: coach.beginZoomGesture,
                                onGestureEnd: coach.endZoomGesture,
                                bottomTrailing: _previewLevelIndicator(),
                                onPreviewTap: (position) => coach.selectSubject(
                                  Point2(
                                    position.dx / bounds.maxWidth,
                                    position.dy / bounds.maxHeight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (coach.initialized &&
                            !coach.canZoom &&
                            coach.phase != CapturePhase.captured)
                          Positioned(
                            bottom: 13,
                            right: 13,
                            child: IgnorePointer(
                              child: _previewLevelIndicator(),
                            ),
                          ),
                        if (coach.phase == CapturePhase.analyzing ||
                            coach.phase == CapturePhase.capturing)
                          Container(
                            color: ink.withValues(alpha: .4),
                            child: const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: acid,
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
          );
        },
      ),
    );
  }

  Widget _previewLevelIndicator() {
    final level = coach.level;
    final name = coach.isDemo ? '练习水平仪' : '手机水平仪';
    final text =
        level.available &&
            !level.waiting &&
            !level.moving &&
            level.elevation != null
        ? '${level.label} ${level.elevation!.abs().toStringAsFixed(1)}°'
        : level.label;
    return Semantics(
      key: const Key('preview-level'),
      label: '$name，$text',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
        child: ExcludeSemantics(
          child: Text(
            text,
            key: const Key('preview-level-value'),
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
              color: Color(0xBFF2F0E7),
              shadows: [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guideLayer() {
    Widget paint(Point2? position) => CustomPaint(
      painter: GuidePainter(
        plan: coach.plan,
        features: coach.features,
        subjectPosition: position,
        subjectTracked: coach.subjectLock.state == SubjectState.tracking,
        ready: coach.phase == CapturePhase.ready,
        showGuides: guiding || coach.phase == CapturePhase.recommending,
      ),
    );
    // A visible box always means a confirmed current location, never a stale
    // search anchor retained internally for reacquiring the original subject.
    final position = coach.subjectLock.state == SubjectState.tracking
        ? coach.subjectLock.position
        : null;
    if (position == null) return paint(null);
    return TweenAnimationBuilder<Offset>(
      key: ValueKey('subject-${coach.subjectLock.revision}'),
      tween: Tween(
        begin: Offset(position.x, position.y),
        end: Offset(position.x, position.y),
      ),
      duration: const Duration(milliseconds: 100),
      builder: (_, point, _) => paint(Point2(point.dx, point.dy)),
    );
  }

  Widget _cameraPreview() {
    final controller = coach.camera!;
    final size = controller.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _cameraPlaceholder() =>
      coach.isPose ? _poseCameraPlaceholder() : _compositionCameraPlaceholder();

  Widget _compositionCameraPlaceholder() => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: bounds.maxHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 34, color: muted),
            const SizedBox(height: 18),
            Text(
              coach.error ?? '正在开启相机…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
            if (coach.error != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _startCamera(explicit: true),
                child: const Text('重新开启相机'),
              ),
              if (_mobile)
                TextButton(
                  onPressed: permissions.backend.openSettings,
                  child: const Text('系统权限设置'),
                ),
              TextButton(
                onPressed: () => _setDemoMode(true),
                child: const Text('试试练习模式'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _poseCameraPlaceholder() => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: bounds.maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 34, color: muted),
              const SizedBox(height: 18),
              Text(
                coach.error ?? '正在开启相机…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _controls() {
    final content =
        coach.isPose &&
            !coach.initialized &&
            coach.error != null &&
            coach.phase != CapturePhase.captured
        ? _cameraRecoveryControls()
        : coach.isPose && coach.phase != CapturePhase.captured
        ? _poseControls()
        : switch (coach.phase) {
            CapturePhase.framing ||
            CapturePhase.analyzing => _framingControls(),
            CapturePhase.recommending => _recommendControls(),
            CapturePhase.guiding ||
            CapturePhase.ready ||
            CapturePhase.capturing => _guidingControls(),
            CapturePhase.captured => _savedControls(),
          };
    return Padding(
      key: const Key('camera-controls'),
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 13),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coach.error != null && coach.initialized)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                coach.error!,
                style: const TextStyle(color: Color(0xFFF4B66F), fontSize: 11),
              ),
            ),
          content,
        ],
      ),
    );
  }

  Widget _cameraRecoveryControls() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _primary('重新开启相机', onPressed: () => _startCamera(explicit: true)),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_mobile)
            Expanded(
              child: TextButton(
                onPressed: permissions.backend.openSettings,
                child: const Text('系统权限设置', style: TextStyle(fontSize: 12)),
              ),
            ),
          Expanded(
            child: TextButton(
              onPressed: () => _setDemoMode(true),
              child: const Text('试试练习模式', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    ],
  );

  void _showFilters() {
    _dismissImportHint();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ink,
      barrierColor: Colors.black.withValues(alpha: .2),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PhotoFilterSheet(coach: coach),
    );
  }

  Widget _filterButton({bool compact = false}) {
    final button = TextButton.icon(
      key: const Key('open-filters'),
      onPressed: coach.canChangePhotoFilter ? _showFilters : null,
      style: TextButton.styleFrom(
        foregroundColor: paper,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: coach.isPose
          ? const PhotoFilterIcon()
          : const Icon(Icons.tune, size: 17),
      label: Text(
        compact
            ? coach.photoFilter.style.label
            : '滤镜 · ${coach.photoFilter.style.label}',
        style: const TextStyle(fontSize: 11),
      ),
    );
    return compact
        ? Tooltip(
            message: '滤镜 · ${coach.photoFilter.style.label}',
            child: button,
          )
        : button;
  }

  Future<void> _showReferences() async {
    if (!widget.consent.accepted ||
        !coach.canChangeShootingMode ||
        _referenceSheetOpen) {
      return;
    }
    _referenceSheetOpen = true;
    setState(() => _showImportHint = false);
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: ink,
        barrierColor: Colors.black.withValues(alpha: .2),
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => ReferenceLibrarySheet(
          library: references,
          onSelected: () => Navigator.of(sheetContext).pop(),
        ),
      );
    } finally {
      _referenceSheetOpen = false;
    }
  }

  Widget _poseControls() => PoseControls(
    library: references,
    importLink: _importReferenceLink,
    enabled: coach.canChangeShootingMode && !references.busy,
    canCapture: coach.canCapturePose,
    capturing: coach.phase == CapturePhase.capturing,
    onImport: _showReferences,
    filterButton: _filterButton(compact: references.selected != null),
    onRestart: _previousPoseStep,
    onShowPhoto: coach.photo == null ? null : _showPhoto,
    onCapture: () {
      _dismissImportHint();
      unawaited(coach.takePhoto());
    },
  );

  Widget _framingControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              switch (coach.subjectLock.state) {
                SubjectState.tracking => '主体已选好',
                SubjectState.lost => '重新点选主体',
                SubjectState.needsDetail => '点选清晰的轮廓',
                _ => '点一下想拍的主体',
              },
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),
          _filterButton(),
        ],
      ),
      Text(switch (coach.subjectLock.state) {
        SubjectState.tracking => '主体已锁定，点击「推荐构图」。',
        SubjectState.lost => '请点一下主体，重新锁定后再推荐。',
        SubjectState.needsDetail => '点在主体清晰的轮廓上，锁定后再推荐。',
        SubjectState.unselected => '先点一下画面中的人或物体，再推荐构图。',
      }, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 15),
      _primary(
        coach.phase == CapturePhase.analyzing ? '正在推荐…' : '推荐构图',
        key: const Key('confirm-scene'),
        onPressed: coach.canRecommend ? coach.confirmScene : null,
      ),
    ],
  );
  Widget _recommendControls() {
    final selected = coach.plan!;
    final summary = coach.recommendationSummary;
    final candidates = coach.plans.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: const Key('composition-title-row'),
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: '全部构图',
                  child: TextButton(
                    key: const Key('open-all-plans'),
                    onPressed: _showPlans,
                    style: TextButton.styleFrom(
                      foregroundColor: paper,
                      minimumSize: const Size(0, 36),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            selected.kind.title,
                            key: const Key('selected-composition-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 18, color: acid),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _suitabilityScore(
              selected,
              key: const Key('selected-suitability'),
              showLabel: true,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Tooltip(
          message: selected.reason,
          child: Text(
            selected.reason,
            key: const Key('composition-reason'),
            style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (summary != null) ...[
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(
              fontSize: 10,
              color: coach.plans.first.score >= .4
                  ? paper
                  : const Color(0xFFF4B66F),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            key: const Key('composition-candidates'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < candidates.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth:
                          (bounds.maxWidth - 6 * (candidates.length - 1)) /
                          candidates.length,
                    ),
                    child: _compositionCandidate(candidates[i], selected),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _primary(
          '开始调整构图',
          key: const Key('start-guidance'),
          onPressed: coach.startGuidance,
        ),
      ],
    );
  }

  Widget _compositionCandidate(CompositionPlan plan, CompositionPlan selected) {
    final active = plan.kind == selected.kind;
    final score = (plan.score.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      selected: active,
      child: TextButton(
        key: ValueKey('composition-candidate-${plan.kind.name}'),
        onPressed: () => coach.choosePlan(plan),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: active ? acid : muted,
          backgroundColor: active
              ? acid.withValues(alpha: .12)
              : const Color(0xFF232923),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: active ? acid.withValues(alpha: .5) : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plan.kind.title, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Text('$score分', style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _suitabilityScore(
    CompositionPlan plan, {
    Key? key,
    bool showLabel = false,
  }) {
    final score = (plan.score.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      key: key,
      label: '${plan.kind.title}适合度，$score分，满分100分',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (showLabel) ...[
            const Text('适合度', style: TextStyle(color: muted, fontSize: 10)),
            const SizedBox(width: 6),
          ],
          Text(
            '$score',
            style: TextStyle(
              fontFamily: 'Editorial',
              color: acid,
              fontSize: showLabel ? 20 : 26,
            ),
          ),
          const Text(' / 100', style: TextStyle(color: muted, fontSize: 10)),
        ],
      ),
    );
  }

  String get _guidanceHeadline => switch (coach.alignment.message) {
    '稳住手机，等待画面恢复' => '等待画面',
    '正在重新锁定主体' => '重新锁定中',
    '重新点一下主体' || '请重新点选主体，再调整构图' => '重新点选',
    '倍率已更新，等待主体重新跟踪' => '重新跟踪中',
    final message => message.split('，').first,
  };

  Widget _guidingControls() {
    final ready = coach.phase == CapturePhase.ready,
        capture = coach.phase == CapturePhase.capturing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              ready ? Icons.check_circle_outline : Icons.open_with,
              color: acid,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                capture ? '正在拍照…' : _guidanceHeadline,
                key: const Key('guidance-headline'),
                semanticsLabel: capture ? '正在拍照…' : coach.alignment.message,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              onTap: _showPlans,
              child: Row(
                children: [
                  Text(
                    coach.plan?.kind.title ?? '构图',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const Icon(Icons.expand_more, size: 15, color: muted),
                ],
              ),
            ),
            _filterButton(),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: coach.alignment.progress,
            minHeight: 3,
            backgroundColor: const Color(0xFF2D352B),
            color: acid,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          ready
              ? kIsWeb
                    ? '点击快门，下载照片'
                    : '点击快门，保存到相册'
              : coach.plan?.useHorizon == true
              ? '让横向分界对准虚线，稳住手机 1 秒'
              : '让绿圈中心留在选框内，保持 1 秒',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        const SizedBox(height: 13),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 90,
              child: TextButton(
                onPressed: capture ? null : _resetFraming,
                child: const Text(
                  '重新取景',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: '拍照',
              enabled: ready,
              child: GestureDetector(
                key: const Key('shutter'),
                onTap: ready ? () => coach.takePhoto() : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 67,
                  height: 67,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ready ? acid : const Color(0xFF485042),
                      width: 2,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? acid : const Color(0xFF333B2D),
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      color: ready ? ink : muted,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: coach.isDemo
                  ? TextButton(
                      key: const Key('demo-align'),
                      onPressed: capture ? null : coach.alignDemo,
                      child: const Text(
                        '自动对齐',
                        style: TextStyle(color: acid, fontSize: 12),
                      ),
                    )
                  : TextButton(
                      key: const Key('open-photo'),
                      onPressed: _showPhoto,
                      child: const Tooltip(
                        message: '查看最近照片',
                        child: Icon(Icons.photo_outlined, color: muted),
                      ),
                    ),
            ),
          ],
        ),
        if (!ready && !capture) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              key: const Key('composition-direct-capture'),
              onPressed: () => coach.takePhoto(overrideGuidance: true),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
              ),
              child: const Text(
                '直接拍照',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _savedControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(
            coach.saved ? Icons.check_circle_outline : Icons.info_outline,
            color: acid,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            coach.saved
                ? kIsWeb
                      ? '已开始下载照片'
                      : '照片已保存到相册'
                : coach.saveError != null
                ? '照片还未保存'
                : '正在保存照片…',
            style: const TextStyle(fontSize: 17),
          ),
        ],
      ),
      if (coach.saveError != null) ...[
        const SizedBox(height: 8),
        Text(
          coach.saveError!,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
          maxLines: 3,
        ),
      ],
      const SizedBox(height: 17),
      Row(
        children: [
          Expanded(
            child: _primary(
              coach.saving
                  ? '正在保存…'
                  : coach.saveError != null
                  ? '重新保存'
                  : '再拍一张',
              key: const Key('next-photo'),
              onPressed: coach.saving
                  ? null
                  : coach.saveError != null
                  ? coach.retrySave
                  : _resetFraming,
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            key: const Key('open-photo'),
            tooltip: '查看照片',
            onPressed: _showPhoto,
            icon: const Icon(Icons.photo_outlined),
          ),
        ],
      ),
    ],
  );
  Widget _primary(String text, {Key? key, VoidCallback? onPressed}) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: acid,
        foregroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.north_east, size: 16),
        ],
      ),
    ),
  );
  Widget _pill(String text, {Color color = muted}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );
  Widget _glassLabel(String text, {Key? key, IconData? icon}) => Container(
    key: key,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .52),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: paper),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    ),
  );

  void _showPlans() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A201A),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择构图', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 6),
              const Text(
                '分数越高，越适合当前画面。点击切换构图。',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              const SizedBox(height: 15),
              ...coach.plans.map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    p.kind.title,
                    style: const TextStyle(fontSize: 15),
                  ),
                  subtitle: Text(
                    p.reason,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                  trailing: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _suitabilityScore(p),
                  ),
                  onTap: () {
                    coach.choosePlan(p);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _showPhoto() async {
    _dismissImportHint();
    final photo = coach.photo;
    final posing =
        coach.isPose &&
        references.selected != null &&
        coach.phase == CapturePhase.framing;
    if (!widget.consent.accepted ||
        (coach.phase != CapturePhase.captured && !guiding && !posing) ||
        photo == null ||
        _photoViewerOpen) {
      return;
    }
    _photoViewerOpen = true;
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PhotoViewer(bytes: photo),
    );
    void closeOnWithdrawal() {
      if (!widget.consent.accepted && route.isActive) {
        navigator.removeRoute(route);
      }
    }

    widget.consent.addListener(closeOnWithdrawal);
    try {
      await navigator.push(route);
    } finally {
      widget.consent.removeListener(closeOnWithdrawal);
      _photoViewerOpen = false;
    }
  }

  void _showHelp() {
    _dismissImportHint();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A201A),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
        maxWidth: 560,
      ),
      builder: (context) => CameraHelpSheet(
        onPrivacy: () {
          Navigator.pop(context);
          unawaited(_showPrivacy());
        },
        onPractice: coach.isDemo
            ? null
            : () {
                Navigator.pop(context);
                unawaited(_setDemoMode(true));
              },
      ),
    );
  }
}
