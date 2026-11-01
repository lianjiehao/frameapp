import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:framecoach/core/vision.dart';
import 'package:framecoach/services/coach.dart';

Future<void> waitForCoach(
  CameraCoach coach,
  bool Function() predicate,
  void Function() action,
) async {
  final done = Completer<void>();
  void changed() {
    if (predicate() && !done.isCompleted) done.complete();
  }

  coach.addListener(changed);
  try {
    action();
    changed();
    await done.future;
  } finally {
    coach.removeListener(changed);
  }
}

Future<void> selectAndWait(CameraCoach coach, Point2 point) => waitForCoach(
  coach,
  () => !coach.selectingSubject,
  () => coach.selectSubject(point),
);

Future<void> pumpSelection(WidgetTester tester, CameraCoach coach) async {
  final deadline = Stopwatch()..start();
  while (coach.selectingSubject &&
      deadline.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
  }
  expect(coach.selectingSubject, false, reason: 'Selection worker completed');
  await tester.pump();
}
