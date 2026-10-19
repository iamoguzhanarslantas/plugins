// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The native half of a [WatchWorkout], behind an interface so host tests can
/// substitute a fake without a native binary present.
///
/// Every member is synchronous and maps to one exported C function. The
/// asynchronous HealthKit calls return a request id; the result is read back
/// with [takeRequestResult] once a request signal arrives. Values cross as
/// the JSON strings the native header documents.
///
/// App code does not use this directly; it uses [WatchWorkout].
library;

import 'watch_workout.dart';

/// See the library documentation.
abstract class WorkoutBackend {
  /// Whether HealthKit is available on this device.
  bool isAvailable();

  /// What the `Info.plist` lacks for a workout, as JSON.
  String setupReport();

  /// Asks for HealthKit access, and location access when [route] is true.
  int requestAuthorization({required bool route});

  /// Starts a session from [configurationJson].
  int start(String configurationJson);

  /// Pauses the running session.
  void pause();

  /// Resumes the paused session.
  void resume();

  /// Ends the session and saves the workout.
  int end();

  /// Ends the session without saving.
  int discard();

  /// Recovers a session the system kept running.
  int recover();

  /// The `HKWorkoutSessionState` raw value, or 0 before any session.
  int state();

  /// The latest metrics as JSON, or null before the first sample.
  String? metrics();

  /// The buffered route locations as a JSON array, or null when none are.
  String? pollLocations();

  /// How many locations native dropped because nobody drained them.
  int droppedLocationCount();

  /// The result of request [id] as JSON, or null while it is running.
  String? takeRequestResult(int id);

  /// The oldest queued session error as JSON, or null.
  String? takeLastError();

  /// The function native wakes with a signal kind, or null to stop.
  void setSignalHandler(void Function(int kind)? handler);
}
