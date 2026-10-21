## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* `WatchWorkout`: an `HKWorkoutSession` with its `HKLiveWorkoutBuilder`,
  started, paused, resumed, ended (saving the workout) or discarded.
* Live `metrics`: heart rate, active energy, distance and active elapsed time.
* An optional GPS route: a `CLLocationManager` feeds an
  `HKWorkoutRouteBuilder`, the route is saved with the workout, and each point
  is also streamed on `locations`.
* `recover()` picks up a session the system kept running.
* `requestAuthorization()` asks for HealthKit and, for a route, when-in-use
  location access.
* `checkSetup()` reports the usage descriptions and the `workout-processing`
  background mode the `Info.plist` lacks; calls that need a missing usage
  description fail with a `WorkoutException` instead of terminating the app.
* Native wakes Dart through one `NativeCallable.listener` that carries a
  signal kind; values come back as JSON through synchronous reads.
* The route's `CLLocationManager` turns on `allowsBackgroundLocationUpdates`
  when `UIBackgroundModes` has `location`, and `checkSetup()` reports it as
  `backgroundLocation`.
* `droppedLocationCount` starts again at 0 with each workout.
