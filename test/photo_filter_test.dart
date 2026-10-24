import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/core/photo_filter.dart';
import 'package:framecoach/core/composition.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/gallery_error.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/ui/photo_filters.dart';
import 'package:framecoach/ui/guides.dart';
import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'widget_test.dart' show loadAppFonts, savePreview;
import 'tracking_test.dart' show treeView, expected;

Future<List<int>> filteredSwatch(Color color, PhotoFilter filter) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final source = await picture.toImage(4, 4);
  picture.dispose();
  final output = await renderPhoto(
    source,
    const Rect.fromLTWH(0, 0, 4, 4),
    filter: filter,
  );
  try {
    return (await output.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!.buffer.asUint8List().sublist(20, 24);
  } finally {
    output.dispose();
    source.dispose();
  }
}

Future<ui.Image> colorChart() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const colors = [
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.white,
    Colors.black,
    Color(0xFF808080),
  ];
  for (var i = 0; i < colors.length; i++) {
    canvas.drawRect(
      Rect.fromLTWH((i % 3) * 32, (i ~/ 3) * 64, 32, 64),
      Paint()..color = colors[i],
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 128);
  picture.dispose();
  return image;
}

Future<List<int>> pixels(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawRgba,
))!.buffer.asUint8List();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('neutral adjustments preserve every preset and its pixels', () async {
    final source = await colorChart();
    addTearDown(source.dispose);
    for (final style in PhotoStyle.values) {
      final preset = PhotoFilter(style: style, intensity: .65);
      final neutral = preset.copyWith(
        brightness: 0,
        contrast: 0,
        saturation: 0,
        warmth: 0,
      );
      expect(neutral, preset);
      expect(neutral.hashCode, preset.hashCode);
      expect(neutral.matrix, orderedEquals(preset.matrix));
      final before = await renderPhoto(
        source,
        const Rect.fromLTWH(0, 0, 96, 128),
        filter: preset,
      );
      final after = await renderPhoto(
        source,
        const Rect.fromLTWH(0, 0, 96, 128),
        filter: neutral,
      );
      expect(await pixels(after), orderedEquals(await pixels(before)));
      before.dispose();
      after.dispose();
    }
  });

  test(
    'adjustment endpoints have predictable color and preserve alpha',
    () async {
      final cases = [
        (
          const Color(0xFF808080),
          const PhotoFilter(brightness: 1),
          [179, 179, 179, 255],
        ),
        (
          const Color(0xFF808080),
          const PhotoFilter(brightness: -1),
          [77, 77, 77, 255],
        ),
        (Colors.black, const PhotoFilter(contrast: -1), [64, 64, 64, 255]),
        (Colors.white, const PhotoFilter(contrast: -1), [191, 191, 191, 255]),
        (
          const Color(0xFF404040),
          const PhotoFilter(contrast: 1),
          [32, 32, 32, 255],
        ),
        (
          const Color(0xFFFF0000),
          const PhotoFilter(saturation: -1),
          [54, 54, 54, 255],
        ),
        (
          const Color(0xFFA07850),
          const PhotoFilter(saturation: 1),
          [194, 114, 34, 255],
        ),
        (
          const Color(0xFF808080),
          const PhotoFilter(warmth: 1),
          [148, 128, 108, 255],
        ),
        (
          const Color(0xFF808080),
          const PhotoFilter(warmth: -1),
          [108, 128, 148, 255],
        ),
        (
          const Color(0xFF505050),
          const PhotoFilter(contrast: 1, brightness: .5),
          [82, 82, 82, 255],
        ),
        (
          const Color(0x80808080),
          const PhotoFilter(brightness: 1, warmth: 1),
          [199, 179, 159, 128],
        ),
        (
          Colors.transparent,
          const PhotoFilter(brightness: 1, warmth: 1),
          [0, 0, 0, 0],
        ),
      ];
      for (final (source, filter, expected) in cases) {
        final actual = await filteredSwatch(source, filter);
        for (var channel = 0; channel < 4; channel++) {
          expect(
            actual[channel],
            closeTo(expected[channel], 1),
            reason: '$source $filter channel $channel',
          );
        }
      }
    },
  );

  test(
    'zero preset strength retains explicit adjustments and no texture',
    () async {
      final source = await colorChart();
      addTearDown(source.dispose);
      const original = PhotoFilter(
        brightness: .2,
        contrast: -.2,
        saturation: .3,
        warmth: -.4,
      );
      final expected = await renderPhoto(
        source,
        const Rect.fromLTWH(0, 0, 96, 128),
        filter: original,
      );
      addTearDown(expected.dispose);
      for (final style in PhotoStyle.values) {
        final filter = original.copyWith(style: style, intensity: 0);
        expect(filter.isOriginal, false);
        expect(filter.vignette, 0);
        expect(filter.grain, 0);
        final result = await renderPhoto(
          source,
          const Rect.fromLTWH(0, 0, 96, 128),
          filter: filter,
        );
        expect(await pixels(result), orderedEquals(await pixels(expected)));
        result.dispose();
      }
    },
  );

  test(
    'zero strength is pixel-identical to the original for every style',
    () async {
      final source = await colorChart();
      addTearDown(source.dispose);
      final original = await pixels(source);
      for (final style in PhotoStyle.values) {
        final result = await renderPhoto(
          source,
          const Rect.fromLTWH(0, 0, 96, 128),
          filter: PhotoFilter(style: style, intensity: 0),
        );
        expect(
          await pixels(result),
          orderedEquals(original),
          reason: style.name,
        );
        result.dispose();
      }
    },
  );

  test('monochrome removes chroma and warm color keeps opaque alpha', () async {
    final source = await colorChart();
    addTearDown(source.dispose);
    for (final style in [PhotoStyle.monochrome, PhotoStyle.warm]) {
      final result = await renderPhoto(
        source,
        const Rect.fromLTWH(0, 0, 96, 128),
        filter: PhotoFilter(style: style),
      );
      final rgba = await pixels(result);
      for (var i = 0; i < rgba.length; i += 4) {
        expect(rgba[i + 3], 255);
        if (style == PhotoStyle.monochrome) {
          expect(rgba[i], closeTo(rgba[i + 1], 1));
          expect(rgba[i + 1], closeTo(rgba[i + 2], 1));
        }
      }
      if (style == PhotoStyle.warm) {
        final gray = (96 * 96 + 80) * 4;
        expect(rgba[gray], greaterThan(rgba[gray + 1]));
        expect(rgba[gray + 1], greaterThan(rgba[gray + 2]));
      }
      result.dispose();
    }
  });

  test('cropping and front-camera mirroring precede color rendering', () async {
    final source = await colorChart();
    addTearDown(source.dispose);
    final outputs = <List<int>>[];
    for (final mirror in [false, true]) {
      final result = await renderPhoto(
        source,
        const Rect.fromLTWH(12, 16, 72, 96),
        mirror: mirror,
        filter: const PhotoFilter(style: PhotoStyle.warm, intensity: .6),
      );
      expect((result.width, result.height), (72, 96));
      outputs.add(await pixels(result));
      result.dispose();
    }
    for (var y = 0; y < 96; y++) {
      for (var x = 0; x < 72; x++) {
        final from = (y * 72 + x) * 4;
        final to = (y * 72 + 71 - x) * 4;
        expect(
          outputs[0].sublist(from, from + 4),
          outputs[1].sublist(to, to + 4),
        );
      }
    }
  });

  for (final style in PhotoStyle.values) {
    for (final adjusted in [false, true]) {
      testWidgets(
        '${style.name} preview matches exported pixels (adjusted: $adjusted)',
        (tester) async {
          final source = (await tester.runAsync(colorChart))!;
          addTearDown(source.dispose);
          final filter = PhotoFilter(
            style: style,
            intensity: .65,
            brightness: adjusted ? .2 : 0,
            contrast: adjusted ? -.25 : 0,
            saturation: adjusted ? .3 : 0,
            warmth: adjusted ? -.35 : 0,
          );
          await tester.pumpWidget(
            Center(
              child: RepaintBoundary(
                key: const Key('filtered-preview'),
                child: SizedBox(
                  width: 96,
                  height: 128,
                  child: FilteredPhoto(
                    filter: filter,
                    child: RawImage(image: source),
                  ),
                ),
              ),
            ),
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('filtered-preview')),
          );
          await tester.runAsync(() async {
            final preview = await boundary.toImage();
            final exported = await renderPhoto(
              source,
              const Rect.fromLTWH(0, 0, 96, 128),
              filter: filter,
            );
            final a = await pixels(preview), b = await pixels(exported);
            var maximumError = 0;
            for (var i = 0; i < a.length; i++) {
              final error = (a[i] - b[i]).abs();
              if (error > maximumError) maximumError = error;
            }
            expect(maximumError, lessThanOrEqualTo(2));
            preview.dispose();
            exported.dispose();
          });
        },
      );
    }
  }

  test(
    'adjustments preserve selected subject, readiness, and preset on reset',
    () async {
      final frames = StreamController<GrayFrame>();
      var now = DateTime(2026, 10, 15);
      final coach = CameraCoach(
        demo: true,
        previewFrames: frames.stream,
        now: () => now,
      );
      addTearDown(coach.dispose);
      // A disabled controller must ignore all edit entry points.
      coach.setPhotoAdjustment(PhotoAdjustment.brightness, .5);
      expect(coach.photoFilter.hasAdjustments, false);
      await coach.initialize();
      Future<void> feed() async {
        now = now.add(const Duration(milliseconds: 120));
        final completed = Completer<void>();
        void changed() {
          if (!completed.isCompleted) completed.complete();
        }

        coach.addListener(changed);
        try {
          frames.add(treeView(panX: 14, panY: -3));
          await completed.future;
        } finally {
          coach.removeListener(changed);
        }
      }

      await feed();
      coach.selectSubject(expected(panX: 14, panY: -3));
      await coach.confirmScene();
      coach.choosePlan(
        coach.plans.firstWhere((p) => p.kind == CompositionKind.centered),
      );
      coach.startGuidance();
      for (var i = 0; i < 10; i++) {
        await feed();
      }
      expect(coach.phase, CapturePhase.ready);
      final revision = coach.subjectLock.revision;
      final reference = List<double>.of(
        coach.subjectLock.tracking!.reference!.values,
      );
      coach.selectPhotoStyle(PhotoStyle.film);
      coach.setPhotoFilterIntensity(.6);
      final preset = coach.photoFilter;
      for (final adjustment in PhotoAdjustment.values) {
        coach.setPhotoAdjustment(adjustment, 2);
        expect(coach.photoFilter.adjustment(adjustment), 1);
        coach.setPhotoAdjustment(adjustment, -2);
        expect(coach.photoFilter.adjustment(adjustment), -1);
        coach.setPhotoAdjustment(adjustment, .25);
        coach.setPhotoAdjustment(adjustment, double.nan);
        coach.setPhotoAdjustment(adjustment, double.infinity);
        expect(coach.photoFilter.adjustment(adjustment), .25);
      }
      coach.selectPhotoStyle(PhotoStyle.original);
      expect(coach.photoFilter.hasAdjustments, true);
      coach.setPhotoFilterIntensity(.4);
      expect(coach.photoFilter.brightness, .25);
      coach.selectPhotoStyle(PhotoStyle.film);
      coach.setPhotoFilterIntensity(.6);
      expect(coach.photoFilter.brightness, .25);
      coach.resetPhotoAdjustments();
      expect(coach.photoFilter, preset);
      expect(coach.phase, CapturePhase.ready);
      expect(coach.subjectLock.state, SubjectState.tracking);
      expect(coach.subjectLock.revision, revision);
      expect(
        coach.subjectLock.tracking!.reference!.values,
        orderedEquals(reference),
      );
      await coach.suspend();
      coach.setPhotoAdjustment(PhotoAdjustment.warmth, .5);
      expect(coach.photoFilter, preset);
      await frames.close();
    },
  );

  test(
    'capture freezes the recipe and retry saves the same filtered PNG',
    () async {
      final frames = StreamController<GrayFrame>();
      final attempts = <List<int>>[];
      final coach = CameraCoach(
        demo: true,
        previewFrames: frames.stream,
        saver: (bytes, _) async {
          attempts.add(List.of(bytes));
          if (attempts.length == 1) throw const PhotoSaveException('保存未完成');
        },
      );
      addTearDown(coach.dispose);
      await coach.initialize();
      coach.selectPhotoStyle(PhotoStyle.monochrome);
      coach.setPhotoFilterIntensity(.5);
      coach.setPhotoFilterIntensity(double.nan);
      expect(coach.photoFilter.intensity, .5);
      coach.setPhotoFilterIntensity(2);
      expect(coach.photoFilter.intensity, 1);
      coach.setPhotoAdjustment(PhotoAdjustment.brightness, .15);
      coach.setPhotoAdjustment(PhotoAdjustment.contrast, -.25);
      coach.setPhotoAdjustment(PhotoAdjustment.saturation, .2);
      coach.setPhotoAdjustment(PhotoAdjustment.warmth, .3);
      final frozen = coach.photoFilter;
      final expectedImage = await renderPhoto(
        coach.demoImage!,
        coach.demoCrop,
        filter: frozen,
      );
      final expectedPixels = await pixels(expectedImage);
      expectedImage.dispose();
      final capture = coach.takePhoto(overrideGuidance: true);
      coach.selectPhotoStyle(PhotoStyle.warm);
      coach.setPhotoFilterIntensity(.2);
      coach.setPhotoAdjustment(PhotoAdjustment.brightness, -.8);
      coach.resetPhotoAdjustments();
      await capture;
      expect(coach.photoFilter, frozen);
      expect(coach.photoFilter.style, PhotoStyle.monochrome);
      expect(coach.photoFilter.intensity, 1);
      expect(coach.saved, false);
      expect(coach.photo, isNotNull);
      final codec = await ui.instantiateImageCodec(coach.photo!);
      final result = (await codec.getNextFrame()).image;
      final rgba = await pixels(result);
      expect(rgba, orderedEquals(expectedPixels));
      expect(result.width / result.height, closeTo(.75, .002));
      result.dispose();
      codec.dispose();
      await coach.retrySave();
      expect(coach.saved, true);
      expect(attempts.length, 2);
      expect(attempts[1], orderedEquals(attempts[0]));
      coach.resetPhotoAdjustments();
      coach.setPhotoAdjustment(PhotoAdjustment.warmth, -.9);
      expect(coach.photoFilter, frozen);
      await coach.suspend();
      await frames.close();
    },
  );

  test(
    'suspending an in-flight filtered capture discards its result',
    () async {
      final frames = StreamController<GrayFrame>();
      var saves = 0;
      final coach = CameraCoach(
        demo: true,
        previewFrames: frames.stream,
        saver: (_, _) async => saves++,
      );
      addTearDown(coach.dispose);
      await coach.initialize();
      coach.selectPhotoStyle(PhotoStyle.film);
      final capture = coach.takePhoto(overrideGuidance: true);
      await coach.suspend();
      await capture;
      expect(coach.photo, isNull);
      expect(saves, 0);
      expect(coach.phase, CapturePhase.framing);
      await frames.close();
    },
  );

  testWidgets(
    'filters share the action row and camera controls stay in the header',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      // Small-screen layout depends on the actual app fonts, not Ahem's
      // fixed-width test glyphs.
      await tester.runAsync(loadAppFonts);
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await consent.load();
      addTearDown(consent.dispose);
      final frames = StreamController<GrayFrame>.broadcast();
      final coach = CameraCoach(
        demo: true,
        previewFrames: frames.stream,
        saver: (_, _) async {},
      );
      await tester.runAsync(coach.initialize);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('app-preview'),
          child: FrameApp(
            coach: coach,
            consent: consent,
            permissionBackend: TestPermissions(),
          ),
        ),
      );
      await tester.pump();
      expect(coach.initialized, true);
      final viewfinder = find.byKey(const Key('viewfinder'));
      final filterButton = find.byKey(const Key('open-filters'));
      final previewRect = tester.getRect(viewfinder);
      final filterRect = tester.getRect(filterButton);
      final title = find.text('点一下想拍的主体');
      expect(filterRect.top, greaterThanOrEqualTo(previewRect.bottom));
      expect(filterRect.center.dy, tester.getCenter(title).dy);
      expect(filterRect.height, greaterThanOrEqualTo(44));
      for (final tooltip in ['切换镜头', '闪光灯']) {
        expect(find.byTooltip(tooltip), findsNothing);
      }
      expect(
        tester.getRect(find.byKey(const Key('exit-demo'))).bottom,
        lessThan(previewRect.top),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('camera-header')),
          matching: find.byIcon(Icons.photo_outlined),
        ),
        findsNothing,
      );
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      expect(coach.subjectLock.state, SubjectState.unselected);
      expect(tester.getRect(viewfinder), previewRect);
      await tester.tap(find.byKey(const Key('filter-film')));
      await tester.pump();
      expect(coach.photoFilter.style, PhotoStyle.film);
      expect(
        tester.widget<FilteredPhoto>(find.byType(FilteredPhoto)).filter,
        coach.photoFilter,
      );
      expect(
        tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(FilteredPhoto),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((widget) => widget.painter)
            .whereType<GuidePainter>(),
        isEmpty,
      );
      final slider = find.byKey(const Key('filter-intensity'));
      await tester.tapAt(tester.getCenter(slider));
      await tester.pump();
      expect(coach.photoFilter.intensity, closeTo(.5, .02));
      final selectedPreset = coach.photoFilter;
      final adjustmentSlider = find.byKey(const Key('photo-adjustment'));
      await tester.tapAt(
        tester.getCenter(adjustmentSlider) + const Offset(45, 0),
      );
      await tester.pump();
      expect(coach.photoFilter.brightness, greaterThan(0));
      expect(
        tester.widget<FilteredPhoto>(find.byType(FilteredPhoto)).filter,
        coach.photoFilter,
      );
      await tester.tap(find.byKey(const Key('reset-photo-adjustments')));
      await tester.pump();
      expect(coach.photoFilter, selectedPreset);
      expect(tester.widget<Slider>(adjustmentSlider).value, 0);
      // Original remains a useful base for explicit adjustments.
      await tester.tap(find.byKey(const Key('filter-original')));
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(adjustmentSlider) + const Offset(35, 0),
      );
      await tester.pump();
      expect(coach.photoFilter.style, PhotoStyle.original);
      expect(coach.photoFilter.brightness, greaterThan(0));
      expect(coach.photoFilter.isOriginal, false);
      await tester.tap(find.byKey(const Key('filter-film')));
      await tester.pump();
      await tester.tapAt(tester.getCenter(slider));
      await tester.tap(find.byKey(const Key('adjustment-contrast')));
      await tester.pump();
      expect(tester.widget<Slider>(adjustmentSlider).value, 0);
      await tester.tapAt(
        tester.getCenter(adjustmentSlider) - const Offset(25, 0),
      );
      await tester.pump();
      expect(coach.photoFilter.contrast, lessThan(0));
      expect(coach.photoFilter.brightness, greaterThan(0));
      const previewDir = String.fromEnvironment('FILTER_PREVIEW_DIR');
      if (previewDir.isNotEmpty) {
        await tester.runAsync(() async {
          await Directory(previewDir).create(recursive: true);
        });
        await tester.pumpAndSettle();
        await savePreview(tester, '$previewDir/filter-controls.png');
      }
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      expect(coach.initialized, true);
      expect(find.text('滤镜 · 胶片'), findsOneWidget);
      expect(tester.getRect(viewfinder), previewRect);
      if (previewDir.isNotEmpty) {
        await savePreview(tester, '$previewDir/filter-viewfinder.png');
      }
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpAndSettle();
      final compactPreview = tester.getRect(viewfinder);
      final compactFilter = tester.getRect(filterButton);
      expect(compactFilter.top, greaterThanOrEqualTo(compactPreview.bottom));
      expect(compactFilter.center.dy, tester.getCenter(title).dy);
      expect(tester.takeException(), isNull);
      if (previewDir.isNotEmpty) {
        await savePreview(tester, '$previewDir/filter-compact.png');
      }
      await tester.tap(filterButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('reset-photo-adjustments')));
      await tester.pump();
      expect(coach.photoFilter.hasAdjustments, false);
      expect(coach.photoFilter.style, PhotoStyle.film);
      expect(coach.photoFilter.intensity, closeTo(.5, .02));
      if (previewDir.isNotEmpty) {
        await savePreview(tester, '$previewDir/filter-compact-controls.png');
      }
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      unawaited(frames.close());
      await tester.pump();
    },
  );
}
