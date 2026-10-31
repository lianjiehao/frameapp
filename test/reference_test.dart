import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/core/composition.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/gallery_error.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/services/references.dart';
import 'package:framecoach/services/reference_catalog.dart';
import 'package:framecoach/services/reference_store_native.dart';
import 'package:framecoach/ui/guides.dart';
import 'package:framecoach/ui/reference_library.dart';
import 'package:framecoach/ui/pose_import_hint.dart';
import 'package:framecoach/ui/pose_controls.dart';
import 'package:framecoach/ui/reference_overlay.dart';
import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'widget_test.dart' show loadAppFonts;

class TestImagePicker extends ImagePicker {
  XFile? recovered, picked;
  int requests = 0;
  @override
  Future<LostDataResponse> retrieveLostData() async => recovered == null
      ? LostDataResponse.empty()
      : LostDataResponse(files: [recovered!]);
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    requests++;
    expect(source, ImageSource.gallery);
    expect(requestFullMetadata, isFalse);
    return picked;
  }
}

class MemoryReferences implements ReferenceStore {
  List<ReferenceAsset> assets = [];
  Set<String> templateFavorites = {};
  int reads = 0, writes = 0;
  bool fail = false, failRead = false;
  @override
  Future<List<ReferenceAsset>> load() async {
    reads++;
    if (failRead) throw StateError('unavailable index');
    return List.of(assets);
  }

  @override
  Future<void> write(List<ReferenceAsset> next) async {
    if (fail) throw StateError('disk full');
    writes++;
    assets = List.of(next);
  }

  @override
  Future<Set<String>> loadTemplateFavorites() async =>
      Set.of(templateFavorites);

  @override
  Future<void> writeTemplateFavorites(Set<String> ids) async {
    if (fail) throw StateError('disk full');
    templateFavorites = Set.of(ids);
  }
}

class PendingReferences extends MemoryReferences {
  final pending = Completer<List<ReferenceAsset>>();
  @override
  Future<List<ReferenceAsset>> load() {
    reads++;
    return pending.future;
  }
}

