import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/main.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/services/camera_zoom.dart';
import 'package:framecoach/services/coach.dart';
import 'package:framecoach/services/privacy.dart';
import 'package:framecoach/ui/camera_zoom_dial.dart';

import 'tracking_test.dart' show expected, treeView;
import 'privacy_test.dart' show MemoryStore, TestPermissions;
import 'widget_test.dart' show loadAppFonts, savePreview;

void main() {
  group('CameraZoomRange', () {
    test('maps logarithmic positions and exposes only supported presets', () {
      const range = CameraZoomRange(min: .6, max: 10);

      expect(range.fromProgress(0), closeTo(.6, .001));
      expect(range.fromProgress(1), closeTo(10, .001));
      expect(range.fromProgress(.5), closeTo(math.sqrt(6), .001));
      expect(range.toProgress(2), closeTo(.428, .002));
      expect(range.quickStops, [.6, 1, 3]);
      expect(range.dialStops, [.6, 1, 2, 3, 6, 10]);
      expect(range.clamp(20), 10);
      expect(range.format(.6), '0.6×');
    });

    test(
      'plans three distinct usable stops for small and large rear ranges',
      () {
        for (final item in [
          (1.0, 10.0, [1.0, 2.0, 4.0]),
          (1.0, 20.0, [1.0, 2.0, 6.0]),
          (1.0, 100.0, [1.0, 4.0, 20.0]),
          (1.0, 3.0, [1.0, 2.0, 3.0]),
          (1.0, 2.0, [1.0, 1.5, 2.0]),
          (1.0, 1.02, [1.0, 1.01, 1.02]),
          (.6, 6.0, [.6, 1.0, 2.0]),
        ]) {
          final range = CameraZoomRange(min: item.$1, max: item.$2);
          expect(range.quickStops, item.$3);
          expect(range.quickStops.map(range.stopLabel).toSet(), hasLength(3));
          expect(range.slotFor(range.quickStops[0]), 0);
          expect(range.slotFor(range.quickStops[1]), 1);
          expect(range.slotFor(range.quickStops[2]), 2);
          expect(range.dialStops.first, item.$1);
          expect(range.dialStops.last, item.$2);
          expect(range.dialStops, containsAll(range.quickStops));
          expect(
            range.dialStops.every((v) => v >= item.$1 && v <= item.$2),
            true,
          );
        }
        expect(const CameraZoomRange(min: 1, max: 10).dialStops, [
          1,
          2,
          4,
          6,
          10,
        ]);
        expect(const CameraZoomRange(min: 1, max: 1).quickStops, [1]);
      },
    );
  });

  group('CameraZoomState', () {
    test(
      'serializes updates and applies only the newest pending value',
      () async {
        final firstApply = Completer<void>();
        final firstStarted = Completer<void>();
        final settled = Completer<bool>();
        final applied = <double>[];
        final zoom = CameraZoomState(onSettled: settled.complete);
        zoom.configure(.6, 10);
        Future<void> apply(double value) async {
          applied.add(value);
          if (applied.length == 1) {
            firstStarted.complete();
            await firstApply.future;
          }
        }

        zoom.request(2, apply);
        await firstStarted.future;
        zoom.request(5, apply);
        zoom.request(8, apply);
        firstApply.complete();

        expect(await settled.future, true);
        expect(applied, [2, 8]);
        expect(zoom.value, 8);
        expect(zoom.busy, false);
      },
    );

    test(
      'reverts the display value when the device rejects a zoom request',
      () async {
        final settled = Completer<bool>();
        final zoom = CameraZoomState(onSettled: settled.complete);
        zoom.configure(.6, 10);
        zoom.request(5, (_) async => throw StateError('unsupported'));

        expect(await settled.future, false);
        expect(zoom.value, 1);
        expect(zoom.lastRequestFailed, true);
        expect(zoom.busy, false);
      },
    );

    for (final firstFails in [false, true]) {
      test(
        'a delayed ${firstFails ? 'failure' : 'success'} cannot replace the final zoom after release',
        () async {
          final first = Completer<void>();
          final last = Completer<void>();
          final lastStarted = Completer<void>();
          final settled = Completer<bool>();
          final applied = <double>[];
          final displayed = <double>[];
          late final CameraZoomState zoom;
          zoom = CameraZoomState(
            onChanged: () => displayed.add(zoom.value),
            onSettled: settled.complete,
          );
          addTearDown(zoom.dispose);
          zoom.configure(1, 10);
          Future<void> apply(double value) {
            applied.add(value);
            if (applied.length == 1) return first.future;
            lastStarted.complete();
            return last.future;
          }

          zoom.beginGesture();
          zoom.request(2, apply);
          zoom.request(3.4, apply);
          displayed.clear();
          zoom.endGesture();
          if (firstFails) {
            first.completeError(StateError('superseded request failed'));
          } else {
            first.complete();
          }
          await lastStarted.future;
          expect(zoom.value, 3.4);
          expect(zoom.isAdjusting, true);
          last.complete();
          expect(await settled.future, true);
          expect(applied, [2, 3.4]);
          expect(displayed, isNotEmpty);
          expect(displayed, everyElement(3.4));
          expect(zoom.value, 3.4);
          expect(zoom.isAdjusting, false);
        },
      );
    }

    test('reset invalidates an in-flight camera request', () async {
      final started = Completer<void>();
      final apply = Completer<void>();
      var settled = false;
      final zoom = CameraZoomState(onSettled: (_) => settled = true);
      zoom.configure(.6, 10);
      zoom.request(8, (_) {
        started.complete();
        return apply.future;
      });
      await started.future;

      zoom.reset();
      apply.complete();
      await Future<void>.value();

      expect(zoom.value, 1);
      expect(zoom.busy, false);
      expect(settled, false);
    });

    test('defers one settle notification until a swipe ends', () async {
      final settled = <bool>[];
      final zoom = CameraZoomState(onSettled: settled.add);
      zoom.configure(.6, 10);
      zoom.beginGesture();
      zoom.request(2, (_) async {});
      await Future<void>.delayed(Duration.zero);
      zoom.request(5, (_) async {});
      await Future<void>.delayed(Duration.zero);

      expect(settled, isEmpty);
      expect(zoom.busy, false);
      expect(zoom.isAdjusting, true);
      zoom.endGesture();
      expect(zoom.isAdjusting, false);
      expect(settled, [true]);
      expect(zoom.value, 5);
    });
  });

  group('zoom gestures', () {
    const range = CameraZoomRange(min: 1, max: 10);
    late double value;
    late int starts, ends, selections;
    late List<double> changes;

    Future<void> showPreview(
      WidgetTester tester, {
      double initial = 1,
      CameraZoomRange cameraRange = range,
      bool echoChanges = true,
      Widget? bottomTrailing,
    }) async {
      value = initial;
      starts = ends = selections = 0;
      changes = [];
      if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
        await tester.runAsync(loadAppFonts);
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'FrameSans'),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: const Key('app-preview'),
                child: SizedBox(
                  key: const Key('zoom-preview'),
                  width: 340,
                  height: 480,
                  child: StatefulBuilder(
                    builder: (context, setState) => Stack(
                      fit: StackFit.expand,
                      children: [
                        if (const bool.fromEnvironment('EXPORT_PREVIEW'))
                          Image.asset(
                            'assets/images/park.jpg',
                            fit: BoxFit.cover,
                          )
                        else
                          const ColoredBox(color: Color(0xFF20261F)),
                        CameraZoomDial(
                          range: cameraRange,
                          value: value,
                          onChanged: (next) {
                            changes.add(next);
                            value = next;
                            if (echoChanges) setState(() {});
                          },
                          onPreviewTap: (_) => selections++,
                          onGestureStart: () => starts++,
                          onGestureEnd: () => ends++,
                          bottomTrailing: bottomTrailing,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/park.jpg'),
            tester.element(find.byKey(const Key('zoom-preview'))),
          ),
        );
        await tester.pump();
      }
    }

    Finder getArc() => find.byKey(const Key('camera-zoom-arc'));
    Offset barCenter(WidgetTester tester) =>
        tester.getCenter(find.byKey(const Key('camera-zoom-bar')));
    Offset previewCenter(WidgetTester tester) =>
        tester.getCenter(find.byKey(const Key('zoom-preview')));

    testWidgets(
      'the angle fades out of the arc and never intercepts preview taps',
      (tester) async {
        const angleKey = Key('test-preview-angle');
        await showPreview(
          tester,
          initial: 10,
          bottomTrailing: const Text(
            '俯拍 38.4°',
            key: angleKey,
            style: TextStyle(fontSize: 10, color: Color(0xBFF2F0E7)),
          ),
        );
        final angle = find.byKey(angleKey);
        final preview = tester.getRect(find.byKey(const Key('zoom-preview')));
        expect(tester.getRect(angle).right, closeTo(preview.right - 13, .5));
        double opacity() => tester
            .widget<Opacity>(
              find.ancestor(of: angle, matching: find.byType(Opacity)),
            )
            .opacity;
        expect(opacity(), 1);
        await tester.tapAt(tester.getCenter(angle));
        expect(selections, 1);
        final finger = await tester.startGesture(barCenter(tester));
        await finger.moveBy(const Offset(-40, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(opacity(), greaterThan(0));
        expect(opacity(), lessThan(1));
        await tester.pump(const Duration(milliseconds: 90));
        expect(opacity(), 0);
        expect(getArc(), findsOneWidget);
        if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
          await savePreview(tester, '/tmp/frame-guidance-zoom-arc.png');
        }
        await finger.up();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 160));
        expect(opacity(), 1);
        await tester.tapAt(tester.getCenter(angle));
        expect(selections, 2);
      },
    );

    testWidgets(
      'only swiping the bar opens the arc; presets remain tap targets',
      (tester) async {
        await showPreview(tester);
        await tester.dragFrom(previewCenter(tester), const Offset(-64, 0));
        await tester.pump();
        expect(getArc(), findsNothing);
        expect(value, 1);
        expect(starts, 0);
        await tester.tap(find.byKey(const Key('zoom-quick-2.0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(value, 2);
        expect(getArc(), findsNothing);
        expect(find.byType(IconButton), findsNothing);
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.byKey(const Key('zoom-active-slot-1'))).dx,
          closeTo(
            tester.getCenter(find.byKey(const Key('zoom-quick-2.0'))).dx,
            .01,
          ),
        );
        if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
          await savePreview(tester, '/tmp/frameapp-zoom-bar.png');
        }
        await tester.dragFrom(barCenter(tester), const Offset(-64, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(getArc(), findsOneWidget);
        expect(value, greaterThan(2));
        expect(starts, 2);
        expect(ends, 2);
        expect(selections, 0);
        expect(
          tester.getSize(find.byKey(const Key('zoom-preview'))),
          const Size(340, 480),
        );
        if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
          await savePreview(tester, '/tmp/frameapp-zoom-arc.png');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'preset taps immediately request only the exact target without counting through values',
      (tester) async {
        await showPreview(tester, initial: 3.4);
        for (final target in [1.0, 2.0, 4.0, 1.0]) {
          changes.clear();
          await tester.tap(
            find.byKey(Key('zoom-quick-${target.toStringAsFixed(1)}')),
          );
          await tester.pump();
          expect(value, target);
          expect(changes, [target]);
          expect(
            tester
                .widget<Text>(find.byKey(const Key('camera-zoom-bar-value')))
                .data,
            range.format(target),
          );
          await tester.pumpAndSettle();
          expect(changes, [target]);
          expect(getArc(), findsNothing);
        }
        expect(starts, 4);
        expect(ends, 4);
      },
    );

    testWidgets(
      'tapping a nearby preset still reaches the exact slot boundary',
      (tester) async {
        for (final item in [(1.0002, 1.0), (1.9998, 2.0)]) {
          await showPreview(tester, initial: item.$1);
          await tester.tap(
            find.byKey(Key('zoom-quick-${item.$2.toStringAsFixed(1)}')),
          );
          await tester.pumpAndSettle();
          expect(value, item.$2);
          expect(changes, [item.$2]);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'selected capsule shares the bar edge and corner radius at both ends',
      (tester) async {
        for (final item in [(1.0, 0), (4.4, 2)]) {
          await showPreview(tester, initial: item.$1);
          final bar = find.byKey(const Key('camera-zoom-bar'));
          final selected = find.byKey(Key('zoom-active-slot-${item.$2}'));
          final barRect = tester.getRect(bar);
          final selectedRect = tester.getRect(selected);
          expect(selectedRect.top, closeTo(barRect.top, .01));
          expect(selectedRect.bottom, closeTo(barRect.bottom, .01));
          expect(
            item.$2 == 0 ? selectedRect.left : selectedRect.right,
            closeTo(item.$2 == 0 ? barRect.left : barRect.right, .01),
          );
          final decoration =
              tester.widget<Container>(selected).decoration! as BoxDecoration;
          expect(
            decoration.borderRadius,
            BorderRadius.circular(barRect.height / 2),
          );
          if (item.$2 == 2 && const bool.fromEnvironment('EXPORT_PREVIEW')) {
            await savePreview(tester, '/tmp/frameapp-zoom-bar-4_4.png');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'opens at the current zoom, follows left drags immediately and reverses at the limit',
      (tester) async {
        await showPreview(tester, initial: 3.6, echoChanges: false);
        final finger = await tester.startGesture(barCenter(tester));
        await finger.moveBy(const Offset(-30, 0));
        await tester.pump();
        expect(value, 3.6);
        expect(
          tester.widget<Text>(find.byKey(const Key('camera-zoom-value'))).data,
          '3.6×',
        );
        await finger.moveBy(const Offset(-15, 0));
        await tester.pump();
        expect(value, greaterThan(3.6));
        expect(
          tester.widget<Text>(find.byKey(const Key('camera-zoom-value'))).data,
          range.format(value),
        );
        await finger.moveBy(const Offset(-2000, 0));
        await tester.pump();
        expect(value, range.max);
        await finger.moveBy(const Offset(5, 0));
        await tester.pump();
        expect(value, lessThan(range.max));
        await finger.up();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'wheel sensitivity is independent of the available zoom range',
      (tester) async {
        Future<double> move(CameraZoomRange limits) async {
          await showPreview(tester, initial: 2, cameraRange: limits);
          final finger = await tester.startGesture(barCenter(tester));
          await finger.moveBy(const Offset(-30, 0));
          await finger.moveBy(const Offset(-25, 0));
          await tester.pump();
          final result = value;
          await finger.up();
          await tester.pumpWidget(const SizedBox.shrink());
          return result;
        }

        final shortRange = await move(range);
        final longRange = await move(const CameraZoomRange(min: .6, max: 100));
        expect(shortRange, greaterThan(2));
        expect(longRange, closeTo(shortRange, .0001));
      },
    );

    testWidgets('the active value stays in the exact 1 / 2 / 4 interval slot', (
      tester,
    ) async {
      for (final item in [
        (1.0, 0),
        (1.999, 0),
        (2.0, 1),
        (3.999, 1),
        (4.0, 2),
        (6.0, 2),
      ]) {
        await showPreview(tester, initial: item.$1);
        await tester.pump(const Duration(milliseconds: 220));
        expect(find.byKey(Key('zoom-active-slot-${item.$2}')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('camera-zoom-bar')),
            matching: find.byType(Text),
          ),
          findsNWidgets(3),
        );
      }
    });

    testWidgets('unsupported 0.6 is replaced by usable 1 / 2 / 4 presets', (
      tester,
    ) async {
      await showPreview(
        tester,
        cameraRange: const CameraZoomRange(min: 1, max: 10),
      );
      expect(find.byKey(const Key('zoom-quick-0.6')), findsNothing);
      expect(find.byKey(const Key('zoom-quick-1.0')), findsOneWidget);
      expect(find.byKey(const Key('zoom-quick-2.0')), findsOneWidget);
      expect(find.byKey(const Key('zoom-quick-4.0')), findsOneWidget);
      expect(value, 1);
      expect(selections, 0);
      expect(starts, 0);
    });

    testWidgets(
      'holds the arc while pressed and dismisses one second after release',
      (tester) async {
        await showPreview(tester);
        final finger = await tester.startGesture(barCenter(tester));
        await finger.moveBy(const Offset(-60, 0));
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump(const Duration(seconds: 4));
        expect(getArc(), findsOneWidget);
        expect(ends, 0);
        await finger.up();
        await tester.pump(const Duration(milliseconds: 999));
        expect(getArc(), findsOneWidget);
        expect(ends, 1);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 160));
        expect(getArc(), findsNothing);
      },
    );

    testWidgets('a tap dismisses immediately and does not select a subject', (
      tester,
    ) async {
      await showPreview(tester);
      await tester.dragFrom(barCenter(tester), const Offset(-50, 0));
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(previewCenter(tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(getArc(), findsNothing);
      expect(selections, 0);
      await tester.tapAt(previewCenter(tester));
      await tester.pump();
      expect(selections, 1);

      await tester.dragFrom(barCenter(tester), const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 220));
      expect(getArc(), findsOneWidget);
      // A touch elsewhere on the screen also closes the wheel.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(getArc(), findsNothing);
    });

    testWidgets(
      're-grabbing cancels the old deadline and does not jump the value',
      (tester) async {
        await showPreview(tester);
        await tester.dragFrom(barCenter(tester), const Offset(-50, 0));
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump(const Duration(milliseconds: 500));
        final before = value;
        final arc = tester.getRect(getArc());
        final finger = await tester.startGesture(arc.center);
        await tester.pump(const Duration(seconds: 3));
        expect(getArc(), findsOneWidget);
        expect(value, before);
        await finger.moveBy(const Offset(30, 0));
        await finger.moveBy(const Offset(12, 0));
        await tester.pump();
        expect(value, lessThan(before));
        await finger.cancel();
        await tester.pump(const Duration(milliseconds: 999));
        expect(getArc(), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(milliseconds: 160));
        expect(getArc(), findsNothing);
        expect(starts, ends);
      },
    );

    testWidgets(
      'pinching displays one centered value and clamps to device limits',
      (tester) async {
        await showPreview(tester);
        final center = previewCenter(tester);
        final bar = find.byKey(const Key('camera-zoom-bar'));
        final originalBarCenter = tester.getCenter(bar);
        final originalBarWidth = tester.getSize(bar).width;
        final left = await tester.startGesture(
          center - const Offset(40, 0),
          pointer: 1,
        );
        final right = await tester.startGesture(
          center + const Offset(40, 0),
          pointer: 2,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        final collapsingWidth = tester.getSize(bar).width;
        expect(collapsingWidth, lessThan(originalBarWidth));
        expect(collapsingWidth, greaterThan(42));
        await tester.pump(const Duration(milliseconds: 110));
        expect(
          find.descendant(of: bar, matching: find.byType(Text)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.byType(TextButton)),
          findsNothing,
        );
        expect(tester.getCenter(bar), originalBarCenter);
        expect(tester.getSize(bar).width, lessThan(originalBarWidth));
        await left.moveTo(center - const Offset(60, 0));
        await right.moveTo(center + const Offset(60, 0));
        await tester.pump();
        await left.moveTo(center - const Offset(100, 0));
        await right.moveTo(center + const Offset(100, 0));
        await tester.pump();
        expect(value, greaterThan(1));
        expect(getArc(), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('camera-zoom-bar-value')))
              .data,
          range.format(value),
        );
        expect(
          find.descendant(of: bar, matching: find.byType(Text)),
          findsOneWidget,
        );
        if (const bool.fromEnvironment('EXPORT_PREVIEW')) {
          await savePreview(tester, '/tmp/frameapp-zoom-pinch.png');
        }
        await left.moveTo(center - const Offset(1000, 0));
        await right.moveTo(center + const Offset(1000, 0));
        await tester.pump();
        expect(value, range.max);
        await left.moveTo(center - const Offset(1, 0));
        await right.moveTo(center + const Offset(1, 0));
        await tester.pump();
        expect(value, range.min);
        await right.up();
        await tester.pump();
        expect(
          find.descendant(of: bar, matching: find.byType(Text)),
          findsOneWidget,
        );
        await left.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        final expandingWidth = tester.getSize(bar).width;
        expect(expandingWidth, greaterThan(42));
        expect(expandingWidth, lessThan(originalBarWidth));
        await tester.pump(const Duration(milliseconds: 110));
        expect(getArc(), findsNothing);
        expect(starts, 1);
        expect(ends, 1);
        expect(selections, 0);
        expect(find.byKey(const Key('zoom-quick-1.0')), findsOneWidget);
        expect(tester.getSize(bar).width, originalBarWidth);
      },
    );

    testWidgets(
      'adding a second finger closes the arc without reopening on finger-up',
      (tester) async {
        await showPreview(tester);
        final start = barCenter(tester);
        final left = await tester.startGesture(start, pointer: 1);
        await left.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 220));
        expect(getArc(), findsOneWidget);
        final beforePinch = value;
        final right = await tester.startGesture(
          start - const Offset(80, 80),
          pointer: 2,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 220));
        expect(getArc(), findsNothing);
        expect(value, beforePinch);
        await right.moveBy(const Offset(-20, -20));
        await tester.pump();
        await right.moveBy(const Offset(-30, -30));
        await tester.pump();
        expect(value, greaterThan(beforePinch));
        await right.up();
        final afterPinch = value;
        await left.moveBy(const Offset(40, 0));
        await tester.pump();
        expect(getArc(), findsNothing);
        expect(value, afterPinch);
        await left.up();
        expect(starts, 1);
        expect(ends, 1);
      },
    );
  });

  testWidgets(
    'front camera hides all zoom controls and rejects zoom gestures, then rear recomputes stops',
    (tester) async {
      final coach = _LensPreviewCoach();
      final consent = PrivacyConsent(
        store: MemoryStore(PolicyDocument.revision),
      );
      await tester.pumpWidget(
        FrameApp(
          coach: coach,
          consent: consent,
          permissionBackend: TestPermissions()..camera = true,
        ),
      );
      await tester.pumpAndSettle();
      expect(coach.canZoom, true);
      expect(find.byKey(const Key('zoom-quick-4.0')), findsOneWidget);
      final bar = find.byKey(const Key('camera-zoom-bar'));
      await tester.dragFrom(tester.getCenter(bar), const Offset(-60, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('camera-zoom-arc')), findsOneWidget);

      await coach.showLens(CameraLensDirection.front);
      await tester.pumpAndSettle();
      expect(coach.canZoom, false);
      expect(find.byType(CameraZoomDial), findsNothing);
      expect(bar, findsNothing);
      expect(find.byKey(const Key('camera-zoom-arc')), findsNothing);
      coach.beginZoomGesture();
      coach.requestZoom(4);
      final center = tester.getCenter(find.byKey(const Key('viewfinder')));
      final left = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await left.moveBy(const Offset(-60, 0));
      await right.moveBy(const Offset(60, 0));
      await left.up();
      await right.up();
      await tester.pump(const Duration(seconds: 2));
      expect(coach.zoom.value, 1);
      expect(coach.zoom.isAdjusting, false);
      expect(tester.takeException(), isNull);

      await coach.showLens(CameraLensDirection.back, maxZoom: 20);
      await tester.pumpAndSettle();
      expect(coach.canZoom, true);
      expect(find.byKey(const Key('zoom-quick-6.0')), findsOneWidget);
      expect(find.byKey(const Key('zoom-quick-4.0')), findsNothing);
      expect(find.byKey(const Key('camera-zoom-arc')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'releasing a small zoom change cannot roll the visible number back',
    (tester) async {
      final zoom = CameraZoomState();
      addTearDown(zoom.dispose);
      const initial = 3.4498;
      const target = 3.4502;
      zoom.configure(1, 10, initial: initial);
      final applied = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 340,
              height: 480,
              child: ListenableBuilder(
                listenable: zoom,
                builder: (context, _) => CameraZoomDial(
                  range: zoom.range,
                  value: zoom.value,
                  onChanged: (next) => zoom.request(next, (value) async {
                    applied.add(value);
                  }),
                  onGestureStart: zoom.beginGesture,
                  onGestureEnd: zoom.endGesture,
                ),
              ),
            ),
          ),
        ),
      );
      final bar = find.byKey(const Key('camera-zoom-bar'));
      final finger = await tester.startGesture(tester.getCenter(bar));
      await finger.moveBy(const Offset(-30, 0));
      // A final subpixel movement crosses a visible tenth without exceeding
      // the old service-layer epsilon. The camera must receive it too.
      await finger.moveBy(
        Offset(-math.log(target / initial) * 340 * .56 * .58, 0),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('camera-zoom-value'))).data,
        '3.5×',
      );
      await finger.up();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('camera-zoom-bar-value')))
            .data,
        '3.5×',
      );
      expect(zoom.value, closeTo(target, .000001));
      expect(applied.single, closeTo(target, .000001));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'settled zoom invalidates old guidance and waits for the same subject',
    () async {
      final frames = StreamController<GrayFrame>(sync: true);
      final coach = CameraCoach(demo: true, previewFrames: frames.stream);
      addTearDown(coach.dispose);
      Future<void> feed() async {
        final analyzed = Completer<void>();
        void changed() {
          if (!analyzed.isCompleted) analyzed.complete();
        }

        coach.addListener(changed);
        frames.add(treeView());
        await analyzed.future;
        coach.removeListener(changed);
      }

      await coach.initialize();
      await feed();
      coach.selectSubject(expected());
      await coach.confirmScene();
      expect(coach.phase, CapturePhase.recommending);
      expect(coach.subjectLock.selected, true);

      coach.zoom.configure(.6, 10);
      final settled = Completer<void>();
      void zoomChanged() {
        if (!coach.zoom.isAdjusting && !settled.isCompleted) settled.complete();
      }

      coach.addListener(zoomChanged);
      final applied = Completer<void>();
      final revision = coach.subjectLock.revision;
      coach.zoom.beginGesture();
      coach.zoom.request(2, (_) => applied.future);
      expect(coach.subjectLock.state, SubjectState.lost);
      expect(coach.features.subject, isNull);
      coach.selectSubject(const Point2(.1, .1));
      expect(coach.subjectLock.revision, revision);
      coach.zoom.endGesture();
      applied.complete();
      await settled.future;
      coach.removeListener(zoomChanged);

      expect(coach.phase, CapturePhase.framing);
      expect(coach.plan, isNull);
      expect(coach.plans, isEmpty);
      expect(coach.subjectLock.state, SubjectState.lost);
      expect(coach.subjectLock.selected, true);
      expect(coach.features.subject, isNull);
      expect(coach.canRecommend, false);

      final recovered = Completer<void>();
      void trackingChanged() {
        if (coach.canRecommend && !recovered.isCompleted) recovered.complete();
      }

      coach.addListener(trackingChanged);
      frames.add(treeView(zoom: 2));
      await recovered.future;
      coach.removeListener(trackingChanged);
      expect(coach.subjectLock.state, SubjectState.tracking);
      expect(coach.canRecommend, true);
      expect(
        coach.subjectLock.position!.distanceTo(expected(zoom: 2)) * 256,
        lessThan(2),
      );
      expect(coach.subjectLock.tracking!.zoom, 2);
      await frames.close();
    },
  );
}

// CameraPage exercises its real lens gate without opening native camera I/O.
class _LensPreviewCoach extends CameraCoach {
  _LensPreviewCoach() : super(demo: false);

  @override
  Future<void> initialize() => showLens(CameraLensDirection.back);

  Future<void> showLens(CameraLensDirection lens, {double maxZoom = 10}) async {
    final previous = camera;
    camera = CameraController(
      CameraDescription(
        name: lens.name,
        lensDirection: lens,
        sensorOrientation: 90,
      ),
      ResolutionPreset.low,
      enableAudio: false,
    );
    initialized = true;
    // Even a stale adjustable range must not enable the front camera UI/API.
    zoom.configure(1, maxZoom);
    notifyListeners();
    await previous?.dispose();
  }
}
