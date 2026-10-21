// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'codec.dart';
import 'ffi_backend.dart';
import 'types.dart';

/// A HealthKit workout session on the Apple Watch: live heart rate, energy
/// and distance while it runs, an optional GPS route, and a workout saved to
/// Health when it ends.
///
/// HealthKit runs one workout session at a time, so there is one of these:
/// [instance].
///
/// ```dart
/// final WatchWorkout workout = WatchWorkout.instance;
/// await workout.requestAuthorization();
/// await workout.start(const WorkoutConfiguration(
///   activity: WorkoutActivity.running,
/// ));
/// workout.metrics.listen((WorkoutMetrics m) => print(m.heartRate));
/// final WorkoutSummary summary = await workout.end();
/// ```
class WatchWorkout {
  WatchWorkout._(this._backend);

  /// A workout over [backend] instead of the native one, for tests.
  @visibleForTesting
  WatchWorkout.withBackend(WorkoutBackend backend) : this._(backend);

  static WatchWorkout? _instance;

  /// The app's workout session.
  static WatchWorkout get instance =>
      _instance ??= WatchWorkout._(FfiWorkoutBackend());

  /// Called by the plugin registrant. There is nothing to register: apps use
  /// [instance] directly.
  static void registerWith() {}

  final WorkoutBackend _backend;

  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  final Set<_StateListener> _stateListeners = <_StateListener>{};
  final Set<MultiStreamController<WorkoutMetrics>> _metricsListeners =
      <MultiStreamController<WorkoutMetrics>>{};
  final Set<MultiStreamController<WorkoutLocation>> _locationListeners =
      <MultiStreamController<WorkoutLocation>>{};
  final Set<MultiStreamController<WorkoutException>> _errorListeners =
      <MultiStreamController<WorkoutException>>{};
  bool _registered = false;

  /// Whether HealthKit is available on this device.
  bool get isAvailable => _backend.isAvailable();

  /// What the app's `Info.plist` lacks for a workout. Nothing here is fatal
  /// to the app: a call that needs a missing key fails with a
  /// [WorkoutException] instead of starting.
  WorkoutSetup checkSetup() => decodeSetup(_backend.setupReport());

  /// Asks the wearer for the HealthKit types a workout writes and reads, and,
  /// when [route] is true, for location access.
  ///
  /// Completes once the wearer has answered the prompts, or at once when they
  /// answered before. Throws a [WorkoutException] with code
  /// `missingUsageDescription` when the `Info.plist` lacks a key the prompts
  /// need, and `healthKit` when the app lacks the HealthKit entitlement.
  Future<WorkoutAuthorization> requestAuthorization({
    bool route = true,
  }) async => decodeAuthorization(
    await _await(_backend.requestAuthorization(route: route)),
  );

  /// Starts a workout session, and its route when
  /// [WorkoutConfiguration.recordRoute] is true.
  ///
  /// Completes once HealthKit is collecting. Throws a [WorkoutException]:
  /// `alreadyRunning` when a session is running, `missingUsageDescription`,
  /// `notAvailable` or `healthKit`.
  Future<void> start(WorkoutConfiguration configuration) async {
    await _await(_backend.start(jsonEncode(configuration.toJson())));
  }

  /// Pauses the running session. [states] reports when it has.
  void pause() => _backend.pause();

  /// Resumes the paused session. [states] reports when it has.
  void resume() => _backend.resume();

  /// Ends the session and saves the workout, with its route when one was
  /// recorded. Throws a [WorkoutException] with code `noSession` when
  /// nothing is running.
  Future<WorkoutSummary> end() async =>
      decodeSummary(await _await(_backend.end()));

  /// Ends the session without saving anything.
  Future<void> discard() async {
    await _await(_backend.discard());
  }

  /// Picks up a session the system kept running after the app quit, and
  /// returns whether there was one.
  ///
  /// Call it at launch: watchOS relaunches an app whose workout was running
  /// when it crashed. A route restarts from the recovered moment; points
  /// recorded before are not recovered.
  Future<bool> recover() async =>
      (await _await(_backend.recover()))['recovered'] == true;

  /// The session's state now.
  WorkoutSessionState get state =>
      WorkoutSessionState.fromHealthKit(_backend.state());

  /// The metrics the watch last reported, or null before the first sample.
  /// They stay readable after the workout ends, until the next one starts.
  WorkoutMetrics? get latestMetrics {
    final String? json = _backend.metrics();
    return json == null ? null : decodeMetrics(json);
  }

  /// How many route points of this workout were dropped because nothing
  /// listened to [locations] in time. Native keeps the latest 512; the count
  /// starts again at 0 with each workout.
  int get droppedLocationCount => _backend.droppedLocationCount();

  /// The session's state, starting with the current one, then each change.
  Stream<WorkoutSessionState> get states => Stream<WorkoutSessionState>.multi((
    MultiStreamController<WorkoutSessionState> c,
  ) {
    final _StateListener listener = _StateListener(c);
    _stateListeners.add(listener);
    _updateRegistration();
    listener.emit(state);
    c.onCancel = () {
      _stateListeners.remove(listener);
      _updateRegistration();
    };
  }, isBroadcast: true);

