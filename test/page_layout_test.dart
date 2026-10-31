import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/core/composition.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/services/references.dart';
import 'package:framecoach/services/reference_catalog.dart';
import 'package:framecoach/services/permissions.dart';
import 'package:framecoach/ui/camera_help.dart';
import 'package:framecoach/ui/photo_viewer.dart';
import 'package:framecoach/ui/privacy_flow.dart';
import 'package:framecoach/ui/reference_library.dart';
import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'reference_test.dart'
    show
        MemoryReferences,
        exportReferencePreview,
        expectOriginalCompositionLayout;
import 'widget_test.dart' show loadAppFonts;

const plans = [
  CompositionPlan(
    CompositionKind.thirds,
    .8,
    Point2(1 / 3, 1 / 3),
    .5,
    '将主体放在三分线上，保留环境。',
  ),
  CompositionPlan(
    CompositionKind.centered,
    .7,
    Point2(.5, .5),
    .5,
    '让主体位于画面中心。',
  ),
  CompositionPlan(
    CompositionKind.symmetry,
    .6,
    Point2(.5, .5),
    .5,
    '让画面左右保持对称。',
  ),
];

void main() {
  for (final (size, scale) in [
    (const Size(320, 568), 1.4),
    (const Size(390, 844), 1.0),
    (const Size(430, 932), 1.4),
    (const Size(768, 1024), 1.6),
  ]) {
    testWidgets('all camera pages and sheets fit $size at $scale', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ReferenceLibrary.importHintSeenKey: true,
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      final references = ReferenceLibrary(store: MemoryReferences());
      final coach = CameraCoach(
        demo: true,
        previewFrames: const Stream.empty(),
        now: tester.binding.clock.now,
      );
      late Uint8List photo;
      await tester.runAsync(() async {
        await consent.load();
        await coach.initialize();
        await loadAppFonts();
        await ReferenceCatalog.load();
        photo = await File('test/fixtures/pose_person.png').readAsBytes();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('reference-preview'),
          child: FrameApp(
            coach: coach,
            consent: consent,
            references: references,
            permissionBackend: TestPermissions()..photos = true,
          ),
        ),
      );
      Future<void> check(String name, {bool settle = true}) async {
        if (settle) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump();
        }
        expect(tester.takeException(), isNull, reason: name);
        final viewfinder = find.byKey(const Key('viewfinder'));
        if (viewfinder.evaluate().isNotEmpty) {
          final rect = tester.getRect(viewfinder);
          expect(rect.height, greaterThan(100), reason: name);
          expect(rect.width / rect.height, closeTo(.75, .001), reason: name);
        }
        final width = size.width.toInt();
        await exportReferencePreview(tester, 'audit-$name-$width-$scale');
      }

      Future<void> closeRoute() async {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      await check('composition-home');
      expectOriginalCompositionLayout(tester);
      final initialSteps = tester.getRect(
        find.byKey(const Key('shooting-subtitle')),
      );
      final initialHeader = tester.getRect(
        find.byKey(const Key('camera-header')),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('composition-steps')),
          matching: find.text('取景'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('open-filters')));
      await check('filters');
      await closeRoute();
      // Inject pose state to audit its layout with deterministic sample pixels;
      // practice UI intentionally exposes no pose tab.
      coach.setShootingMode(ShootingMode.pose);
      await check('pose-home');
      expect(
        find.byKey(const Key('open-filters')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('open-references')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(ReferenceLibrarySheet));
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await Future.wait([
          for (final image in images) precacheImage(image.image, context),
        ]);
      });
      await check('references');
      expect(find.byType(ReferenceLibrarySheet), findsOneWidget);
      await closeRoute();
      references.selectTemplate('audit', photo);
      await tester.pump();
      await tester.runAsync(() async {
        final context = tester.element(find.byKey(const Key('viewfinder')));
        await precacheImage(MemoryImage(photo), context);
        if (context.mounted) {
          await precacheImage(
            ResizeImage(MemoryImage(photo), width: 32),
            context,
          );
        }
      });
      await check('pose-shooting');
      expect(
        find.byKey(const Key('pose-restart')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.widget<GestureDetector>(find.byKey(const Key('shutter'))).onTap,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('pose-restart')));
      await check('pose-restarted');
      await tester.tap(find.byKey(const Key('mode-composition')));
      coach.plans = plans;
      coach.choosePlan(plans.first);
      coach.phase = CapturePhase.recommending;
      await check('recommendations');
      expectOriginalCompositionLayout(tester);
      expect(
        tester.getRect(find.byKey(const Key('shooting-subtitle'))),
        initialSteps,
      );
      expect(
        tester.getRect(find.byKey(const Key('camera-header'))),
        initialHeader,
      );
      final recommendationPreview = tester.getRect(
        find.byKey(const Key('viewfinder')),
      );
      expect(
        recommendationPreview.top - initialSteps.bottom,
        closeTo(16, .001),
      );
      final footer = tester.getRect(find.byKey(const Key('camera-controls')));
      expect(footer.height, lessThanOrEqualTo(scale <= 1 ? 200 : 260));
      final score = find.byKey(const Key('selected-suitability'));
      expect(tester.getSize(score).height, lessThanOrEqualTo(30 * scale));
      final scoreText = find.descendant(of: score, matching: find.byType(Text));
      final scoreLabel = tester.getRect(scoreText.at(0));
      final scoreValue = tester.getRect(scoreText.at(1));
      expect(scoreLabel.right, lessThan(scoreValue.left));
      expect(
        scoreLabel.center.dy,
        inInclusiveRange(scoreValue.top, scoreValue.bottom),
      );
      for (final plan in plans) {
        final candidate = find.byKey(
          ValueKey('composition-candidate-${plan.kind.name}'),
        );
        final text = find.descendant(
          of: candidate,
          matching: find.byType(Text),
        );
        final title = tester.getRect(text.at(0));
        final value = tester.getRect(text.at(1));
        expect(title.right, lessThan(value.left));
        expect(title.center.dy, closeTo(value.center.dy, .001));
        expect(tester.getSize(candidate).height, 44);
      }
      final lastCandidate = find.byKey(
        const ValueKey('composition-candidate-symmetry'),
      );
      await tester.ensureVisible(lastCandidate);
      await tester.tap(lastCandidate);
      await tester.pumpAndSettle();
      expect(coach.plan!.kind, CompositionKind.symmetry);
      expect(
        tester.getRect(find.byKey(const Key('viewfinder'))),
        recommendationPreview,
      );
      final modeUnderline = tester.getRect(
        find.byKey(const ValueKey('mode-indicator-composition')),
      );
      final stepsRow = tester.getRect(
        find.byKey(const Key('composition-steps')),
      );
      final upperGap = stepsRow.top - modeUnderline.bottom;
      final lowerGap = recommendationPreview.top - stepsRow.bottom;
      expect((upperGap - lowerGap).abs(), lessThanOrEqualTo(5));
      // Weak and close recommendations keep their explanation visible without
      // moving the step row or lifting the preview toward it.
      for (final weak in [false, true]) {
        coach.plans = [
          CompositionPlan(
            CompositionKind.negativeSpace,
            weak ? .3 : .8,
            const Point2(.5, .5),
            .5,
            '将主体放在画面一侧，为另一侧保留更多空间，让整体构图更均衡。',
          ),
          CompositionPlan(
            CompositionKind.golden,
            weak ? .29 : .79,
            const Point2(.5, .5),
            .5,
            '让主体靠近黄金比例交点。',
          ),
          plans.first,
        ];
        coach.choosePlan(coach.plans.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(coach.recommendationSummary!), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('shooting-subtitle'))),
          initialSteps,
        );
        final preview = tester.getRect(find.byKey(const Key('viewfinder')));
        expect(preview.top, recommendationPreview.top);
        expect(preview.height, greaterThan(100));
        expect(
          find.byKey(const Key('start-guidance')).hitTestable(),
          findsOneWidget,
        );
        await exportReferencePreview(
          tester,
          'audit-recommendation-${weak ? "weak" : "close"}-${size.width.toInt()}-$scale',
        );
      }
      coach.plans = plans;
      coach.choosePlan(plans.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-all-plans')));
      await check('all-plans');
      await tester.tap(find.widgetWithText(ListTile, plans.first.reason));
      await tester.pumpAndSettle();
      expect(coach.plan!.kind, CompositionKind.thirds);
      coach.startGuidance();
      await check('guiding');
      final shutter = tester.getRect(find.byKey(const Key('shutter')));
      final direct = tester.getRect(
        find.byKey(const Key('composition-direct-capture')),
      );
      final demoAlign = tester.getRect(find.byKey(const Key('demo-align')));
      expect(direct.top, greaterThanOrEqualTo(shutter.bottom));
      expect(direct.center.dx, shutter.center.dx);
      expect(demoAlign.left, greaterThanOrEqualTo(shutter.right));
      expect(demoAlign.center.dy, shutter.center.dy);
      expect(find.byKey(const Key('open-photo')), findsNothing);
      coach.photo = photo;
      coach.saved = true;
      coach.choosePlan(plans.first);
      coach.phase = CapturePhase.ready;
      coach.alignment = const AlignmentResult(true, 1, 1, '可以拍照了', true);
      await check('ready', settle: false);
      expect(find.byKey(const Key('composition-direct-capture')), findsNothing);
      expectOriginalCompositionLayout(tester);
      coach.choosePlan(plans.first);
      coach.phase = CapturePhase.captured;
      await check('saved');
      await tester.tap(find.byKey(const Key('open-photo')));
      await check('previous-photo');
      expect(find.byType(PhotoViewer), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('next-photo')).hitTestable(), findsOneWidget);
      coach.saveError = '照片保存失败，请检查系统权限后重新保存。';
      coach.saved = false;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('reference-preview'),
          child: FrameApp(
            coach: coach,
            consent: consent,
            references: references,
          ),
        ),
      );
      await check('save-error');
      coach.resetFraming();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-help')));
      await check('help');
      await tester.tap(find.text('隐私与权限'));
      await check('privacy-hub');
      expect(find.byType(PrivacyHub), findsOneWidget);
      for (final document in PolicyDocument.values) {
        await tester.ensureVisible(find.text(document.title));
        await tester.tap(find.text(document.title));
        final path = document.path;
        await check('policy-$path');
        await closeRoute();
      }
      await tester.ensureVisible(find.byKey(const Key('privacy-withdraw')));
      await tester.tap(find.byKey(const Key('privacy-withdraw')));
      await check('withdraw-dialog');
      await tester.tap(find.text('继续使用'));
      await closeRoute();
      coach.plans = plans;
      coach.choosePlan(plans.first);
      coach.phase = CapturePhase.captured;
      coach.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-photo')));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoViewer), findsOneWidget);
      await consent.withdraw();
      await check('consent');
      expect(coach.photo, isNull);
      expect(find.byKey(const Key('photo-viewer')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('privacy-decline')));
      await tester.tap(find.byKey(const Key('privacy-decline')));
      await check('consent-declined');
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    });
  }
  testWidgets(
    'camera failures and permission explanations fit a compact screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await consent.load();
      await tester.runAsync(loadAppFonts);
      final coach = _UnavailableCameraCoach();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('reference-preview'),
          child: FrameApp(
            coach: coach,
            consent: consent,
            references: ReferenceLibrary(store: MemoryReferences()),
            permissionBackend: TestPermissions()..camera = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('重新开启相机').hitTestable(), findsOneWidget);
      await exportReferencePreview(tester, 'audit-camera-error-320-1.4');
      await tester.tap(find.byKey(const Key('camera-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-help')));
      await tester.pumpAndSettle();
      expect(find.byType(CameraHelpSheet), findsOneWidget);
      expect(
        find.byKey(const Key('help-practice')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await exportReferencePreview(tester, 'audit-help-practice-320-1.4');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      for (final purpose in PermissionPurpose.values) {
        final context = tester.element(find.byType(CameraPage));
        final response = explainPermission(context, purpose);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('继续').hitTestable(), findsOneWidget);
        final name = purpose.name;
        await exportReferencePreview(tester, 'audit-permission-$name-320-1.4');
        await tester.tap(find.text('暂不开启'));
        expect(await response, isFalse);
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );
}

class _UnavailableCameraCoach extends CameraCoach {
  _UnavailableCameraCoach() : super(demo: false);
  @override
  Future<void> initialize() async {
    error = '相机暂时无法开启，请重试或检查系统权限。';
    notifyListeners();
  }
}
