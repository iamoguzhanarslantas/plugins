# flutter_watch_workout_example

A watchOS-only example: start a run, watch the heart rate, energy, distance
and route points come in, pause, resume, and end it to save the workout to
Health. Run it on an Apple Watch simulator with:

```sh
flutter-watchos run
```

The runner's `Info.plist` has the three usage descriptions and the
`workout-processing` background mode, and `Runner/Runner.entitlements` has
the HealthKit entitlement, which a workout app needs.
