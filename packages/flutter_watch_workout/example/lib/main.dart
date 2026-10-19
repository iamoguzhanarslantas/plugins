// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_watch_workout/flutter_watch_workout.dart';

void main() => runApp(const WorkoutExampleApp());

/// A watch app that records an outdoor run.
class WorkoutExampleApp extends StatelessWidget {
  /// The example app.
  const WorkoutExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const WorkoutPage(),
      );
}

/// Start, pause, resume and end a run, and its live metrics.
class WorkoutPage extends StatefulWidget {
  /// The one page.
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  final WatchWorkout _workout = WatchWorkout.instance;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  late final WorkoutSetup _setup = _workout.checkSetup();
  Timer? _ticker;

  WorkoutSessionState _state = WorkoutSessionState.idle;
  WorkoutMetrics? _metrics;
  int _routePoints = 0;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(_workout.states.listen((WorkoutSessionState s) {
        setState(() => _state = s);
      }))
      ..add(_workout.metrics.listen((WorkoutMetrics m) {
        setState(() => _metrics = m);
      }))
      ..add(_workout.locations.listen((WorkoutLocation _) {
        setState(() => _routePoints++);
      }))
      ..add(_workout.errors.listen((WorkoutException e) {
        setState(() => _message = '${e.code}: ${e.message}');
      }));
    // Redraws the elapsed time between metric samples.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state == WorkoutSessionState.running) {
        setState(() {});
      }
    });
    _run(() async {
      if (await _workout.recover()) {
        _message = 'Recovered the running workout.';
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final StreamSubscription<Object?> s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on WorkoutException catch (e) {
      _message = '${e.code}: ${e.message}';
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _start() => _run(() async {
        final WorkoutAuthorization auth = await _workout.requestAuthorization();
        if (auth.workoutSharing != WorkoutPermission.authorized) {
          _message = 'Allow saving workouts in Health to record one.';
          return;
        }
        _routePoints = 0;
        _message = null;
        await _workout.start(
          const WorkoutConfiguration(activity: WorkoutActivity.running),
        );
      });

  Future<void> _end() => _run(() async {
        final WorkoutSummary s = await _workout.end();
        _message = 'Saved ${(s.distance / 1000).toStringAsFixed(2)} km, '
            '${s.activeEnergy.round()} kcal, ${s.routePoints} route points'
            '${s.routeSaved ? '' : ' (no route saved)'}.';
      });

  /// Active time now: the last sample's, plus the time since while running.
  Duration get _elapsed {
    final WorkoutMetrics? m = _metrics;
    if (m == null) {
      return Duration.zero;
    }
    if (_state != WorkoutSessionState.running) {
      return m.elapsed;
    }
    return m.elapsed + DateTime.now().difference(m.timestamp);
  }

  String _clock(Duration d) {
    final String minutes = d.inMinutes.toString().padLeft(2, '0');
    final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final WorkoutMetrics? m = _metrics;
    final bool running = _state == WorkoutSessionState.running;
    final bool paused = _state == WorkoutSessionState.paused;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
        children: <Widget>[
          if (!_workout.isAvailable)
            const Text('HealthKit is not available on this device.'),
          if (_setup.missingUsageDescriptions.isNotEmpty)
            Text('Info.plist lacks '
                '${_setup.missingUsageDescriptions.join(', ')}.'),
          if (!_setup.workoutProcessing)
            const Text('WKBackgroundModes lacks workout-processing.'),
          Text(_clock(_elapsed),
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
          Text('${m?.heartRate?.round() ?? '--'} bpm'),
          Text('${((m?.distance ?? 0) / 1000).toStringAsFixed(2)} km'),
          Text('${(m?.activeEnergy ?? 0).round()} kcal'),
          Text('$_routePoints route points · ${_state.name}'),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_message!,
                  style: const TextStyle(color: Colors.orangeAccent)),
            ),
          const SizedBox(height: 8),
          if (!running && !paused)
            FilledButton(
              onPressed: _busy ? null : _start,
              child: const Text('Start run'),
            ),
          if (running)
            FilledButton.tonal(
              onPressed: _workout.pause,
              child: const Text('Pause'),
            ),
          if (paused)
            FilledButton.tonal(
              onPressed: _workout.resume,
              child: const Text('Resume'),
            ),
          if (running || paused) ...<Widget>[
            FilledButton(
              onPressed: _busy ? null : _end,
              child: const Text('End and save'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(_workout.discard),
              child: const Text('Discard'),
            ),
          ],
        ],
      ),
    );
  }
}
