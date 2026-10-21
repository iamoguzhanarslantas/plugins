# flutter_watch_workout

HealthKit workout sessions for Flutter apps on Apple Watch: start, pause,
resume and end a workout, read heart rate, active energy and distance while
it runs, record a GPS route, and save the workout (with its route) to
Health. Over dart:ffi, for apps built with
[flutter-watchos](https://github.com/flutterwatch/flutter-watchos).

This is a first-party package, not a port: no upstream Flutter plugin runs an
`HKWorkoutSession`. [`health`](https://pub.dev/packages/health) reads and
writes samples but starts no session, and
[`workout`](https://pub.dev/packages/workout) targets Wear OS and Tizen.
Neither has a federated platform interface a watchOS package could implement.

## Installation

```yaml
dependencies:
  flutter_watch_workout: ^0.0.1
```

## Setup

A workout app needs four things that `flutter-watchos create` does not add.
In `watchos/Runner/Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Shows your heart rate, energy and distance during a workout.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Saves your workouts and their routes to Health.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Records the route of an outdoor workout.</string>
<key>WKBackgroundModes</key>
<array>
	<string>workout-processing</string>
</array>
```

And the HealthKit entitlement: a `watchos/Runner/Runner.entitlements` with
`com.apple.developer.healthkit` set to true, named by
`CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` in the Runner
target's build settings. The [example](example) has all four, and the background location mode below.

`checkSetup()` reports what is missing. HealthKit and CoreLocation terminate
an app that asks for access without the usage descriptions, so this package
checks for them first and fails the call with a `WorkoutException` instead.
Without `workout-processing` the app is suspended when the wrist goes down,
even mid-workout. Without the entitlement, authorization fails with a
`healthKit` error.

For a route recorded with the wrist down, also add `location` to
`UIBackgroundModes`; the route's `CLLocationManager` then turns on
`allowsBackgroundLocationUpdates`, which `checkSetup().backgroundLocation`
reports. It has to be `UIBackgroundModes`: CoreLocation ignores `location`
under `WKBackgroundModes`, and asserts if the flag turns on without the
right key, so this package checks first.

```xml
<key>UIBackgroundModes</key>
<array>
	<string>location</string>
</array>
```

## Usage

```dart
final WatchWorkout workout = WatchWorkout.instance;

// At launch: watchOS relaunches an app whose workout was running.
await workout.recover();

final WorkoutAuthorization auth = await workout.requestAuthorization();
if (auth.workoutSharing == WorkoutPermission.authorized) {
  await workout.start(const WorkoutConfiguration(
    activity: WorkoutActivity.running,
    location: WorkoutLocationType.outdoor,
  ));
}

workout.metrics.listen((WorkoutMetrics m) {
  print('${m.heartRate} bpm, ${m.distance} m, ${m.activeEnergy} kcal');
});
workout.locations.listen((WorkoutLocation p) {
  print('${p.latitude}, ${p.longitude} at ${p.speed} m/s');
});

workout.pause();
workout.resume();

final WorkoutSummary summary = await workout.end();
print('Saved ${summary.uuid}: ${summary.routePoints} route points');
```

## What it does

| Member | What it does |
|---|---|
| `requestAuthorization({route})` | Asks for the workout, route, energy, distance and heart-rate types, then for when-in-use location when `route` is true |
| `start(configuration)` | Creates an `HKWorkoutSession` with its `HKLiveWorkoutBuilder`; with `recordRoute`, a `CLLocationManager` feeds an `HKWorkoutRouteBuilder` |
| `pause()` / `resume()` | Pauses and resumes the session; `states` reports each change |
| `end()` | Ends collection, saves the `HKWorkout`, then its route; returns a `WorkoutSummary` |
| `discard()` | Ends the session and saves nothing |
| `recover()` | `recoverActiveWorkoutSession`: picks up a session the system kept running |
| `states` | The `HKWorkoutSessionState`, starting with the current one |
| `metrics` | Heart rate (bpm), active energy (kcal), distance (m: cycling distance for cycling, walking and running otherwise) and active elapsed time, each time the builder collects |
| `locations` | Route points as they are recorded. Points worse than 50 m are left out, as in Apple's workout sample |
| `errors` | Failures outside a call: the session failing, a route point not saved, a location error |

Elapsed time leaves out paused time. Between samples it is
`metrics.elapsed + (now - metrics.timestamp)` while running, which is what
the example shows.

## Limits worth knowing

- One session at a time, as HealthKit allows. `start` fails with
  `alreadyRunning` while one runs.
- A recovered session records a new route from the moment it is recovered;
  points recorded before the app quit are not recovered.
- Native keeps the latest 512 route points for Dart; `droppedLocationCount`
  says how many were dropped while nothing listened to `locations`.
- Swimming and other activities that need extra configuration are not
  offered yet.
- HealthKit only says whether an app may *write* a type, so
  `WorkoutAuthorization.workoutSharing` is the only HealthKit answer; a read
  refusal shows up as metrics that never arrive.

## Status

| Aspect | Result |
|---|---|
| Host unit tests (`flutter test`) | ✅ pass (native backend faked) |
| Integration test (`example/integration_test`) | ✅ passes on the watchOS 27.0 Simulator |
| Example on the Simulator | ✅ authorization sheets, a running session with simulated heart rate and a simulated route, pause, resume, end with the route saved, and discard; the route kept recording with the app sent to the background; after the app was killed mid-workout, `recover()` picked the session up on relaunch and it ended and saved |
| Physical watch | not yet checked: the wrist going down (the Simulator has no wrist), real GPS and heart rate, and whether Dart itself keeps running in the background rather than catching up on return need a device |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
