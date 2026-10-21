// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The C symbols of `watchos/Classes/flutter_watch_workout_ffi.h`, resolved
// from the process. Native wakes Dart through one `NativeCallable.listener`
// that carries a signal kind; every value comes back through a synchronous
// read, as a JSON string native allocated and this file releases.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'backend.dart';

typedef _SignalNative = Void Function(Int64);

/// [WorkoutBackend] over the exported C functions.
class FfiWorkoutBackend implements WorkoutBackend {
  /// Resolves the symbols from the process lazily, on first use.
  FfiWorkoutBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  /// One trampoline for the life of the backend. A [NativeCallable] is only
  /// reclaimed by `close()`, which cannot be called while native may be about
  /// to call it, so it is kept and its pointer unregistered instead.
  NativeCallable<_SignalNative>? _callable;
  void Function(int kind)? _handler;

  late final void Function(Pointer<NativeFunction<_SignalNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<_SignalNative>>),
              void Function(Pointer<NativeFunction<_SignalNative>>)>(
          'flutter_watch_workout_set_callback');
  late final int Function() _isAvailable =
      _lib.lookupFunction<Int32 Function(), int Function()>(
    'flutter_watch_workout_is_available',
  );
  late final Pointer<Utf8> Function() _setupReport =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'flutter_watch_workout_setup_report',
  );
  late final int Function(int) _requestAuthorization =
      _lib.lookupFunction<Int64 Function(Int32), int Function(int)>(
    'flutter_watch_workout_request_authorization',
  );
  late final int Function(Pointer<Utf8>) _start = _lib.lookupFunction<
      Int64 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('flutter_watch_workout_start');
  late final void Function() _pause =
      _lib.lookupFunction<Void Function(), void Function()>(
    'flutter_watch_workout_pause',
  );
  late final void Function() _resume =
      _lib.lookupFunction<Void Function(), void Function()>(
    'flutter_watch_workout_resume',
  );
  late final int Function() _end =
      _lib.lookupFunction<Int64 Function(), int Function()>(
    'flutter_watch_workout_end',
  );
  late final int Function() _discard =
      _lib.lookupFunction<Int64 Function(), int Function()>(
    'flutter_watch_workout_discard',
  );
  late final int Function() _recover =
      _lib.lookupFunction<Int64 Function(), int Function()>(
    'flutter_watch_workout_recover',
  );
  late final int Function() _state =
      _lib.lookupFunction<Int32 Function(), int Function()>(
    'flutter_watch_workout_state',
  );
  late final Pointer<Utf8> Function() _metrics =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'flutter_watch_workout_metrics',
  );
  late final Pointer<Utf8> Function() _pollLocations =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'flutter_watch_workout_poll_locations',
  );
  late final int Function() _droppedLocationCount =
      _lib.lookupFunction<Int64 Function(), int Function()>(
    'flutter_watch_workout_dropped_location_count',
  );
  late final Pointer<Utf8> Function(int) _takeRequestResult =
      _lib.lookupFunction<
          Pointer<Utf8> Function(Int64),
          Pointer<Utf8> Function(
              int)>('flutter_watch_workout_take_request_result');
  late final Pointer<Utf8> Function() _takeLastError =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
    'flutter_watch_workout_take_last_error',
  );
  late final void Function(Pointer<Utf8>) _release = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('flutter_watch_workout_release');

  /// Copies a native string out and releases it; null for a null pointer.
  String? _take(Pointer<Utf8> p) {
    if (p == nullptr) {
      return null;
    }
    try {
      return p.toDartString();
    } finally {
      _release(p);
    }
  }

  @override
  bool isAvailable() => _isAvailable() == 1;

  @override
  String setupReport() => _take(_setupReport()) ?? '{}';

  @override
  int requestAuthorization({required bool route}) =>
      _requestAuthorization(route ? 1 : 0);

  @override
  int start(String configurationJson) => using(
        (Arena arena) =>
            _start(configurationJson.toNativeUtf8(allocator: arena)),
      );

  @override
  void pause() => _pause();

  @override
  void resume() => _resume();

  @override
  int end() => _end();

  @override
  int discard() => _discard();

  @override
  int recover() => _recover();

  @override
  int state() => _state();

  @override
  String? metrics() => _take(_metrics());

  @override
  String? pollLocations() => _take(_pollLocations());

  @override
  int droppedLocationCount() => _droppedLocationCount();

  @override
  String? takeRequestResult(int id) => _take(_takeRequestResult(id));

  @override
  String? takeLastError() => _take(_takeLastError());

  @override
  void setSignalHandler(void Function(int kind)? handler) {
    _handler = handler;
    if (handler == null) {
      _setCallback(nullptr);
      return;
    }
    final NativeCallable<_SignalNative> callable = _callable ??= () {
      final NativeCallable<_SignalNative> created =
          NativeCallable<_SignalNative>.listener(
        (int kind) => _handler?.call(kind),
      );
      // A workout should not, by itself, keep the isolate alive.
      created.keepIsolateAlive = false;
      return created;
    }();
    _setCallback(callable.nativeFunction);
  }
}
