// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// A HealthKit workout session for the Apple Watch, over dart:ffi.
//
// One HKWorkoutSession with its HKLiveWorkoutBuilder, and optionally a
// CLLocationManager feeding an HKWorkoutRouteBuilder, live in this file for
// the life of a workout. Native wakes Dart through one callback that carries a
// kind, never a payload; Dart then pulls what changed back through the
// synchronous reads below. Values cross as JSON strings that native allocates
// and Dart releases with `flutter_watch_workout_release`.
//
// The asynchronous HealthKit calls (authorization, starting collection,
// finishing the workout, recovering a session) each return a request id at
// once. Their result lands later: a FWW_SIGNAL_REQUEST signal says one
// finished, and `flutter_watch_workout_take_request_result` hands it over.

#ifndef FLUTTER_WATCH_WORKOUT_FFI_H
#define FLUTTER_WATCH_WORKOUT_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define FWW_EXPORT __attribute__((visibility("default"))) __attribute__((used))

// What woke Dart up. Mirrored in lib/src/codec.dart.
#define FWW_SIGNAL_STATE 1
#define FWW_SIGNAL_METRICS 2
#define FWW_SIGNAL_LOCATIONS 3
#define FWW_SIGNAL_ERROR 4
#define FWW_SIGNAL_REQUEST 5

// How many route locations native holds for Dart before it drops the oldest.
#define FWW_LOCATION_BUFFER 512

typedef void (*fww_signal_callback)(int64_t kind);

// Registers the callback Dart wants woken, or NULL to stop signalling.
FWW_EXPORT
void flutter_watch_workout_set_callback(fww_signal_callback callback);

// 1 when HealthKit is available on this device, 0 otherwise.
FWW_EXPORT
int flutter_watch_workout_is_available(void);

// What the app's Info.plist lacks for a workout, as a JSON object:
// {"missing": [<key>, ...], "workoutProcessing": <bool>,
// "backgroundLocation": <bool>}. `missing` names the usage descriptions
// HealthKit and CoreLocation terminate an app without; `workoutProcessing`
// says whether WKBackgroundModes has workout-processing, without which the
// app is suspended when the wrist goes down; `backgroundLocation` says
// whether UIBackgroundModes has location, which lets the route's location
// updates continue in the background.
FWW_EXPORT
char* flutter_watch_workout_setup_report(void);

// Asks for the HealthKit types a workout writes and reads and, when `route` is
// nonzero, for when-in-use location access. Result: {"workoutSharing":
// "authorized"|"denied"|"notDetermined", "location": "authorized"|"denied"|
// "notDetermined"|"notRequested"}.
FWW_EXPORT
int64_t flutter_watch_workout_request_authorization(int route);

// Starts a session. `config_json` is {"activity": <HKWorkoutActivityType raw
// value>, "location": <HKWorkoutSessionLocationType raw value>, "route":
// <bool>}. The result is {} once collection began.
FWW_EXPORT
int64_t flutter_watch_workout_start(const char* config_json);

// Pause and resume the running session; no-ops without one.
FWW_EXPORT
void flutter_watch_workout_pause(void);
FWW_EXPORT
void flutter_watch_workout_resume(void);

// Ends the session and saves the workout (and its route, when one was
// recorded). Result: {"uuid": <string>, "duration": <seconds>,
// "activeEnergy": <kcal>, "distance": <m>, "routePoints": <int>,
// "routeSaved": <bool>}.
FWW_EXPORT
int64_t flutter_watch_workout_end(void);

// Ends the session without saving anything. Result: {}.
FWW_EXPORT
int64_t flutter_watch_workout_discard(void);

// Recovers the session the system kept running after the app quit. Result:
// {"recovered": <bool>}.
FWW_EXPORT
int64_t flutter_watch_workout_recover(void);

// The session's HKWorkoutSessionState raw value, or 0 without a session.
FWW_EXPORT
int flutter_watch_workout_state(void);

// The latest metrics as JSON ({"heartRate": <bpm or null>, "activeEnergy":
// <kcal>, "distance": <m>, "elapsed": <seconds>, "timestamp": <ms since
// 1970>}), or NULL before the first sample.
FWW_EXPORT
char* flutter_watch_workout_metrics(void);

// Drains the buffered route locations as a JSON array, or NULL when none are
// buffered. Each element is {"latitude", "longitude", "altitude",
// "horizontalAccuracy", "verticalAccuracy", "speed", "course", "timestamp"}.
FWW_EXPORT
char* flutter_watch_workout_poll_locations(void);

// How many locations were dropped because Dart did not drain them in time.
FWW_EXPORT
int64_t flutter_watch_workout_dropped_location_count(void);

// The result of request `id` as JSON, or NULL while it is still running. A
// failed request is {"error": {"code": <string>, "message": <string>,
// "nativeCode": <int>}}. Each result is handed over once.
FWW_EXPORT
char* flutter_watch_workout_take_request_result(int64_t id);

// The oldest error that arrived outside a request (a session failure), as the
// same {"code", "message", "nativeCode"} object, or NULL when none is queued.
FWW_EXPORT
char* flutter_watch_workout_take_last_error(void);

// Releases a string this file returned.
FWW_EXPORT
void flutter_watch_workout_release(char* string);

#endif  // FLUTTER_WATCH_WORKOUT_FFI_H