Future<void> exportReferencePreview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('EXPORT_REFERENCE_PREVIEWS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('reference-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('artifacts/references').create(recursive: true);
      await File(
        'artifacts/references/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void expectCenteredConnectedSteps(WidgetTester tester, String rowKey) {
  final subtitle = tester.getRect(find.byKey(const Key('shooting-subtitle')));
  final row = find.byKey(Key(rowKey));
  final rowRect = tester.getRect(row);
  expect(rowRect.top - subtitle.top, closeTo(8, .001));
  expect(subtitle.bottom - rowRect.bottom, closeTo(8, .001));
  expect(rowRect.center.dy, closeTo(subtitle.center.dy, .001));
  final labels = find.descendant(of: row, matching: find.byType(Text));
  expect(labels, findsNWidgets(6));
  for (var i = 1; i < 3; i++) {
    final connector = find.descendant(
      of: row,
      matching: find.byKey(ValueKey('step-connector-$i')),
    );
    expect(connector, findsOneWidget);
    final line = tester.getRect(connector);
    expect(line.height, 1);
    expect(line.width, greaterThan(24));
    expect(line.center.dy, closeTo(rowRect.center.dy, .001));
    expect(
      line.left,
      closeTo(tester.getRect(labels.at(i * 2 - 1)).right, .001),
    );
    expect(line.right, closeTo(tester.getRect(labels.at(i * 2)).left, .001));
  }
}

// Recommendation reserves breathing room below the fixed step indicator.
// Other phases keep the original centered 3:4 preview and 10px side margins.
void expectOriginalCompositionLayout(WidgetTester tester) {
  final header = tester.getRect(find.byKey(const Key('camera-header')));
  final steps = tester.getRect(find.byKey(const Key('shooting-subtitle')));
  final footer = tester.getRect(find.byKey(const Key('camera-controls')));
  final preview = tester.getRect(find.byKey(const Key('viewfinder')));
  final recommending = find
      .byKey(const Key('composition-candidates'))
      .evaluate()
      .isNotEmpty;
  final previewTop = steps.bottom + (recommending ? 16 : 0);
  final availableHeight = footer.top - previewTop;
  final height = ((header.width - 20) / .75).clamp(0.0, availableHeight);
  expect(preview.height, closeTo(height, .001));
  expect(preview.width, closeTo(height * .75, .001));
  expect(preview.center.dx, closeTo(header.center.dx, .001));
  expect(
    preview.center.dy,
    closeTo(
      recommending ? previewTop + height / 2 : (steps.bottom + footer.top) / 2,
      .001,
    ),
  );
  expectCenteredConnectedSteps(tester, 'composition-steps');
}

void expectPoseStep(WidgetTester tester, int active) {
  expectCenteredConnectedSteps(tester, 'pose-steps');
  for (int i = 0; i < 3; i++) {
    final label = tester.widget<Text>(
      find.byKey(ValueKey('pose-step-${i + 1}')),
    );
    expect(label.style!.color, i == active ? acid : muted);
  }
}

Future<Uint8List> referencePng([
  Color color = Colors.pink,
  int width = 60,
  int height = 80,
]) async {
  final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
  canvas.drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('import hint stays eligible until actually displayed', () async {
    final library = ReferenceLibrary(store: MemoryReferences());
    expect(await library.needsImportHint(), isTrue);
    expect(await library.needsImportHint(), isTrue);
    await library.markImportHintSeen();
    expect(await library.needsImportHint(), isFalse);
    final reopened = ReferenceLibrary(store: MemoryReferences());
    expect(await reopened.needsImportHint(), isFalse);
    reopened.dispose();
    library.dispose();
  });

  testWidgets(
    'floating import tip animates once, stays interactive and respects reduced motion',
    (tester) async {
      final link = LayerLink();
      var imports = 0, dismissals = 0;
      Future<void> mount(bool reducedMotion) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reducedMotion,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 22,
                  top: 220,
                  child: CompositedTransformTarget(
                    link: link,
                    child: const SizedBox(width: 240, height: 44),
                  ),
                ),
                Positioned.fill(
                  child: PoseImportHint(
                    key: ValueKey(reducedMotion),
                    link: link,
                    onImport: () => imports++,
                    onDismiss: () => dismissals++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await mount(false);
      final fade = find.descendant(
        of: find.byType(PoseImportHint),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(fade).opacity, 0);
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.widget<Opacity>(fade).opacity, greaterThan(0));
      expect(tester.widget<Opacity>(fade).opacity, lessThan(1));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(fade).opacity, 1);
      await tester.tap(find.byKey(const Key('dismiss-pose-import-hint')));
      expect(dismissals, 1);
      expect(imports, 0);
      await tester.tap(find.byKey(const Key('pose-import-hint-action')));
      expect(imports, 1);
      await mount(true);
      expect(tester.widget<Opacity>(fade).opacity, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'explicit Android import recovers interrupted picker before opening another',
    () async {
      final bytes = await referencePng();
      final picker = TestImagePicker()..recovered = XFile.fromData(bytes);
      expect(await pickReferenceImage(picker: picker), orderedEquals(bytes));
      expect(picker.requests, 0);
      picker.recovered = null;
      picker.picked = XFile.fromData(bytes);
      expect(await pickReferenceImage(picker: picker), orderedEquals(bytes));
      expect(picker.requests, 1);
      picker.picked = null;
      expect(await pickReferenceImage(picker: picker), isNull);
      expect(picker.requests, 2);
    },
  );
  test('bundled catalog metadata, filtering and images are complete', () async {
    final catalog = await ReferenceCatalog.load();
    expect(catalog.templates, hasLength(139));
    expect(catalog.templates.map((item) => item.id).toSet(), hasLength(139));
    expect(catalog.filter(category: 'Gym'), hasLength(31));
    expect(catalog.filter(gender: 'male'), hasLength(64));
    expect(
      catalog
          .filter(category: 'Sitting', gender: 'female')
          .every(
            (item) => item.category == 'Sitting' && item.gender == 'female',
          ),
      isTrue,
    );
    for (final template in catalog.templates) {
      final bytes = await template.loadBytes();
      expect(bytes.take(2), orderedEquals([0xff, 0xd8]));
      expect(bytes, hasLength(template.bytes));
      expect(sha256.convert(bytes).toString(), template.sha256);
    }
  });

  test(
    'built-in favorites persist separately from imported references',
    () async {
      final store = MemoryReferences();
      final library = ReferenceLibrary(store: store);
      await library.load();
      const id = '73cec973-64e8-4ad9-b5a0-fc3c8da5e062';
      library.selectTemplate(
        id,
        await ReferenceCatalog.load().then(
          (catalog) => catalog.templates.first.loadBytes(),
        ),
      );
      await library.setTemplateSaved(id, true);
      expect(library.assets, isEmpty);
      expect(library.selected!.saved, isTrue);
      final reopened = ReferenceLibrary(store: store);
      await reopened.load();
      expect(reopened.templateFavorites, contains(id));
      expect(reopened.assets, isEmpty);
      reopened.dispose();
      library.dispose();
    },
  );
  testWidgets(
    'built-in gallery filters, favorites and selects offline photos',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = ReferenceLibrary(store: MemoryReferences());
      await library.load();
      await ReferenceCatalog.load();
      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReferenceLibrarySheet(
              library: library,
              onSelected: () => selections++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reference-template-grid')), findsOneWidget);
      final catalog = await ReferenceCatalog.load();
      final initialGrid = tester.widget<SliverGrid>(
        find.byKey(const Key('reference-template-grid')),
      );
      expect(initialGrid.delegate.estimatedChildCount, 139);
      expect(
        find.byKey(ValueKey('reference-template-${catalog.templates.last.id}')),
        findsNothing,
      );
      final delegate =
          initialGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
      final firstTile = find.byKey(
        ValueKey('reference-template-${catalog.templates.first.id}'),
      );
      final secondTile = find.byKey(
        ValueKey('reference-template-${catalog.templates[1].id}'),
      );
      expect(tester.getTopLeft(firstTile).dy, tester.getTopLeft(secondTile).dy);
      expect(
        tester.getSize(firstTile).width / tester.getSize(firstTile).height,
        closeTo(.75, .001),
      );
      final image = tester.widget<Image>(
        find.descendant(of: firstTile, matching: find.byType(Image)),
      );
      expect(image.image, isA<AssetImage>());
      await tester.runAsync(
        () => precacheImage(image.image, tester.element(firstTile)),
      );
      await tester.pump();
      final rendered = tester.renderObject<RenderImage>(
        find.descendant(of: firstTile, matching: find.byType(RawImage)),
      );
      expect(rendered.image, isNotNull);
      expect(rendered.image!.width, greaterThan(300));
      final filters = find.byKey(const Key('reference-library-filters'));
      final categories = find.byKey(const Key('reference-category-row'));
      final genders = find.byKey(const Key('reference-gender-row'));
      final fixedRects = [
        tester.getRect(filters),
        tester.getRect(categories),
        tester.getRect(genders),
      ];
      final list = find.byKey(const Key('reference-library-list'));
      final controller = tester.widget<CustomScrollView>(list).controller!;
      await tester.drag(list, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect([
        tester.getRect(filters),
        tester.getRect(categories),
        tester.getRect(genders),
      ], fixedRects);
      expect(categories.hitTestable(), findsOneWidget);
      expect(genders.hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reference-category-3')));
      await tester.pumpAndSettle();
      var grid = tester.widget<SliverGrid>(
        find.byKey(const Key('reference-template-grid')),
      );
      expect(grid.delegate.estimatedChildCount, 31);
      expect(controller.offset, 0);
      final gym = (await ReferenceCatalog.load()).filter(category: 'Gym');
      await tester.tap(
        find.byKey(ValueKey('template-favorite-${gym.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(library.templateFavorites, {gym.first.id});
      await tester.tap(find.byKey(const Key('reference-favorites-filter')));
      await tester.pumpAndSettle();
      grid = tester.widget<SliverGrid>(
        find.byKey(const Key('reference-template-grid')),
      );
      expect(grid.delegate.estimatedChildCount, 1);
      await tester.tap(
        find.byKey(ValueKey('reference-template-${gym.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(library.selected?.id, gym.first.id);
      expect(selections, 1);
      expect(library.assets, isEmpty);
      library.dispose();
    },
  );
  test(
    'normalization, dedup, favorites, restart, errors and deletion',
    () async {
      final store = MemoryReferences();
      var input = await referencePng(Colors.pink, 2200, 1200);
      final library = ReferenceLibrary(store: store, picker: () async => input);
      await library.importImage();
      expect(library.error, isNull);
      expect(library.assets, hasLength(1));
      expect(library.selected!.id, matches(r'^[a-f0-9]{64}$'));
      final codec = await ui.instantiateImageCodec(library.selected!.bytes);
      final decoded = (await codec.getNextFrame()).image;
      expect(decoded.width, 1600);
      expect(decoded.height, 873);
      decoded.dispose();
      codec.dispose();
      await library.setSaved(library.selected!, true);
      await library.importImage();
      expect(library.assets, hasLength(1));
      expect(library.selected!.saved, isTrue);
      final reopened = ReferenceLibrary(store: store, picker: () async => null);
      await reopened.load();
      expect(reopened.assets.single.saved, isTrue);
      reopened.select(reopened.assets.single);
      reopened.setOpacity(0);
      expect(reopened.opacity, 0);
      reopened.toggleMirror();
      expect(reopened.mirror, isTrue);
      reopened.select(reopened.assets.single);
      expect(reopened.mirror, isFalse);
      expect(reopened.opacity, 0);
      store.fail = true;
      await reopened.remove(reopened.selected!);
      expect(reopened.assets, hasLength(1));
      expect(reopened.selected, isNotNull);
      expect(reopened.error, isNotNull);
      store.fail = false;
      await reopened.remove(reopened.selected!);
      expect(reopened.assets, isEmpty);
      expect(reopened.selected, isNull);
      input = Uint8List.fromList([1, 2, 3]);
      await library.importImage();
      expect(library.error, isNotNull);
      expect(library.assets, hasLength(1));
      reopened.dispose();
      library.dispose();
    },
  );
  test('bounded library preserves favorites and evicts recent only', () async {
    final store = MemoryReferences();
    var input = await referencePng();
    final library = ReferenceLibrary(store: store, picker: () async => input);
    for (var i = 0; i < 20; i++) {
      input = await referencePng(Color.fromARGB(255, i * 10, 80, 140));
      await library.importImage();
      await library.setSaved(library.selected!, true);
    }
    final previous = library.selected;
    input = await referencePng(Colors.green);
    await library.importImage();
    expect(library.assets, hasLength(20));
    expect(library.selected, same(previous));
    expect(library.error, contains('已满'));
    await library.setSaved(library.assets.last, false);
    await library.importImage();
    expect(library.assets, hasLength(20));
    expect(library.assets.where((a) => a.saved), hasLength(19));
    library.dispose();
  });
  test(
    'native files survive reopen and removal deletes private copy',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'frame-reference-store-',
      );
      if (await directory.exists()) await directory.delete(recursive: true);
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final bytes = await referencePng();
      final library = ReferenceLibrary(
        store: createReferenceStore(directory: directory),
        picker: () async => bytes,
      );
      await library.importImage();
      expect(library.error, isNull);
      final file = File('${directory.path}/${library.selected!.id}.png');
      expect(await file.exists(), isTrue);
      const templateId = '73cec973-64e8-4ad9-b5a0-fc3c8da5e062';
      final nativeStore = createReferenceStore(directory: directory);
      await nativeStore.writeTemplateFavorites({templateId});
      await library.setSaved(library.selected!, true);
      final reopened = ReferenceLibrary(
        store: createReferenceStore(directory: directory),
      );
      await reopened.load();
      expect(reopened.assets.single.id, library.selected!.id);
      expect(reopened.assets.single.saved, isTrue);
      expect(await nativeStore.loadTemplateFavorites(), {templateId});
      await reopened.remove(reopened.assets.single);
      expect(await file.exists(), isFalse);
      expect(await File('${directory.path}/index.json').readAsString(), '[]');
      expect(await nativeStore.loadTemplateFavorites(), {templateId});
      reopened.dispose();
      library.dispose();
    },
  );
  test('cancel and disposal discard late picker without a write', () async {
    final store = MemoryReferences(),
        picked = Completer<Uint8List?>(),
        opened = Completer<void>();
    final library = ReferenceLibrary(
      store: store,
      picker: () {
        opened.complete();
        return picked.future;
      },
    );
    final importing = library.importImage();
    await opened.future;
    library.dispose();
    picked.complete(await referencePng());
    await importing;
    expect(store.writes, 0);
    expect(library.selected, isNull);
    final cancelled = ReferenceLibrary(store: store, picker: () async => null);
    await cancelled.importImage();
    expect(cancelled.error, isNull);
    expect(store.writes, 0);
    cancelled.dispose();
  });
  test(
    'failed initial load never replaces the stored library on import',
    () async {
      final store = MemoryReferences()..failRead = true;
      var requests = 0;
      final library = ReferenceLibrary(
        store: store,
        picker: () async {
          requests++;
          return referencePng();
        },
      );
      await library.importImage();
      expect(requests, 0);
      expect(store.writes, 0);
      expect(library.error, isNotNull);
      store.failRead = false;
      await library.importImage();
      expect(requests, 1);
      expect(store.writes, 1);
      expect(library.error, isNull);
      library.dispose();
    },
  );
  testWidgets(
    'reference disk and picker stay idle until explicit consent and import',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final consent = PrivacyConsent(store: MemoryStore());
      final store = MemoryReferences();
      var requests = 0;
      final library = ReferenceLibrary(
        store: store,
        picker: () async {
          requests++;
          return null;
        },
      );
      final coach = CameraCoach(demo: true);
      await consent.load();
      await tester.pumpWidget(
        FrameApp(coach: coach, consent: consent, references: library),
      );
      await tester.pumpAndSettle();
      expect(coach.initialized, isFalse);
      expect(store.reads, 0);
      expect(requests, 0);
      await tester.runAsync(() async {
        await consent.accept();
        await coach.initialize();
      });
      await tester.pumpAndSettle();
      expect(store.reads, 0);
      coach.setShootingMode(ShootingMode.pose);
      await tester.pumpAndSettle();
      expect(store.reads, 0);
      await tester.tap(find.byKey(const Key('open-references')));
      await tester.pumpAndSettle();
      expect(store.reads, 1);
      expect(requests, 0);
      await tester.tap(find.byKey(const Key('import-reference')));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(store.writes, 0);
      expect(find.byType(ReferenceLibrarySheet), findsOneWidget);
      expect(library.error, isNull);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  testWidgets(
    'header keeps composition steps and pose import hint is shown once across launches',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await consent.load();
      final store = PendingReferences();
      final library = ReferenceLibrary(store: store);
      final coach = _NativeUiCoach();
      if (const bool.fromEnvironment('EXPORT_REFERENCE_PREVIEWS')) {
        await tester.runAsync(loadAppFonts);
      }
      Future<void> mount(
        CameraCoach controller,
        ReferenceLibrary references,
      ) async {
        final initialized = Completer<void>();
        void onInitialized() {
          if (controller.initialized && !initialized.isCompleted) {
            initialized.complete();
          }
        }

        controller.addListener(onInitialized);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('reference-preview'),
            child: FrameApp(
              coach: controller,
              consent: consent,
              references: references,
              permissionBackend: TestPermissions()..camera = true,
            ),
          ),
        );
        final deadline = Stopwatch()..start();
        while (!initialized.isCompleted &&
            deadline.elapsed < const Duration(seconds: 10)) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump();
        }
        expect(
          initialized.isCompleted,
          isTrue,
          reason: 'Camera initialization completed',
        );
        controller.removeListener(onInitialized);
      }

      await mount(coach, library);
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('camera-header'));
      final steps = find.byKey(const Key('composition-steps'));
      expect(find.text('frame'), findsNothing);
      expect(find.text('构图模式'), findsOneWidget);
      expect(find.text('摆姿模式'), findsOneWidget);
      expect(find.byKey(const Key('pose-import-hint')), findsNothing);
      expect(store.reads, 0);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ReferenceLibrary.importHintSeenKey,
        ),
        isNull,
      );
      final labels = find.descendant(of: steps, matching: find.byType(Text));
      expect(tester.widgetList<Text>(labels).map((text) => text.data), [
        '01',
        '取景',
        '02',
        '构图',
        '03',
        '拍照',
      ]);
      for (final mode in ['composition', 'pose']) {
        final rect = tester.getRect(find.byKey(ValueKey('mode-$mode')));
        expect(tester.getRect(header).contains(rect.center), isTrue);
        expect(rect.bottom, lessThanOrEqualTo(tester.getRect(steps).top));
      }
      final originalPreview = tester.getRect(
        find.byKey(const Key('viewfinder')),
      );
      expectOriginalCompositionLayout(tester);
      await exportReferencePreview(tester, 'composition-header');
      await tester.tap(find.byKey(const Key('mode-pose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pose-import-hint')), findsOneWidget);
      final poseSteps = find.byKey(const Key('pose-steps'));
      expect(
        tester
            .widgetList<Text>(
              find.descendant(of: poseSteps, matching: find.byType(Text)),
            )
            .map((text) => text.data),
        ['01', '选图', '02', '摆姿', '03', '成片'],
      );
      expectPoseStep(tester, 0);
      expect(find.byKey(const Key('pose-select-controls')), findsOneWidget);
      expect(find.byKey(const Key('pose-direct-capture')), findsNothing);
      expect(find.byKey(const Key('reference-opacity')), findsNothing);
      expect(find.byKey(const Key('pose-recent-photo')), findsNothing);
      expect(find.text('参考图仅供取景，不会写入照片'), findsNothing);
      expect(steps, findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ReferenceLibrary.importHintSeenKey,
        ),
        isTrue,
      );
      expect(store.reads, 0);
      for (final (size, scale) in [
        (const Size(390, 844), 1.0),
        (const Size(320, 640), 1.0),
        (const Size(430, 900), 1.4),
        (const Size(320, 640), 1.4),
      ]) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('open-references'));
        expect(button.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const Key('pose-import-hint'))).bottom,
          lessThan(tester.getRect(button).top),
        );
        expect(find.byType(CompositedTransformFollower), findsOneWidget);
        expect(
          find.byKey(const Key('pose-import-hint-action')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const Key('shutter')), findsNothing);
        expect(tester.takeException(), isNull);
        await exportReferencePreview(
          tester,
          'import-hint-${size.width.toInt()}-$scale',
        );
      }
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      final opener = find.byKey(const Key('open-references'));
      final openerStyle = tester.widget<FilledButton>(opener).style!;
      expect(
        openerStyle.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(openerStyle.splashFactory, NoSplash.splashFactory);
      await tester.tap(find.byKey(const Key('pose-import-hint-action')));
      // A second queued callback must not push another sheet.
      tester.widget<FilledButton>(opener).onPressed!();
      await tester.pump();
      expect(find.byType(ReferenceLibrarySheet), findsOneWidget);
      expect(
        library.busy,
        isTrue,
        reason: 'The sheet opens before the disk read completes',
      );
      expect(store.reads, 1);
      store.pending.complete([]);
      await tester.pumpAndSettle();
      expect(library.loaded, isTrue);
      expect(find.byType(BottomSheet), findsOneWidget);
      if (const bool.fromEnvironment('EXPORT_REFERENCE_PREVIEWS')) {
        Future<void> cacheSheetImages() async {
          final images = tester.widgetList<Image>(find.byType(Image)).toList();
          final context = tester.element(find.byType(ReferenceLibrarySheet));
          await tester.runAsync(
            () => Future.wait([
              for (final image in images) precacheImage(image.image, context),
            ]),
          );
          await tester.pumpAndSettle();
        }

        await cacheSheetImages();
        await exportReferencePreview(tester, 'library-original-images');
        await tester.drag(
          find.byKey(const Key('reference-library-list')),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        await cacheSheetImages();
        await exportReferencePreview(tester, 'library-scrolled');
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const Key('pose-import-hint')), findsNothing);
      await exportReferencePreview(tester, 'import-after-close');
      await tester.tap(find.byKey(const Key('mode-composition')));
      await tester.pumpAndSettle();
      expect(steps, findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('viewfinder'))),
        originalPreview,
      );
      await tester.tap(find.byKey(const Key('mode-pose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pose-import-hint')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final reopened = ReferenceLibrary(store: MemoryReferences());
      final nextCoach = _NativeUiCoach();
      await mount(nextCoach, reopened);
      await tester.pumpAndSettle();
      expect(nextCoach.shootingMode, ShootingMode.composition);
      await tester.tap(find.byKey(const Key('mode-pose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pose-import-hint')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  for (final mode in ShootingMode.values) {
    testWidgets(
      '${mode.name} direct capture saves once and supports retaking',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          ReferenceLibrary.importHintSeenKey: true,
        });
        final consent = PrivacyConsent(
          store: MemoryStore(PolicyDocument.revision),
        );
        final library = ReferenceLibrary(store: MemoryReferences());
        var saves = 0;
        Uint8List? saved;
        final coach = CameraCoach(
          demo: true,
          previewFrames: const Stream.empty(),
          now: tester.binding.clock.now,
          saver: (bytes, _) async {
            saves++;
            saved = bytes;
          },
        );
        await tester.runAsync(() async {
          await consent.load();
          await coach.initialize();
        });
        await tester.pumpWidget(
          FrameApp(
            coach: coach,
            consent: consent,
            references: library,
            permissionBackend: TestPermissions()..photos = true,
          ),
        );
        if (mode == ShootingMode.pose) {
          library.selectTemplate(
            'capture-reference',
            await tester.runAsync(referencePng) ?? Uint8List(0),
          );
          coach.setShootingMode(ShootingMode.pose);
        } else {
          coach.choosePlan(
            const CompositionPlan(
              CompositionKind.thirds,
              .8,
              Point2(1 / 3, 1 / 3),
              .5,
              '',
            ),
          );
          coach.startGuidance();
        }
        await tester.pumpAndSettle();
        expect(library.selected != null, mode == ShootingMode.pose);
        expect(coach.phase, isNot(CapturePhase.ready));
        final direct = find.byKey(
          Key(
            mode == ShootingMode.pose
                ? 'shutter'
                : 'composition-direct-capture',
          ),
        );
        expect(direct.hitTestable(), findsOneWidget);
        final capture = mode == ShootingMode.pose
            ? tester.widget<GestureDetector>(direct).onTap!
            : tester.widget<TextButton>(direct).onPressed!;
        await tester.tap(direct);
        capture();
        expect(coach.phase, CapturePhase.capturing);
        final deadline = Stopwatch()..start();
        while (coach.phase != CapturePhase.captured &&
            deadline.elapsed < const Duration(seconds: 10)) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(coach.phase, CapturePhase.captured);
        expect(coach.saved, isTrue);
        expect(saves, 1);
        expect(saved, orderedEquals(coach.photo!));
        expect(find.byKey(const Key('open-photo')), findsOneWidget);
        expect(direct, findsNothing);
        await tester.tap(find.byKey(const Key('next-photo')));
        await tester.pumpAndSettle();
        expect(coach.phase, CapturePhase.framing);
        if (mode == ShootingMode.pose) {
          expect(find.byKey(const Key('open-photo')), findsOneWidget);
        } else {
          expect(find.byKey(const Key('open-photo')), findsNothing);
        }
        if (mode == ShootingMode.pose) {
          expectPoseStep(tester, 1);
          expect(direct.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        consent.dispose();
      },
    );
  }

  testWidgets(
    'pose shooting shares filters immediately after reference selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        ReferenceLibrary.importHintSeenKey: true,
      });
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      final library = ReferenceLibrary(store: MemoryReferences());
      final coach = CameraCoach(
        demo: true,
        previewFrames: const Stream.empty(),
      );
      late Uint8List bytes;
      await tester.runAsync(() async {
        await consent.load();
        await coach.initialize();
        bytes = await referencePng();
      });
      await tester.pumpWidget(
        FrameApp(coach: coach, consent: consent, references: library),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-warm')));
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      coach.setShootingMode(ShootingMode.pose);
      await tester.pumpAndSettle();
      expectPoseStep(tester, 0);
      expect(find.byKey(const Key('open-filters')), findsOneWidget);
      library.selectTemplate('filter-reference', bytes);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shutter')).hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('start-posing')), findsNothing);
      expectPoseStep(tester, 1);
      expect(find.byKey(const Key('open-filters')), findsNothing);
      await tester.tap(find.byKey(const Key('camera-more')));
      await tester.pumpAndSettle();
      expect(find.text('滤镜 · 暖光'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-film')));
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-more')));
      await tester.pumpAndSettle();
      expect(find.text('滤镜 · 胶片'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mode-composition')));
      await tester.pumpAndSettle();
      expect(find.text('滤镜 · 胶片'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  testWidgets(
    'reference artwork fills preview height and stays centered across sizes and aspect ratios',
    (tester) async {
      final library = ReferenceLibrary(store: MemoryReferences());
      library.setOpacity(1);
      for (final source in [
        const Size(60, 160),
        const Size(120, 160),
        const Size(320, 160),
      ]) {
        late Uint8List bytes;
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(Offset.zero & source, Paint()..color = Colors.red);
          canvas.drawRect(
            Rect.fromLTWH(source.width / 2, 0, source.width / 2, source.height),
            Paint()..color = Colors.blue,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            source.width.toInt(),
            source.height.toInt(),
          );
          try {
            bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!.buffer.asUint8List();
          } finally {
            image.dispose();
            picture.dispose();
          }
        });
        library.selectTemplate('sizing-$source', bytes);
        for (final preview in [const Size(180, 240), const Size(240, 320)]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: RepaintBoundary(
                  key: const Key('fitted-reference'),
                  child: SizedBox.fromSize(
                    size: preview,
                    child: ColoredBox(
                      color: Colors.black,
                      child: ReferenceOverlay(library: library),
                    ),
                  ),
                ),
              ),
            ),
          );
          final context = tester.element(find.byType(ReferenceOverlay));
          await tester.runAsync(
            () => precacheImage(MemoryImage(bytes), context),
          );
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('fitted-reference')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              final fittedWidth = source.width * preview.height / source.height;
              final left = (preview.width - fittedWidth) / 2;
              for (final y in [1, image.height ~/ 2, image.height - 2]) {
                for (final x in [
                  1,
                  image.width ~/ 4,
                  image.width * 3 ~/ 4,
                  image.width - 2,
                ]) {
                  final inside = x >= left && x < left + fittedWidth;
                  final color = !inside
                      ? Colors.black
                      : x < image.width / 2
                      ? Colors.red
                      : Colors.blue;
                  final index = (y * image.width + x) * 4;
                  expect(pixels.sublist(index, index + 4), [
                    (color.r * 255).round(),
                    (color.g * 255).round(),
                    (color.b * 255).round(),
                    255,
                  ], reason: 'source=$source preview=$preview pixel=($x,$y)');
                }
              }
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'selecting a reference immediately exposes capture and adjustments ($reducedMotion)',
      (tester) async {
        final library = ReferenceLibrary(store: MemoryReferences());
        late Uint8List bytes;
        await tester.runAsync(() async {
          bytes = await referencePng();
        });
        var captures = 0, imports = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: ListenableBuilder(
                      listenable: library,
                      builder: (context, _) => PoseControls(
                        library: library,
                        importLink: LayerLink(),
                        enabled: true,
                        canCapture: true,
                        capturing: false,
                        onImport: () => imports++,
                        onCapture: () => captures++,
                        onRestart: library.clearSelection,
                        onShowPhoto: null,
                        filterButton: const Text('原图'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('shutter')), findsNothing);
        library.selectTemplate('reference', bytes);
        await tester.pump();
        expect(find.byKey(const Key('shutter')).hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('reference-opacity')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const Key('start-posing')), findsNothing);
        expect(find.byKey(const Key('reset-reference')), findsNothing);
        expect(find.byKey(const Key('edit-reference')), findsNothing);
        expect(captures, 0);
        await tester.tap(find.byKey(const Key('mirror-reference')));
        await tester.pump();
        expect(library.mirror, isTrue);
        expect(
          tester
              .widget<GestureDetector>(find.byKey(const Key('shutter')))
              .onTap,
          isNotNull,
        );
        final mirrorRect = tester.getRect(
          find.byKey(const Key('mirror-reference')),
        );
        final changeRect = tester.getRect(
          find.byKey(const Key('open-references')),
        );
        final toolsRect = tester.getRect(
          find.byKey(const Key('reference-adjustment-bar')),
        );
        expect(changeRect.right + 8, closeTo(toolsRect.left, .01));
        expect(changeRect.center.dy, toolsRect.center.dy);
        expect(mirrorRect.center.dy, toolsRect.center.dy);
        expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
        expect(find.text('换参考图'), findsNothing);
        expect(find.byKey(const Key('toggle-reference')), findsNothing);
        expect(find.byIcon(Icons.visibility_outlined), findsNothing);
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('open-photo')))
              .onPressed,
          isNull,
        );
        final opacity = tester.widget<Slider>(
          find.byKey(const Key('reference-opacity')),
        );
        opacity.onChanged!(0);
        await tester.pump();
        expect(library.opacity, 0);
        opacity.onChanged!(.6);
        await tester.pump();
        expect(library.opacity, .6);
        expect(library.visible, isTrue);

        await tester.tap(find.byKey(const Key('shutter')));
        expect(captures, 1);
        await tester.tap(find.byKey(const Key('open-references')));
        expect(imports, 1);
        expect(captures, 1);
        await tester.pumpWidget(const SizedBox());
        library.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'replacement cancellation preserves the reference and back returns directly to selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        ReferenceLibrary.importHintSeenKey: true,
      });
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      final store = MemoryReferences();
      late Uint8List bytes;
      final library = ReferenceLibrary(store: store, picker: () async => bytes);
      final coach = CameraCoach(
        demo: true,
        previewFrames: const Stream.empty(),
      );
      await tester.runAsync(() async {
        bytes = await referencePng();
        await consent.load();
        await coach.initialize();
        await library.importImage();
        await library.setSaved(library.selected!, true);
      });
      coach.setShootingMode(ShootingMode.pose);
      await tester.pumpWidget(
        FrameApp(coach: coach, consent: consent, references: library),
      );
      await tester.pumpAndSettle();
      final asset = library.selected!;
      library.setOpacity(.65);
      library.toggleMirror();
      await tester.pumpAndSettle();
      final preview = tester.getRect(find.byKey(const Key('viewfinder')));
      final footer = tester.getRect(find.byKey(const Key('camera-controls')));
      expectPoseStep(tester, 1);
      expect(find.text('拖动或双指缩放参考图'), findsNothing);
      expect(find.text('完成摆姿'), findsNothing);
      expect(find.byKey(const Key('shutter')), findsOneWidget);
      expect(find.byKey(const Key('open-photo')), findsOneWidget);
      final thumbnail =
          tester
                  .widget<Image>(find.byKey(const Key('reference-thumbnail')))
                  .image
              as ResizeImage;
      expect((thumbnail.imageProvider as MemoryImage).bytes, same(asset.bytes));
      tester
          .widget<Slider>(find.byKey(const Key('reference-opacity')))
          .onChanged!(.55);
      await tester.pumpAndSettle();
      // Cancelling replacement preserves the image and all adjustments.
      await tester.tap(find.byKey(const Key('open-references')));
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceLibrarySheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceLibrarySheet), findsNothing);
      expect(library.selected, same(asset));
      expectPoseStep(tester, 1);
      expect(library.opacity, .55);
      expect(library.mirror, isTrue);
      expect(tester.getRect(find.byKey(const Key('viewfinder'))), preview);
      expect(tester.getRect(find.byKey(const Key('camera-controls'))), footer);
      expect(find.byKey(const Key('start-posing')), findsNothing);
      expect(find.byKey(const Key('reset-reference')), findsNothing);
      expect(find.byKey(const Key('viewfinder-status')), findsNothing);
      expect(find.byKey(const Key('shutter')).hitTestable(), findsOneWidget);
      await tester.dragFrom(preview.center, const Offset(25, 20));
      await tester.pumpAndSettle();
      expect(library.selected, same(asset));
      expect(library.opacity, .55);
      expect(library.mirror, isTrue);
      expect(coach.photo, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expectPoseStep(tester, 0);
      expect(library.selected, isNull);
      expect(library.assets.single, same(asset));
      expect(store.assets.single.saved, isTrue);
      expect(find.byKey(const Key('pose-select-controls')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  testWidgets(
    'composition keeps committed layout and pose controls preserve preview space',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        ReferenceLibrary.importHintSeenKey: true,
      });
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await consent.load();
      final library = ReferenceLibrary(store: MemoryReferences());
      final coach = CameraCoach(
        demo: true,
        previewFrames: const Stream.empty(),
        now: tester.binding.clock.now,
      );
      late Uint8List bytes;
      await tester.runAsync(() async {
        await loadAppFonts();
        bytes = await File('test/fixtures/pose_person.png').readAsBytes();
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('reference-preview'),
          child: FrameApp(coach: coach, consent: consent, references: library),
        ),
      );
      final deadline = Stopwatch()..start();
      while (!coach.initialized &&
          deadline.elapsed < const Duration(seconds: 10)) {
        await tester.runAsync(() => Future<void>(() {}));
        await tester.pump();
      }
      expect(coach.initialized, isTrue);
      for (final (size, scale, padding) in [
        (const Size(390, 844), 1.0, const FakeViewPadding(top: 47, bottom: 34)),
        (const Size(320, 568), 1.4, const FakeViewPadding(top: 24, bottom: 24)),
        (const Size(430, 932), 1.4, const FakeViewPadding(top: 59, bottom: 34)),
        (const Size(1100, 900), 1.0, const FakeViewPadding()),
      ]) {
        tester.view.physicalSize = size;
        tester.view.padding = padding;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        coach.setShootingMode(ShootingMode.composition);
        await tester.pumpAndSettle();
        final viewfinder = find.byKey(const Key('viewfinder'));
        final original = tester.getRect(viewfinder);
        expectOriginalCompositionLayout(tester);
        expect(original.width / original.height, closeTo(.75, .001));
        await exportReferencePreview(
          tester,
          'composition-safe-${size.width.toInt()}-$scale',
        );
        coach.setShootingMode(ShootingMode.pose);
        await tester.pumpAndSettle();
        expectPoseStep(tester, 0);
        expect(find.byKey(const Key('pose-select-controls')), findsOneWidget);
        expect(find.byKey(const Key('pose-direct-capture')), findsNothing);
        expect(
          find.byKey(const Key('open-filters')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('open-references')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(viewfinder).top, closeTo(original.top, 12));
        expect(find.byKey(const Key('shutter')), findsNothing);
        await exportReferencePreview(
          tester,
          'pose-select-safe-${size.width.toInt()}-$scale',
        );
        final selectionPreview = tester.getRect(viewfinder);
        library.selectTemplate('layout-reference', bytes);
        await tester.pumpAndSettle();
        final imageContext = tester.element(viewfinder);
        await tester.runAsync(() async {
          await precacheImage(MemoryImage(bytes), imageContext);
          if (!imageContext.mounted) return;
          await precacheImage(
            ResizeImage(MemoryImage(bytes), width: 32),
            imageContext,
          );
        });
        await tester.pumpAndSettle();
        expectPoseStep(tester, 1);
        expect(find.text('开始摆姿'), findsNothing);
        expect(find.byKey(const Key('shutter')), findsOneWidget);
        expect(find.byKey(const Key('open-photo')), findsOneWidget);
        expect(find.byKey(const Key('hide-reference')), findsNothing);
        final selectedPreview = tester.getRect(viewfinder);
        final controls = tester.getRect(
          find.byKey(const Key('camera-controls')),
        );
        expect(controls.height, lessThan(192));
        expect(
          selectedPreview.width / selectedPreview.height,
          closeTo(.75, .001),
        );
        expect(
          selectedPreview.top,
          greaterThanOrEqualTo(selectionPreview.top - 12),
        );
        final toolsRect = tester.getRect(
          find.byKey(const Key('reference-adjustment-bar')),
        );
        expect(toolsRect.top, greaterThanOrEqualTo(selectedPreview.bottom));
        final change = tester.getRect(find.byKey(const Key('open-references')));
        expect(change.height, greaterThanOrEqualTo(44));
        final mirror = tester.getRect(
          find.byKey(const Key('mirror-reference')),
        );
        expect(mirror.width, greaterThanOrEqualTo(44));
        expect(mirror.height, greaterThanOrEqualTo(44));
        expect(find.byKey(const Key('reset-reference')), findsNothing);
        library.setOpacity(.4);
        await tester.pump();
        final beforeOpacity = library.opacity;
        await tester.drag(
          find.byKey(const Key('reference-opacity')),
          const Offset(30, 0),
        );
        await tester.pumpAndSettle();
        expect(library.opacity, greaterThan(beforeOpacity));
        expect(tester.getRect(viewfinder), selectedPreview);
        final suffix = '${size.width.toInt()}-$scale';
        await exportReferencePreview(tester, 'pose-reference-$suffix');
        expect(find.byKey(const Key('reference-opacity')), findsOneWidget);
        expect(find.byKey(const Key('mirror-reference')), findsOneWidget);
        expect(find.byKey(const Key('reference-thumbnail')), findsOneWidget);
        final shutter = tester.getRect(find.byKey(const Key('shutter')));
        final gallery = tester.getRect(find.byKey(const Key('open-photo')));
        final edit = tester.getRect(find.byKey(const Key('open-references')));
        expect(shutter.center.dx, controls.center.dx);
        expect(gallery.center.dy, shutter.center.dy);
        expect(gallery.left, greaterThanOrEqualTo(shutter.right));
        expect(
          tester.getRect(find.byKey(const Key('pose-restart'))).center.dy,
          shutter.center.dy,
        );
        expect(edit.center.dy, toolsRect.center.dy);
        expect(edit.right + 8, closeTo(toolsRect.left, .01));
        expect(toolsRect.bottom, lessThan(shutter.top));
        expect(find.byKey(const Key('toggle-reference')), findsNothing);
        expect(find.byKey(const Key('pose-direct-capture')), findsNothing);
        expect(find.byKey(const Key('pose-hold-progress')), findsNothing);
        expect(
          find.byKey(const Key('pose-restart')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester
              .widget<GestureDetector>(find.byKey(const Key('shutter')))
              .onTap,
          isNotNull,
        );
        expect(tester.getRect(viewfinder), selectedPreview);
        expect(
          tester.getRect(find.byKey(const Key('camera-controls'))),
          controls,
        );
        await exportReferencePreview(tester, 'pose-posing-$suffix');
        await tester.tap(find.byKey(const Key('pose-restart')));
        await tester.pumpAndSettle();
        expect(library.selected, isNull);
        expect(find.byKey(const Key('pose-select-controls')), findsOneWidget);
        await tester.tap(find.byKey(const Key('mode-composition')));
        await tester.pumpAndSettle();
        expect(tester.getRect(viewfinder), original);
        coach.phase = CapturePhase.recommending;
        coach.plans = [
          const CompositionPlan(
            CompositionKind.thirds,
            .8,
            Point2(1 / 3, 1 / 3),
            .5,
            '将主体放在三分线上，保留环境。',
          ),
        ];
        coach.choosePlan(coach.plans.single);
        await tester.pumpAndSettle();
        expectOriginalCompositionLayout(tester);
        expect(
          find.byKey(const Key('start-guidance')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('start-guidance')));
        await tester.pumpAndSettle();
        expectOriginalCompositionLayout(tester);
        final guidingShutter = tester.getRect(find.byKey(const Key('shutter')));
        final compositionDirect = tester.getRect(
          find.byKey(const Key('composition-direct-capture')),
        );
        final reset = tester.getRect(find.text('重新取景'));
        expect(
          compositionDirect.top,
          greaterThanOrEqualTo(guidingShutter.bottom),
        );
        expect(reset.center.dy, guidingShutter.center.dy);
        expect(compositionDirect.center.dx, guidingShutter.center.dx);
        expect(
          guidingShutter.center.dx,
          tester.getRect(find.byKey(const Key('camera-controls'))).center.dx,
        );
        await exportReferencePreview(
          tester,
          'composition-guiding-safe-${size.width.toInt()}-$scale',
        );
        coach.phase = CapturePhase.ready;
        coach.choosePlan(coach.plans.single);
        coach.phase = CapturePhase.ready;
        await tester.pump();
        expect(
          find.byKey(const Key('composition-direct-capture')),
          findsNothing,
        );
        expect(find.byKey(const Key('demo-align')), findsOneWidget);
        coach.setShootingMode(ShootingMode.pose);
        await tester.pumpAndSettle();
        expectPoseStep(tester, 0);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    },
  );

  for (final (width, scale) in [
    (320.0, 1.0),
    (390.0, 1.0),
    (430.0, 1.4),
    (320.0, 1.4),
  ]) {
    testWidgets('overlay, clean capture and retry at $width / $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      final store = MemoryReferences();
      late Uint8List input;
      final library = ReferenceLibrary(store: store, picker: () async => input);
      var attempts = 0;
      Uint8List? saved;
      final coach = CameraCoach(
        demo: true,
        saver: (bytes, _) async {
          if (++attempts == 1) {
            throw const PhotoSaveException('test save failure');
          }
          saved = bytes;
        },
      );
      await tester.runAsync(() async {
        await consent.load();
        await coach.initialize();
        input = await File('test/fixtures/pose_person.png').readAsBytes();
        await library.importImage();
        if (const bool.fromEnvironment('EXPORT_REFERENCE_PREVIEWS')) {
          await loadAppFonts();
        }
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('reference-preview'),
          child: FrameApp(
            coach: coach,
            consent: consent,
            references: library,
            permissionBackend: TestPermissions()..photos = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(coach.shootingMode, ShootingMode.composition);
      expectOriginalCompositionLayout(tester);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((p) => p.painter is GuidePainter),
        isNotEmpty,
      );
      coach.setShootingMode(ShootingMode.pose);
      await tester.pumpAndSettle();
      expectPoseStep(tester, 1);
      final poseRect = tester.getRect(find.byKey(const Key('viewfinder')));
      await tester.runAsync(() async {
        final context = tester.element(find.byKey(const Key('viewfinder')));
        await precacheImage(MemoryImage(library.selected!.bytes), context);
        if (!context.mounted) return;
        await precacheImage(
          ResizeImage(MemoryImage(library.selected!.bytes), width: 32),
          context,
        );
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reference-overlay')), findsOneWidget);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((p) => p.painter is GuidePainter),
        isEmpty,
      );
      expect(find.text('姿势相似度'), findsNothing);
      expect(coach.canCapturePose, isTrue);
      final preview = tester.getSize(find.byKey(const Key('viewfinder')));
      expect(preview.width / preview.height, closeTo(.75, .001));
      final previousPan = coach.demoPan;
      await tester.drag(
        find.byKey(const Key('viewfinder')),
        const Offset(30, 20),
      );
      await tester.pumpAndSettle();
      expect(coach.demoPan, previousPan);
      expect(find.byKey(const Key('reference-gesture')), findsNothing);
      expect(find.byKey(const Key('reset-reference')), findsNothing);
      expect(find.byKey(const Key('start-posing')), findsNothing);
      await tester.tap(find.byKey(const Key('mirror-reference')));
      await tester.pump();
      expect(library.mirror, isTrue);
      tester
          .widget<Slider>(find.byKey(const Key('reference-opacity')))
          .onChanged!(.7);
      await tester.pump();
      expect(library.opacity, .7);
      Future<void> screenshot(String name) async {
        if (!const bool.fromEnvironment('EXPORT_REFERENCE_PREVIEWS')) return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('reference-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('artifacts/references').create(recursive: true);
          await File(
            'artifacts/references/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      final suffix = '${width.toInt()}-$scale';
      await screenshot('overlay-$suffix');
      expect(find.byKey(const Key('shutter')).hitTestable(), findsOneWidget);
      final shutterRect = tester.getRect(find.byKey(const Key('shutter')));
      expect(tester.getRect(find.byKey(const Key('viewfinder'))), poseRect);
      expectPoseStep(tester, 1);
      expect(find.byKey(const Key('reference-opacity')), findsOneWidget);
      expect(library.opacity, .7);
      await screenshot('pose-ready-$suffix');
      await tester.tap(find.byKey(const Key('open-references')));
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceLibrarySheet), findsOneWidget);
      await screenshot('library-$suffix');
      final catalog = await ReferenceCatalog.load();
      await tester.tap(
        find
            .byKey(ValueKey('reference-template-${catalog.templates.first.id}'))
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceLibrarySheet), findsNothing);
      expect(library.selected?.id, catalog.templates.first.id);
      if (const bool.fromEnvironment('EXPORT_REFERENCE_PREVIEWS')) {
        final context = tester.element(find.byKey(const Key('viewfinder')));
        await tester.runAsync(
          () => precacheImage(MemoryImage(library.selected!.bytes), context),
        );
        await tester.pumpAndSettle();
        await screenshot('pose-template-$suffix');
      }
      expect(tester.takeException(), isNull);
      final baseline = CameraCoach(demo: true, saver: (_, _) async {});
      await tester.runAsync(() async {
        await baseline.initialize();
        baseline.setShootingMode(ShootingMode.pose);
        await baseline.takePhoto(overrideGuidance: true);
      });
      final expected = baseline.photo!;
      expectPoseStep(tester, 1);
      expect(find.byKey(const Key('start-posing')), findsNothing);
      expect(tester.getRect(find.byKey(const Key('shutter'))), shutterRect);
      expect(
        tester.widget<GestureDetector>(find.byKey(const Key('shutter'))).onTap,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('shutter')));
      expect(coach.phase, CapturePhase.capturing);
      await tester.pump();
      expectPoseStep(tester, 1);
      final captureDeadline = Stopwatch()..start();
      while (coach.phase != CapturePhase.captured &&
          captureDeadline.elapsed < const Duration(seconds: 10)) {
        await tester.runAsync(() => Future<void>(() {}));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(coach.phase, CapturePhase.captured);
      expectPoseStep(tester, 2);
      expect(coach.saved, isFalse);
      expect(coach.photo, orderedEquals(expected));
      expect(find.byKey(const Key('reference-overlay')), findsNothing);
      coach.setShootingMode(ShootingMode.composition);
      expect(coach.isPose, isTrue);
      await tester.runAsync(() => coach.retrySave(explicit: true));
      await tester.pumpAndSettle();
      expect(coach.saved, isTrue);
      expect(saved, orderedEquals(expected));
      await tester.tap(find.byKey(const Key('next-photo')));
      await tester.pumpAndSettle();
      expect(library.selected, isNotNull);
      expectPoseStep(tester, 1);
      expect(find.byKey(const Key('reference-overlay')), findsOneWidget);
      await consent.withdraw();
      await tester.pumpAndSettle();
      expect(library.selected, isNull);
      expect(coach.disposed, isTrue);
      expect(coach.photo, isNull);
      expect(store.assets, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      baseline.dispose();
      consent.dispose();
    });
  }
}

// Exercise native mode navigation without opening a device camera.
class _NativeUiCoach extends CameraCoach {
  _NativeUiCoach() : super(demo: false);

  @override
  Future<void> initialize() async {
    initialized = true;
    notifyListeners();
  }
}
