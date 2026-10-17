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
  const FrameApp({super.key, this.coach, this.consent, this.permissionBackend});
  final CameraCoach? coach;
  final PrivacyConsent? consent;
  final PermissionBackend? permissionBackend;
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
  });
  final CameraCoach? coach;
  final PrivacyConsent consent;
  final PermissionBackend? permissionBackend;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late final CameraCoach coach;
  late final AppPermissions permissions;
  bool _openingCamera = false;
  bool _infoPageOpen = false;
  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    coach = widget.coach ?? CameraCoach();
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
      unawaited(coach.suspend());
    } else if (state == AppLifecycleState.resumed) {
      if (coach.phase != CapturePhase.captured) unawaited(_startCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    coach.removeListener(_changed);
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

  Future<void> _showPrivacy() async {
    await _showInfoPage(PrivacyHub(consent: widget.consent));
  }

  Future<void> _showInfoPage(Widget page) async {
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
        final phone = SafeArea(
          child: Column(
            children: [
              _header(),
              _steps(),
              Expanded(child: _viewfinder()),
              _controls(),
            ],
          ),
        );
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
          const Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'frame',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Editorial',
                      fontSize: 30,
                      height: 1.1,
                    ),
                  ),
                ),
                SizedBox(width: 9),
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '取景',
                    style: TextStyle(
                      color: muted,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (coach.isDemo && bounds.maxWidth >= 330)
            _pill('练习模式', color: acid),
          IconButton(
            tooltip: '切换镜头',
            onPressed: _canUseCameraControls ? coach.switchCamera : null,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.cameraswitch_outlined, size: 20),
          ),
          IconButton(
            tooltip: '闪光灯',
            onPressed: _canUseCameraControls ? coach.toggleFlash : null,
            icon: Icon(
              coach.flash == FlashMode.off
                  ? Icons.flash_off
                  : coach.flash == FlashMode.auto
                  ? Icons.flash_auto
                  : Icons.flash_on,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: '拍照指南',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline, size: 21),
          ),
        ],
      ),
    ),
  );
  Widget _steps() {
    final current = switch (coach.phase) {
      CapturePhase.framing || CapturePhase.analyzing => 0,
      CapturePhase.recommending ||
      CapturePhase.guiding ||
      CapturePhase.ready => 1,
      _ => 2,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 13),
      child: Row(
        children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: paper.withValues(alpha: .12),
                ),
              ),
            Text(
              '0${i + 1}',
              style: TextStyle(
                color: current == i ? acid : muted,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              ['取景', '构图', '拍照'][i],
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

  Widget _viewfinder() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Center(
      child: AspectRatio(
        aspectRatio: .75,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (context, bounds) => GestureDetector(
              key: const Key('viewfinder'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => coach.selectSubject(
                Point2(
                  d.localPosition.dx / bounds.maxWidth,
                  d.localPosition.dy / bounds.maxHeight,
                ),
              ),
              onPanUpdate: coach.isDemo
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
                  if (coach.phase != CapturePhase.captured)
                    IgnorePointer(child: _guideLayer()),
                  Positioned(
                    top: 13,
                    left: 13,
                    child: _glassLabel(coach.isDemo ? '练习照片 · 3:4' : '3:4'),
                  ),
                  if (coach.phase != CapturePhase.captured)
                    Positioned(
                      top: 13,
                      right: 13,
                      child: _glassLabel(
                        coach.subjectLabel,
                        icon:
                            coach.subjectLock.state == SubjectState.lost ||
                                coach.subjectLock.state ==
                                    SubjectState.needsDetail
                            ? Icons.touch_app_outlined
                            : Icons.center_focus_weak,
                      ),
                    ),
                  if (coach.initialized && coach.phase != CapturePhase.captured)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: .55),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              coach.phase == CapturePhase.ready
                                  ? Icons.check_circle
                                  : coach.subjectLock.state ==
                                            SubjectState.lost ||
                                        coach.subjectLock.state ==
                                            SubjectState.needsDetail
                                  ? Icons.touch_app_outlined
                                  : Icons.crop_free,
                              size: 15,
                              color: coach.phase == CapturePhase.ready
                                  ? acid
                                  : paper,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                coach.phase == CapturePhase.ready
                                    ? '可以拍照了'
                                    : coach.isDemo &&
                                          coach.plan != null &&
                                          coach.plan?.useHorizon != true &&
                                          coach.subjectLock.state ==
                                              SubjectState.tracking
                                    ? '拖动画面，让绿圈中心进入选框'
                                    : coach.subjectHint,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Semantics(
                              label:
                                  '${coach.isDemo ? '练习水平仪' : '手机水平仪'}，${coach.level.label}',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    coach.isDemo ? '练习水平仪' : '手机水平仪',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: paper.withValues(alpha: .65),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    coach.level.label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          coach.level.blocksAlignment ||
                                              coach.level.needsLeveling
                                          ? const Color(0xFFF4B66F)
                                          : acid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
    ),
  );

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

  Widget _cameraPlaceholder() => Column(
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
        TextButton(onPressed: coach.enableDemo, child: const Text('试试练习模式')),
      ],
    ],
  );

  Widget _controls() {
    final content = switch (coach.phase) {
      CapturePhase.framing || CapturePhase.analyzing => _framingControls(),
      CapturePhase.recommending => _recommendControls(),
      CapturePhase.guiding ||
      CapturePhase.ready ||
      CapturePhase.capturing => _guidingControls(),
      CapturePhase.captured => _savedControls(),
    };
    return Padding(
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

  void _showFilters() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: ink,
    barrierColor: Colors.black.withValues(alpha: .2),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => PhotoFilterSheet(coach: coach),
  );

  Widget _filterButton() => TextButton.icon(
    key: const Key('open-filters'),
    onPressed: coach.canChangePhotoFilter ? _showFilters : null,
    style: TextButton.styleFrom(
      foregroundColor: paper,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    icon: const Icon(Icons.tune, size: 17),
    label: Text(
      '滤镜 · ${coach.photoFilter.style.label}',
      style: const TextStyle(fontSize: 11),
    ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _pill('构图建议', color: acid),
            const Spacer(),
            _filterButton(),
            TextButton(
              onPressed: _showPlans,
              child: const Text('全部构图 ↗', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              selected.kind.title,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            _suitabilityScore(selected, key: const Key('selected-suitability')),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          selected.reason,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
          maxLines: 2,
        ),
        if (summary != null) ...[
          const SizedBox(height: 5),
          Text(
            summary,
            style: TextStyle(
              fontSize: 10,
              color: coach.plans.first.score >= .4
                  ? paper
                  : const Color(0xFFF4B66F),
            ),
            maxLines: 2,
          ),
        ],
        const SizedBox(height: 13),
        Row(
          children: [
            for (final p in coach.plans.take(3))
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => coach.choosePlan(p),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: p.kind == selected.kind
                            ? acid.withValues(alpha: .12)
                            : const Color(0xFF232923),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: p.kind == selected.kind
                              ? acid.withValues(alpha: .5)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.kind.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.kind == selected.kind ? acid : muted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${(p.score.clamp(0.0, 1.0) * 100).round()}分',
                            style: TextStyle(
                              color: p.kind == selected.kind ? acid : muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 13),
        _primary(
          '开始调整构图',
          key: const Key('start-guidance'),
          onPressed: coach.startGuidance,
        ),
      ],
    );
  }

  Widget _suitabilityScore(
    CompositionPlan plan, {
    Key? key,
    bool compact = false,
  }) {
    final score = (plan.score.clamp(0.0, 1.0) * 100).round();
    return Semantics(
      key: key,
      label: '${plan.kind.title}适合度，$score分，满分100分',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!compact)
            const Text('适合度', style: TextStyle(color: muted, fontSize: 10)),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontFamily: 'Editorial',
                  color: acid,
                  fontSize: compact ? 26 : 32,
                ),
              ),
              const Text(
                ' / 100',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
                capture ? '正在拍照…' : coach.alignment.message,
                style: const TextStyle(
                  fontSize: 14,
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
                      onPressed: _showPhoto,
                      child: const Tooltip(
                        message: '查看最近照片',
                        child: Icon(Icons.photo_outlined, color: muted),
                      ),
                    ),
            ),
          ],
        ),
        if (ready && coach.alignment.advice != null) ...[
          const SizedBox(height: 6),
          Text(
            coach.alignment.advice!,
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
        if (!ready && !capture) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton(
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
  Widget _glassLabel(String text, {IconData? icon}) => Container(
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
        Text(text, style: const TextStyle(fontSize: 10)),
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
                  trailing: _suitabilityScore(p, compact: true),
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
  void _showPhoto() {
    if (coach.photo == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('还没有照片，先拍一张吧。')));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: ink,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(coach.photo!, fit: BoxFit.contain),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A201A),
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('拍照指南', style: TextStyle(fontSize: 24)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_showPrivacy());
                    },
                    icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                    label: const Text('隐私与权限', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                '1. 点选想拍的主体，点击「推荐构图」。\n2. 选好构图，点击「开始调整构图」。\n3. 按提示移动手机，出现「可以拍照了」后点击快门。',
                style: TextStyle(fontSize: 13, height: 2, color: paper),
              ),
              const SizedBox(height: 14),
              const Text(
                '白框跟随主体，让绿圈中心留在框内一秒。\n提示「主体跟丢了」时，重新点一下主体。\n右下角的角度接近 0°，画面更水平。',
                style: TextStyle(color: paper, fontSize: 12, height: 1.8),
              ),
              const SizedBox(height: 14),
              const Text(
                '想保留当前画面？也可以点击「直接拍照」。',
                style: TextStyle(color: acid, fontSize: 11),
              ),
              if (!coach.isDemo)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    coach.enableDemo();
                  },
                  child: const Text('试试练习模式'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
