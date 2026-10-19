// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// What kind of workout a session records.
///
/// Each value maps to an `HKWorkoutActivityType`, which decides how the
/// watch estimates energy and which distance it accumulates.
enum WorkoutActivity {
  /// `HKWorkoutActivityType.running`.
  running(37),

  /// `HKWorkoutActivityType.walking`.
  walking(52),

  /// `HKWorkoutActivityType.cycling`. Accumulates cycling distance.
  cycling(13),

  /// `HKWorkoutActivityType.hiking`.
  hiking(24),

  /// `HKWorkoutActivityType.other`.
  other(3000);

  const WorkoutActivity(this.healthKitValue);

  /// The `HKWorkoutActivityType` raw value.
  final int healthKitValue;
}

/// Where a workout takes place: `HKWorkoutSessionLocationType`.
enum WorkoutLocationType {
  /// Not known.
  unknown(1),

  /// Indoors, as on a treadmill.
  indoor(2),

  /// Outdoors. Only an outdoor workout records a route by default.
  outdoor(3);

  const WorkoutLocationType(this.healthKitValue);

  /// The `HKWorkoutSessionLocationType` raw value.
  final int healthKitValue;
}

/// The state of the workout session: `HKWorkoutSessionState`, plus [idle].
enum WorkoutSessionState {
  /// No session has started since the app launched.
  idle(0),

  /// Created, not yet started.
  notStarted(1),

  /// Running: metrics accumulate and the route records.
  running(2),

  /// Ended. The workout is being saved, or has been.
  ended(3),

  /// Paused: nothing accumulates until it resumes.
  paused(4),

  /// Prepared, sensors warming up, not yet started.
  prepared(5),

  /// Stopped: collection is over, the session is about to end.
  stopped(6);

  const WorkoutSessionState(this.healthKitValue);

  /// The `HKWorkoutSessionState` raw value, or 0 for [idle].
  final int healthKitValue;

  /// The state for an `HKWorkoutSessionState` raw value; [idle] for 0 and for
  /// any value this package does not know.
  static WorkoutSessionState fromHealthKit(int value) =>
      WorkoutSessionState.values.firstWhere(
        (WorkoutSessionState s) => s.healthKitValue == value,
        orElse: () => WorkoutSessionState.idle,
      );
}

/// How to set up a workout session.
class WorkoutConfiguration {
  /// A session of [activity] at [location]. [recordRoute] defaults to true
  /// outdoors and false indoors.
  const WorkoutConfiguration({
    required this.activity,
    this.location = WorkoutLocationType.outdoor,
    bool? recordRoute,
  }) : _recordRoute = recordRoute;

  /// The kind of workout.
  final WorkoutActivity activity;

  /// Where it takes place.
  final WorkoutLocationType location;

  final bool? _recordRoute;

  /// Whether the session records a GPS route and saves it with the workout.
  bool get recordRoute =>
      _recordRoute ?? location == WorkoutLocationType.outdoor;

  /// The JSON the native side reads.
  Map<String, Object?> toJson() => <String, Object?>{
        'activity': activity.healthKitValue,
        'location': location.healthKitValue,
        'route': recordRoute,
      };
}

/// The running totals of a workout, as the watch last reported them.
class WorkoutMetrics {
  /// Metrics with these values.
  const WorkoutMetrics({
    required this.heartRate,
    required this.activeEnergy,
    required this.distance,
    required this.elapsed,
    required this.timestamp,
  });

  /// The most recent heart rate, in beats per minute, or null before the
  /// first reading.
  final double? heartRate;

  /// Active energy burned so far, in kilocalories.
  final double activeEnergy;

  /// Distance so far, in metres: cycling distance for
  /// [WorkoutActivity.cycling], walking and running distance otherwise.
  final double distance;

  /// Active time at [timestamp], with paused time left out.
  final Duration elapsed;

  /// When the watch reported these values.
  final DateTime timestamp;
}

