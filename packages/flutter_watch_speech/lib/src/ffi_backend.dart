// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The C symbols of `watchos/Classes/flutter_watch_speech_ffi.h`, resolved from
// the process.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'backend.dart';

typedef _SignalNative = Void Function(Int64);

/// [SpeechBackend] over the exported C functions.
class FfiSpeechBackend implements SpeechBackend {
  /// Resolves the symbols from the process lazily, on first use.
  FfiSpeechBackend() : _lib = DynamicLibrary.process();

  final DynamicLibrary _lib;

  /// One trampoline for the life of the backend; only its pointer is
  /// unregistered, since a [NativeCallable] is reclaimed only by `close()`.
  NativeCallable<_SignalNative>? _callable;
  void Function(int kind)? _handler;

  late final void Function(Pointer<NativeFunction<_SignalNative>>)
      _setCallback = _lib.lookupFunction<
              Void Function(Pointer<NativeFunction<_SignalNative>>),
              void Function(Pointer<NativeFunction<_SignalNative>>)>(
          'flutter_watch_speech_set_callback');
  late final int Function(Pointer<Utf8>, Pointer<Utf8>) _speak =
      _lib.lookupFunction<
          Int64 Function(Pointer<Utf8>, Pointer<Utf8>),
          int Function(
              Pointer<Utf8>, Pointer<Utf8>)>('flutter_watch_speech_speak');
  late final int Function() _stop =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_speech_stop');
  late final int Function() _pause =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_speech_pause');
  late final int Function() _resume =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_speech_resume');
  late final int Function() _isSpeaking =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_speech_is_speaking');
  late final int Function() _isPaused =
      _lib.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_speech_is_paused');
  late final Pointer<Utf8> Function() _voices =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_speech_voices');
  late final Pointer<Utf8> Function() _currentLanguage =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_speech_current_language');
  late final Pointer<Utf8> Function() _pollEvents =
      _lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_speech_poll_events');
  late final void Function(Pointer<Utf8>) _release = _lib.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('flutter_watch_speech_release');

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
  int speak(String text, String optionsJson) => using((Arena arena) => _speak(
        text.toNativeUtf8(allocator: arena),
        optionsJson.toNativeUtf8(allocator: arena),
      ));

  @override
  bool stop() => _stop() == 1;
  @override
  bool pause() => _pause() == 1;
  @override
  bool resume() => _resume() == 1;
  @override
  bool isSpeaking() => _isSpeaking() == 1;
  @override
  bool isPaused() => _isPaused() == 1;
  @override
  String voices() => _take(_voices()) ?? '[]';
  @override
  String currentLanguage() => _take(_currentLanguage()) ?? '';
  @override
  String? pollEvents() => _take(_pollEvents());

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
              (int kind) => _handler?.call(kind));
      created.keepIsolateAlive = false;
      return created;
    }();
    _setCallback(callable.nativeFunction);
  }
}
