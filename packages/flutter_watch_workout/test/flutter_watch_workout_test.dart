// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The native HealthKit backend is replaced with a fake
// that hands back the JSON the native header documents, so the request,
// signal and stream machinery is checked off-device. HealthKit itself is
// exercised by the example's integration test and on a watch.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_workout/flutter_watch_workout.dart';

/// Signal kinds, mirrored from the native header.
const int kState = 1;
const int kMetrics = 2;
const int kLocations = 3;
const int kError = 4;
const int kRequest = 5;

class _FakeBackend implements WorkoutBackend {
  bool available = true;
  String setup = '{"missing": [], "workoutProcessing": true}';
  int nativeState = 0;
  String? metricsJson;
  final List<Map<String, Object?>> bufferedLocations = <Map<String, Object?>>[];
  int dropped = 0;
  final Map<int, String> results = <int, String>{};
  final List<String> errors = <String>[];
  final List<String> calls = <String>[];
  String? lastConfiguration;
  int _next = 1;

  void Function(int kind)? handler;

  /// What the next request-starting call answers at once, as a refused
  /// precondition does inside the native call.
  String? immediateResult;

  int _request(String name) {
    calls.add(name);
    final int id = _next++;
    if (immediateResult != null) {
      results[id] = immediateResult!;
      immediateResult = null;
    }
    return id;
  }

  /// Lands [result] for request [id] and signals, as native does.
  void finish(int id, Object result) {
    results[id] = jsonEncode(result);
    signal(kRequest);
  }

  void signal(int kind) => handler?.call(kind);

  @override
  bool isAvailable() => available;
  @override
  String setupReport() => setup;
  @override
  int requestAuthorization({required bool route}) =>
      _request('requestAuthorization(route: $route)');
  @override
  int start(String configurationJson) {
    lastConfiguration = configurationJson;
    return _request('start');
  }

  @override
  void pause() => calls.add('pause');
  @override
  void resume() => calls.add('resume');
  @override
  int end() => _request('end');
  @override
  int discard() => _request('discard');
  @override
  int recover() => _request('recover');
  @override
  int state() => nativeState;
  @override
  String? metrics() => metricsJson;
  @override
  String? pollLocations() {
    if (bufferedLocations.isEmpty) {
      return null;
    }
    final String json = jsonEncode(bufferedLocations);
    bufferedLocations.clear();
    return json;
  }

  @override
  int droppedLocationCount() => dropped;
  @override
  String? takeRequestResult(int id) => results.remove(id);
  @override
  String? takeLastError() => errors.isEmpty ? null : errors.removeAt(0);
  @override
  void setSignalHandler(void Function(int kind)? h) => handler = h;
}

Map<String, Object?> _location(double latitude) => <String, Object?>{
  'latitude': latitude,
  'longitude': 29.0,
  'altitude': 40.0,
  'horizontalAccuracy': 5.0,
  'verticalAccuracy': 3.0,
  'speed': 3.2,
  'course': 90.0,
  'timestamp': 1792400000000,
};

