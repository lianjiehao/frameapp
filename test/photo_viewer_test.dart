import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/services/references.dart';
import 'package:framecoach/ui/photo_viewer.dart';
import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'reference_test.dart'
    show MemoryReferences, referencePng, exportReferencePreview;
import 'widget_test.dart' show loadAppFonts;

void main() {
  for (final mode in ShootingMode.values) {
    for (final size in [const Size(390, 844), const Size(1100, 900)]) {
      testWidgets(
        'captured ${mode.name} photo fills $size and clears on withdrawal',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final consent = PrivacyConsent(
            store: MemoryStore(PolicyDocument.revision),
          );
          final references = ReferenceLibrary(store: MemoryReferences());
          Uint8List? saved;
          final coach = CameraCoach(
            demo: true,
            previewFrames: const Stream.empty(),
            now: tester.binding.clock.now,
            saver: (bytes, _) async => saved = bytes,
          );
          await tester.runAsync(() async {
            await consent.load();
            await coach.initialize();
            if (mode == ShootingMode.pose) {
              coach.setShootingMode(mode);
              references.selectTemplate(
                'viewer-reference',
                await referencePng(),
              );
            }
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
                references: references,
                permissionBackend: TestPermissions()..photos = true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (mode == ShootingMode.pose) {
            expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
            expect(
              tester
                  .widget<IconButton>(find.byKey(const Key('open-photo')))
                  .onPressed,
              isNull,
            );
          } else {
            expect(find.byKey(const Key('open-photo')), findsNothing);
            expect(find.byIcon(Icons.photo_outlined), findsNothing);
          }
          await tester.runAsync(() => coach.takePhoto(overrideGuidance: true));
          await tester.pumpAndSettle();
          expect(coach.phase, CapturePhase.captured);
          expect(coach.saved, isTrue);
          expect(saved, orderedEquals(coach.photo!));
          final opener = find.byKey(const Key('open-photo'));
          expect(opener.hitTestable(), findsOneWidget);
          final openPhoto = tester.widget<IconButton>(opener).onPressed!;
          await tester.tap(opener);
          // A queued second activation must not stack two viewers.
          openPhoto();
          await tester.pumpAndSettle();
          final viewer = find.byKey(const Key('photo-viewer'));
          expect(find.byType(PhotoViewer), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          expect(tester.getRect(viewer), Offset.zero & size);
          final photo = find.descendant(
            of: viewer,
            matching: find.byType(Image),
          );
          final provider = tester.widget<Image>(photo).image as MemoryImage;
          expect(provider.bytes, same(coach.photo));
          await tester.runAsync(
            () => precacheImage(provider, tester.element(viewer)),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .renderObject<RenderImage>(
                  find.descendant(of: photo, matching: find.byType(RawImage)),
                )
                .image,
            isNotNull,
          );
          await exportReferencePreview(
            tester,
            'photo-fullscreen-${mode.name}-${size.width.toInt()}',
          );
          final zoom = find.byKey(const Key('photo-viewer-zoom'));
          final center = tester.getCenter(zoom);
          final left = await tester.startGesture(center - const Offset(40, 0));
          final right = await tester.startGesture(center + const Offset(40, 0));
          await tester.pump();
          await left.moveBy(const Offset(-50, 0));
          await right.moveBy(const Offset(50, 0));
          await tester.pump();
          final transform = find.descendant(
            of: zoom,
            matching: find.byType(Transform),
          );
          expect(
            tester.widget<Transform>(transform).transform.getMaxScaleOnAxis(),
            greaterThan(1),
          );
          await left.up();
          await right.up();
          await tester.tap(find.byKey(const Key('close-photo')));
          await tester.pumpAndSettle();
          expect(viewer, findsNothing);
          expect(coach.phase, CapturePhase.captured);
          expect(opener.hitTestable(), findsOneWidget);
          await tester.tap(opener);
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(viewer, findsNothing);
          coach.resetFraming();
          await tester.pumpAndSettle();
          expect(coach.photo, isNotNull);
          if (mode == ShootingMode.pose) {
            expect(opener.hitTestable(), findsOneWidget);
            references.setOpacity(.62);
            references.toggleMirror();
            await tester.pumpAndSettle();
            final selected = references.selected;
            final opacity = references.opacity;
            final mirrored = references.mirror;
            await tester.tap(opener);
            await tester.pumpAndSettle();
            expect(viewer, findsOneWidget);
            expect(
              tester.widget<PhotoViewer>(find.byType(PhotoViewer)).bytes,
              same(coach.photo),
            );
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(coach.phase, CapturePhase.framing);
            expect(references.selected, same(selected));
            expect(references.opacity, opacity);
            expect(references.mirror, mirrored);
            references.clearSelection();
            await tester.pumpAndSettle();
            expect(opener, findsNothing);
          } else {
            expect(opener, findsNothing);
          }
          openPhoto();
          await tester.pumpAndSettle();
          expect(viewer, findsNothing);
          await tester.runAsync(() => coach.takePhoto(overrideGuidance: true));
          await tester.pumpAndSettle();
          await tester.tap(opener);
          await tester.pumpAndSettle();
          await consent.withdraw();
          await tester.pumpAndSettle();
          expect(viewer, findsNothing);
          expect(coach.disposed, isTrue);
          expect(coach.photo, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          consent.dispose();
        },
      );
    }
  }
}