  /// The running totals, starting with [latestMetrics] when there are any,
  /// then each time the watch reports new ones.
  Stream<WorkoutMetrics> get metrics =>
      Stream<WorkoutMetrics>.multi((MultiStreamController<WorkoutMetrics> c) {
        _metricsListeners.add(c);
        _updateRegistration();
        final WorkoutMetrics? latest = latestMetrics;
        if (latest != null) {
          c.add(latest);
        }
        c.onCancel = () {
          _metricsListeners.remove(c);
          _updateRegistration();
        };
      }, isBroadcast: true);

  /// The route points as they are recorded. A new listener first receives
  /// the points recorded since anything last listened.
  Stream<WorkoutLocation> get locations =>
      Stream<WorkoutLocation>.multi((MultiStreamController<WorkoutLocation> c) {
        _locationListeners.add(c);
        _updateRegistration();
        _drainLocations();
        c.onCancel = () {
          _locationListeners.remove(c);
          _updateRegistration();
        };
      }, isBroadcast: true);

  /// Failures that arrive outside a call: the session failing, a route point
  /// that could not be saved, a location error. A new listener first
  /// receives those queued while nothing listened (up to 32).
  Stream<WorkoutException> get errors => Stream<WorkoutException>.multi((
    MultiStreamController<WorkoutException> c,
  ) {
    _errorListeners.add(c);
    _updateRegistration();
    _drainErrors();
    c.onCancel = () {
      _errorListeners.remove(c);
      _updateRegistration();
    };
  }, isBroadcast: true);

  bool get _wanted =>
      _pending.isNotEmpty ||
      _stateListeners.isNotEmpty ||
      _metricsListeners.isNotEmpty ||
      _locationListeners.isNotEmpty ||
      _errorListeners.isNotEmpty;

  /// Registers the signal handler while anything waits, and unregisters it
  /// when nothing does.
  void _updateRegistration() {
    final bool wanted = _wanted;
    if (wanted == _registered) {
      return;
    }
    _registered = wanted;
    _backend.setSignalHandler(wanted ? _onSignal : null);
  }

  void _onSignal(int kind) {
    switch (kind) {
      case WorkoutSignal.state:
        final WorkoutSessionState now = state;
        for (final _StateListener l in _stateListeners.toList()) {
          l.emit(now);
        }
      case WorkoutSignal.metrics:
        final WorkoutMetrics? latest = latestMetrics;
        if (latest != null) {
          for (final MultiStreamController<WorkoutMetrics> c
              in _metricsListeners.toList()) {
            c.add(latest);
          }
        }
      case WorkoutSignal.locations:
        _drainLocations();
      case WorkoutSignal.error:
        _drainErrors();
      case WorkoutSignal.request:
        _drainRequests();
    }
  }

  /// Hands buffered route points to every location listener. Leaves them
  /// buffered natively while there is none.
  void _drainLocations() {
    if (_locationListeners.isEmpty) {
      return;
    }
    final String? json = _backend.pollLocations();
    if (json == null) {
      return;
    }
    final List<WorkoutLocation> points = decodeLocations(json);
    for (final MultiStreamController<WorkoutLocation> c
        in _locationListeners.toList()) {
      points.forEach(c.add);
    }
  }

  /// Hands queued session errors to every error listener. Leaves them queued
  /// natively while there is none.
  void _drainErrors() {
    if (_errorListeners.isEmpty) {
      return;
    }
    for (
      String? json = _backend.takeLastError();
      json != null;
      json = _backend.takeLastError()
    ) {
      final WorkoutException error = decodeError(decodeObject(json));
      for (final MultiStreamController<WorkoutException> c
          in _errorListeners.toList()) {
        c.add(error);
      }
    }
  }

  /// Completes every pending request whose result has landed.
  void _drainRequests() {
    for (final int id in _pending.keys.toList()) {
      final String? json = _backend.takeRequestResult(id);
      if (json == null) {
        continue;
      }
      final Completer<Map<String, Object?>> completer = _pending.remove(id)!;
      final Map<String, Object?> result = decodeObject(json);
      final Object? error = result['error'];
      if (error is Map<Object?, Object?>) {
        completer.completeError(decodeError(error.cast<String, Object?>()));
      } else {
        completer.complete(result);
      }
    }
    _updateRegistration();
  }

  /// Waits for request [id]'s result.
  Future<Map<String, Object?>> _await(int id) {
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _updateRegistration();
    // The result may have landed before the handler was registered, as a
    // refused precondition does inside the call itself.
    _drainRequests();
    return completer.future;
  }
}

/// A [WatchWorkout.states] subscriber, which is told a state only when it
/// differs from the last one it was told.
class _StateListener {
  _StateListener(this.controller);

  final MultiStreamController<WorkoutSessionState> controller;
  WorkoutSessionState? _last;

  void emit(WorkoutSessionState state) {
    if (state == _last) {
      return;
    }
    _last = state;
    controller.add(state);
  }
}
