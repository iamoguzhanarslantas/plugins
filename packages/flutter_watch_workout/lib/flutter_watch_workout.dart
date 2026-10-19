// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// HealthKit workout sessions for Flutter apps on the Apple Watch: live heart
/// rate, active energy and distance, a GPS route, and a workout saved to
/// Health, over dart:ffi.
///
/// Start with [WatchWorkout.instance].
library;

export 'src/backend.dart' show WorkoutBackend;
export 'src/types.dart';
export 'src/watch_workout.dart' show WatchWorkout;
