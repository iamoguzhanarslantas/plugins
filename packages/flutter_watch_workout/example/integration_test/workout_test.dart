// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Against the real native library, on a watch Simulator. These cover what the
// host tests cannot: that every symbol resolves and that HealthKit answers
// the calls that need no wearer. Asking for authorization puts a system sheet
// up, which a test cannot answer, so starting a workout is checked by hand.
//
// Run with:
//   flutter-watchos drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/workout_test.dart -d <watch-sim>

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_workout/flutter_watch_workout.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final WatchWorkout workout = WatchWorkout.instance;

  testWidgets('HealthKit is available on the watch', (WidgetTester _) async {
    expect(workout.isAvailable, isTrue);
  });

  testWidgets('the example Info.plist has everything a workout needs',
      (WidgetTester _) async {
    final WorkoutSetup setup = workout.checkSetup();
    expect(setup.missingUsageDescriptions, isEmpty);
    expect(setup.workoutProcessing, isTrue);
  });

  testWidgets('nothing is running before a workout starts',
      (WidgetTester _) async {
    expect(await workout.recover(), isFalse);
    expect(workout.state, WorkoutSessionState.idle);
    expect(workout.latestMetrics, isNull);
    expect(await workout.states.first, WorkoutSessionState.idle);
  });

  testWidgets('ending without a session fails with noSession',
      (WidgetTester _) async {
    await expectLater(
      workout.end(),
      throwsA(isA<WorkoutException>()
          .having((WorkoutException e) => e.code, 'code', 'noSession')),
    );
    await expectLater(
      workout.discard(),
      throwsA(isA<WorkoutException>()
          .having((WorkoutException e) => e.code, 'code', 'noSession')),
    );
  });
}
