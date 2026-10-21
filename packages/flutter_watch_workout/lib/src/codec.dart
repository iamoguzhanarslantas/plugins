// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The JSON native hands over, turned into this package's types. Kept apart
// from the FFI so host tests can feed it the same strings native produces.

import 'dart:convert';

import 'types.dart';

/// What woke Dart up. Mirrored in `watchos/Classes/flutter_watch_workout_ffi.h`.
abstract final class WorkoutSignal {
  /// The session state changed.
  static const int state = 1;

  /// New metrics.
  static const int metrics = 2;

  /// Route locations are buffered.
  static const int locations = 3;

  /// A session error is queued.
  static const int error = 4;

  /// A request finished.
  static const int request = 5;
}

/// A JSON object string as a map.
Map<String, Object?> decodeObject(String json) =>
    (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>();

double _double(Object? value) => (value as num?)?.toDouble() ?? 0;

DateTime _time(Object? millis) =>
    DateTime.fromMillisecondsSinceEpoch((millis as num? ?? 0).toInt());

Duration _seconds(Object? seconds) =>
    Duration(microseconds: (_double(seconds) * 1000000).round());

/// A native `{code, message, nativeCode}` error object.
WorkoutException decodeError(Map<String, Object?> error) => WorkoutException(
      error['code'] as String? ?? 'unknown',
      error['message'] as String? ?? '',
      nativeCode: (error['nativeCode'] as num?)?.toInt() ?? 0,
    );

/// The `setup_report` JSON.
WorkoutSetup decodeSetup(String json) {
  final Map<String, Object?> o = decodeObject(json);
  return WorkoutSetup(
    missingUsageDescriptions:
        (o['missing'] as List<Object?>? ?? const <Object?>[])
            .cast<String>()
            .toList(growable: false),
    workoutProcessing: o['workoutProcessing'] == true,
    backgroundLocation: o['backgroundLocation'] == true,
  );
}

WorkoutPermission _permission(Object? value) => switch (value) {
      'authorized' => WorkoutPermission.authorized,
      'denied' => WorkoutPermission.denied,
      'notRequested' => WorkoutPermission.notRequested,
      _ => WorkoutPermission.notDetermined,
    };

/// A `request_authorization` result.
WorkoutAuthorization decodeAuthorization(Map<String, Object?> o) =>
    WorkoutAuthorization(
      workoutSharing: _permission(o['workoutSharing']),
      location: _permission(o['location']),
    );

/// The `metrics` JSON.
WorkoutMetrics decodeMetrics(String json) {
  final Map<String, Object?> o = decodeObject(json);
  return WorkoutMetrics(
    heartRate: (o['heartRate'] as num?)?.toDouble(),
    activeEnergy: _double(o['activeEnergy']),
    distance: _double(o['distance']),
    elapsed: _seconds(o['elapsed']),
    timestamp: _time(o['timestamp']),
  );
}

/// The `poll_locations` JSON array.
List<WorkoutLocation> decodeLocations(String json) => <WorkoutLocation>[
      for (final Object? item in jsonDecode(json) as List<Object?>)
        if (item is Map<Object?, Object?>)
          WorkoutLocation(
            latitude: _double(item['latitude']),
            longitude: _double(item['longitude']),
            altitude: _double(item['altitude']),
            horizontalAccuracy: _double(item['horizontalAccuracy']),
            verticalAccuracy: _double(item['verticalAccuracy']),
            speed: _double(item['speed']),
            course: _double(item['course']),
            timestamp: _time(item['timestamp']),
          ),
    ];

/// An `end` result.
WorkoutSummary decodeSummary(Map<String, Object?> o) => WorkoutSummary(
      uuid: o['uuid'] as String? ?? '',
      duration: _seconds(o['duration']),
      activeEnergy: _double(o['activeEnergy']),
      distance: _double(o['distance']),
      routePoints: (o['routePoints'] as num?)?.toInt() ?? 0,
      routeSaved: o['routeSaved'] == true,
    );