void main() {
  late _FakeBackend fake;
  late WatchWorkout workout;

  setUp(() {
    fake = _FakeBackend();
    workout = WatchWorkout.withBackend(fake);
  });

  group('requests', () {
    test('start sends the configuration and completes on its result', () async {
      bool done = false;
      final Future<void> started = workout
          .start(const WorkoutConfiguration(activity: WorkoutActivity.cycling))
          .then((_) => done = true);
      await pumpEventQueue();
      expect(done, isFalse, reason: 'nothing has landed yet');
      expect(jsonDecode(fake.lastConfiguration!), <String, Object?>{
        'activity': 13,
        'location': 3,
        'route': true,
      });

      fake.finish(1, <String, Object?>{});
      await started;
      expect(done, isTrue);
    });

    test('an indoor workout records no route unless asked', () async {
      unawaited(
        workout.start(
          const WorkoutConfiguration(
            activity: WorkoutActivity.running,
            location: WorkoutLocationType.indoor,
          ),
        ),
      );
      expect(jsonDecode(fake.lastConfiguration!)['route'], isFalse);
      unawaited(
        workout.start(
          const WorkoutConfiguration(
            activity: WorkoutActivity.running,
            location: WorkoutLocationType.indoor,
            recordRoute: true,
          ),
        ),
      );
      expect(jsonDecode(fake.lastConfiguration!)['route'], isTrue);
    });

    test(
      'a result that landed inside the call completes without a signal',
      () async {
        fake.immediateResult = jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 'missingUsageDescription',
            'message':
                "The watch app's Info.plist has no "
                'NSHealthShareUsageDescription.',
            'nativeCode': 0,
          },
        });
        await expectLater(
          workout.requestAuthorization(),
          throwsA(
            isA<WorkoutException>()
                .having(
                  (WorkoutException e) => e.code,
                  'code',
                  'missingUsageDescription',
                )
                .having(
                  (WorkoutException e) => e.message,
                  'message',
                  contains('NSHealthShareUsageDescription'),
                ),
          ),
        );
      },
    );

    test('a native error carries its code', () async {
      final Future<void> started = workout.start(
        const WorkoutConfiguration(activity: WorkoutActivity.running),
      );
      fake.finish(1, <String, Object?>{
        'error': <String, Object?>{
          'code': 'healthKit',
          'message': 'Missing com.apple.developer.healthkit entitlement.',
          'nativeCode': 4,
        },
      });
      await expectLater(
        started,
        throwsA(
          isA<WorkoutException>()
              .having((WorkoutException e) => e.code, 'code', 'healthKit')
              .having((WorkoutException e) => e.nativeCode, 'nativeCode', 4),
        ),
      );
    });

    test('authorization maps both answers', () async {
      final Future<WorkoutAuthorization> asked = workout.requestAuthorization();
      expect(fake.calls.single, 'requestAuthorization(route: true)');
      fake.finish(1, <String, Object?>{
        'workoutSharing': 'authorized',
        'location': 'denied',
      });
      final WorkoutAuthorization answer = await asked;
      expect(answer.workoutSharing, WorkoutPermission.authorized);
      expect(answer.location, WorkoutPermission.denied);
    });

    test('authorization without a route does not ask for location', () async {
      final Future<WorkoutAuthorization> asked = workout.requestAuthorization(
        route: false,
      );
      expect(fake.calls.single, 'requestAuthorization(route: false)');
      fake.finish(1, <String, Object?>{
        'workoutSharing': 'notDetermined',
        'location': 'notRequested',
      });
      expect((await asked).location, WorkoutPermission.notRequested);
    });

    test('end returns the saved summary', () async {
      final Future<WorkoutSummary> ended = workout.end();
      fake.finish(1, <String, Object?>{
        'uuid': 'A1B2',
        'duration': 1800.5,
        'activeEnergy': 320.25,
        'distance': 5012.0,
        'routePoints': 1795,
        'routeSaved': true,
      });
      final WorkoutSummary summary = await ended;
      expect(summary.uuid, 'A1B2');
      expect(
        summary.duration,
        const Duration(seconds: 1800, milliseconds: 500),
      );
      expect(summary.activeEnergy, 320.25);
      expect(summary.distance, 5012.0);
      expect(summary.routePoints, 1795);
      expect(summary.routeSaved, isTrue);
    });

    test('two requests in flight complete independently', () async {
      final Future<bool> recovered = workout.recover();
      final Future<void> discarded = workout.discard();
      fake.finish(2, <String, Object?>{});
      await discarded;
      fake.finish(1, <String, Object?>{'recovered': true});
      expect(await recovered, isTrue);
    });

    test('the handler is registered only while something waits', () async {
      expect(fake.handler, isNull);
      final Future<bool> recovered = workout.recover();
      expect(fake.handler, isNotNull);
      fake.finish(1, <String, Object?>{'recovered': false});
      expect(await recovered, isFalse);
      expect(fake.handler, isNull);
    });

    test('pause and resume reach native', () {
      workout
        ..pause()
        ..resume();
      expect(fake.calls, <String>['pause', 'resume']);
    });
  });

  group('states', () {
    test(
      'a listener starts with the current state, then each change',
      () async {
        fake.nativeState = 0;
        final List<WorkoutSessionState> seen = <WorkoutSessionState>[];
        final StreamSubscription<WorkoutSessionState> sub = workout.states
            .listen(seen.add);
        await pumpEventQueue();

        fake.nativeState = 2;
        fake.signal(kState);
        fake.nativeState = 4;
        fake.signal(kState);
        await pumpEventQueue();

        expect(seen, <WorkoutSessionState>[
          WorkoutSessionState.idle,
          WorkoutSessionState.running,
          WorkoutSessionState.paused,
        ]);
        await sub.cancel();
        expect(fake.handler, isNull);
      },
    );

    test('a repeated state is not repeated on the stream', () async {
      fake.nativeState = 2;
      final List<WorkoutSessionState> seen = <WorkoutSessionState>[];
      final StreamSubscription<WorkoutSessionState> sub = workout.states.listen(
        seen.add,
      );
      fake.signal(kState);
      fake.signal(kState);
      await pumpEventQueue();
      expect(seen, <WorkoutSessionState>[WorkoutSessionState.running]);
      await sub.cancel();
    });

    test('a late listener starts with the state now', () async {
      final StreamSubscription<WorkoutSessionState> first = workout.states
          .listen((_) {});
      fake.nativeState = 2;
      fake.signal(kState);
      await expectLater(
        workout.states.first,
        completion(WorkoutSessionState.running),
      );
      await first.cancel();
    });

    test('an unknown raw state reads as idle', () {
      fake.nativeState = 99;
      expect(workout.state, WorkoutSessionState.idle);
    });
  });

  group('metrics', () {
    const String sample =
        '{"heartRate": 142.0, "activeEnergy": 81.5, '
        '"distance": 1204.0, "elapsed": 431.25, "timestamp": 1792400000000}';

    test('each signal emits the latest metrics', () async {
      final List<WorkoutMetrics> seen = <WorkoutMetrics>[];
      final StreamSubscription<WorkoutMetrics> sub = workout.metrics.listen(
        seen.add,
      );
      await pumpEventQueue();
      expect(seen, isEmpty, reason: 'no sample yet');

      fake.metricsJson = sample;
      fake.signal(kMetrics);
      await pumpEventQueue();

      final WorkoutMetrics m = seen.single;
      expect(m.heartRate, 142.0);
      expect(m.activeEnergy, 81.5);
      expect(m.distance, 1204.0);
      expect(m.elapsed, const Duration(seconds: 431, milliseconds: 250));
      expect(m.timestamp, DateTime.fromMillisecondsSinceEpoch(1792400000000));
      await sub.cancel();
    });

    test('a listener starts with the latest metrics', () async {
      fake.metricsJson = sample;
      expect((await workout.metrics.first).distance, 1204.0);
    });

    test('a heart rate not yet read is null', () {
      fake.metricsJson =
          '{"heartRate": null, "activeEnergy": 0, '
          '"distance": 0, "elapsed": 0, "timestamp": 0}';
      expect(workout.latestMetrics!.heartRate, isNull);
    });
  });

  group('locations', () {
    test('points recorded while nothing listened arrive first', () async {
      fake.bufferedLocations.addAll(<Map<String, Object?>>[
        _location(41.0),
        _location(41.1),
      ]);
      final List<WorkoutLocation> seen = <WorkoutLocation>[];
      final StreamSubscription<WorkoutLocation> sub = workout.locations.listen(
        seen.add,
      );
      await pumpEventQueue();
      expect(seen.map((WorkoutLocation l) => l.latitude), <double>[41.0, 41.1]);

      fake.bufferedLocations.add(_location(41.2));
      fake.signal(kLocations);
      await pumpEventQueue();
      expect(seen, hasLength(3));
      final WorkoutLocation last = seen.last;
      expect(last.longitude, 29.0);
      expect(last.speed, 3.2);
      expect(last.course, 90.0);
      expect(last.horizontalAccuracy, 5.0);
      await sub.cancel();
    });

    test('two listeners both receive every point', () async {
      final List<WorkoutLocation> a = <WorkoutLocation>[];
      final List<WorkoutLocation> b = <WorkoutLocation>[];
      final StreamSubscription<WorkoutLocation> subA = workout.locations.listen(
        a.add,
      );
      final StreamSubscription<WorkoutLocation> subB = workout.locations.listen(
        b.add,
      );
      fake.bufferedLocations.add(_location(40.0));
      fake.signal(kLocations);
      await pumpEventQueue();
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await subA.cancel();
      await subB.cancel();
    });

    test('points stay buffered natively while nothing listens', () async {
      final StreamSubscription<WorkoutSessionState> keepAlive = workout.states
          .listen((_) {});
      fake.bufferedLocations.add(_location(40.0));
      fake.signal(kLocations);
      expect(fake.bufferedLocations, hasLength(1));
      await keepAlive.cancel();
    });

    test('the dropped count is native', () {
      fake.dropped = 7;
      expect(workout.droppedLocationCount, 7);
    });
  });

  group('errors and setup', () {
    test('errors queued before listening arrive first, in order', () async {
      fake.errors.addAll(<String>[
        '{"code": "session", "message": "first", "nativeCode": 1}',
        '{"code": "route", "message": "second", "nativeCode": 2}',
      ]);
      final List<WorkoutException> seen = <WorkoutException>[];
      final StreamSubscription<WorkoutException> sub = workout.errors.listen(
        seen.add,
      );
      await pumpEventQueue();
      expect(seen.map((WorkoutException e) => e.message), <String>[
        'first',
        'second',
      ]);

      fake.errors.add(
        '{"code": "location", "message": "third", '
        '"nativeCode": 3}',
      );
      fake.signal(kError);
      await pumpEventQueue();
      expect(seen.last.code, 'location');
      await sub.cancel();
    });

    test('checkSetup reports what the Info.plist lacks', () {
      fake.setup =
          '{"missing": ["NSHealthUpdateUsageDescription"], '
          '"workoutProcessing": false, "backgroundLocation": true}';
      final WorkoutSetup setup = workout.checkSetup();
      expect(setup.missingUsageDescriptions, <String>[
        'NSHealthUpdateUsageDescription',
      ]);
      expect(setup.workoutProcessing, isFalse);
      expect(setup.backgroundLocation, isTrue);
      expect(setup.isComplete, isFalse);
    });

    test('a complete setup is complete', () {
      expect(workout.checkSetup().isComplete, isTrue);
    });

    test('isAvailable is native', () {
      fake.available = false;
      expect(workout.isAvailable, isFalse);
    });

    test('registerWith does nothing and does not throw', () {
      expect(WatchWorkout.registerWith, returnsNormally);
    });
  });

  test('activities and location types carry the HealthKit raw values', () {
    expect(WorkoutActivity.running.healthKitValue, 37);
    expect(WorkoutActivity.walking.healthKitValue, 52);
    expect(WorkoutActivity.cycling.healthKitValue, 13);
    expect(WorkoutActivity.hiking.healthKitValue, 24);
    expect(WorkoutActivity.other.healthKitValue, 3000);
    expect(WorkoutLocationType.outdoor.healthKitValue, 3);
    expect(WorkoutSessionState.fromHealthKit(6), WorkoutSessionState.stopped);
  });
}