/// One point of a recorded route.
class WorkoutLocation {
  /// A route point with these values.
  const WorkoutLocation({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.horizontalAccuracy,
    required this.verticalAccuracy,
    required this.speed,
    required this.course,
    required this.timestamp,
  });

  /// Latitude, in degrees.
  final double latitude;

  /// Longitude, in degrees.
  final double longitude;

  /// Altitude above sea level, in metres.
  final double altitude;

  /// Radius of uncertainty of the position, in metres. Points less accurate
  /// than 50 m are not recorded.
  final double horizontalAccuracy;

  /// Uncertainty of [altitude], in metres; negative when it is not valid.
  final double verticalAccuracy;

  /// Speed in metres per second; negative when it is not valid.
  final double speed;

  /// Direction of travel in degrees from true north; negative when it is
  /// not valid.
  final double course;

  /// When the point was measured.
  final DateTime timestamp;
}

/// What a saved workout came to.
class WorkoutSummary {
  /// A summary with these values.
  const WorkoutSummary({
    required this.uuid,
    required this.duration,
    required this.activeEnergy,
    required this.distance,
    required this.routePoints,
    required this.routeSaved,
  });

  /// The saved `HKWorkout`'s UUID.
  final String uuid;

  /// The workout's active duration.
  final Duration duration;

  /// Active energy burned, in kilocalories.
  final double activeEnergy;

  /// Distance, in metres.
  final double distance;

  /// How many route points were recorded.
  final int routePoints;

  /// Whether a route was saved with the workout.
  final bool routeSaved;
}

/// One permission a workout needs.
enum WorkoutPermission {
  /// Granted.
  authorized,

  /// Refused, or restricted on this device.
  denied,

  /// Not decided yet.
  notDetermined,

  /// Not asked for: a route was not requested.
  notRequested,
}

/// What the wearer granted.
///
/// HealthKit tells an app whether it may *write* a type, never whether it
/// may read one, so [workoutSharing] is the only HealthKit answer there is.
class WorkoutAuthorization {
  /// An answer with these values.
  const WorkoutAuthorization({
    required this.workoutSharing,
    required this.location,
  });

  /// Whether the app may save workouts.
  final WorkoutPermission workoutSharing;

  /// Whether the app may read the location, for a route.
  final WorkoutPermission location;
}

/// What the app's `Info.plist` has and lacks for a workout.
class WorkoutSetup {
  /// A report with these values.
  const WorkoutSetup({
    required this.missingUsageDescriptions,
    required this.workoutProcessing,
  });

  /// The usage-description keys the `Info.plist` lacks:
  /// `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` and
  /// `NSLocationWhenInUseUsageDescription`. HealthKit and CoreLocation
  /// terminate an app without them, so this package refuses to start
  /// instead.
  final List<String> missingUsageDescriptions;

  /// Whether `WKBackgroundModes` has `workout-processing`. Without it the
  /// app is suspended when the wrist goes down, even mid-workout.
  final bool workoutProcessing;

  /// Whether nothing is missing.
  bool get isComplete => missingUsageDescriptions.isEmpty && workoutProcessing;
}

/// A failure reported by the workout session.
class WorkoutException implements Exception {
  /// A failure with this [code] and [message].
  const WorkoutException(this.code, this.message, {this.nativeCode = 0});

  /// What failed:
  ///
  /// * `missingUsageDescription`: the `Info.plist` lacks a key named in
  ///   [message].
  /// * `notAvailable`: HealthKit is not available on this device.
  /// * `alreadyRunning`, `noSession`, `alreadyEnding`: the call does not fit
  ///   the session's state.
  /// * `invalidConfiguration`: the configuration did not reach native intact.
  /// * `healthKit`, `session`, `route`, `location`: HealthKit or CoreLocation
  ///   reported an error; [nativeCode] is its code.
  final String code;

  /// The description native gave.
  final String message;

  /// The `NSError` code, or 0 when the failure is this package's own.
  final int nativeCode;

  @override
  String toString() => 'WorkoutException($code, $message'
      '${nativeCode == 0 ? '' : ', nativeCode: $nativeCode'})';
}
