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

/// Text to speech on the Apple Watch, through `AVSpeechSynthesizer`.
///
/// ```dart
/// final WatchSpeech speech = WatchSpeech.instance;
/// await speech.speak('One kilometre. Pace five thirty.',
///     options: const SpeechOptions(language: 'en-US', rate: 0.45));
/// ```
///
/// Utterances queue: each [speak] starts after the one before it ends, and
/// completes with how its own utterance ended.
class WatchSpeech {
  WatchSpeech._(this._backend);

  /// A speech over [backend] instead of the native one, for tests.
  @visibleForTesting
  WatchSpeech.withBackend(SpeechBackend backend) : this._(backend);

  static WatchSpeech? _instance;

  /// The app's speech synthesizer.
  static WatchSpeech get instance =>
      _instance ??= WatchSpeech._(FfiSpeechBackend());

  /// Called by the plugin registrant. There is nothing to register: apps use
  /// [instance] directly.
  static void registerWith() {}

  final SpeechBackend _backend;
  final Map<int, Completer<SpeechOutcome>> _pending =
      <int, Completer<SpeechOutcome>>{};
  final Set<MultiStreamController<SpeechEvent>> _listeners =
      <MultiStreamController<SpeechEvent>>{};
  bool _registered = false;

  /// What [speak] uses for each option it is not given.
  SpeechOptions defaultOptions = const SpeechOptions();

  /// Speaks [text] once everything queued before it has been spoken, and
  /// completes with how it ended. Empty text completes at once as finished.
  Future<SpeechOutcome> speak(String text, {SpeechOptions? options}) {
    if (text.trim().isEmpty) {
      return Future<SpeechOutcome>.value(SpeechOutcome.finished);
    }
    final Completer<SpeechOutcome> completer = Completer<SpeechOutcome>();
    final int id =
        _backend.speak(text, jsonEncode((options ?? defaultOptions).toJson()));
    _pending[id] = completer;
    _update();
    // Its events may have queued before the handler was registered.
    _drain();
    return completer.future;
  }

  /// Stops at once and drops everything queued; each pending [speak]
  /// completes as cancelled. Returns whether anything was speaking.
  Future<bool> stop() async => _backend.stop();

  /// Pauses at the end of the current word. Returns whether anything was
  /// speaking.
  Future<bool> pause() async => _backend.pause();

  /// Continues paused speech. Returns whether anything was paused.
  Future<bool> resume() async => _backend.resume();

  /// Whether anything is speaking, paused included.
  bool get isSpeaking => _backend.isSpeaking();

  /// Whether speech is paused.
  bool get isPaused => _backend.isPaused();

  /// The installed voices.
  List<SpeechVoice> get voices => decodeVoices(_backend.voices());

  /// The language the system speaks in by default, for example `en-GB`.
  String get currentLanguage => _backend.currentLanguage();

  /// Everything that happens to utterances, from now on.
  Stream<SpeechEvent> get events =>
      Stream<SpeechEvent>.multi((MultiStreamController<SpeechEvent> c) {
        _listeners.add(c);
        _update();
        c.onCancel = () {
          _listeners.remove(c);
          _update();
        };
      }, isBroadcast: true);

  void _update() {
    final bool wanted = _pending.isNotEmpty || _listeners.isNotEmpty;
    if (wanted == _registered) {
      return;
    }
    _registered = wanted;
    _backend.setSignalHandler(wanted
        ? (int kind) {
            if (kind == SpeechSignal.events) {
              _drain();
            }
          }
        : null);
  }

  void _drain() {
    final String? json = _backend.pollEvents();
    if (json == null) {
      return;
    }
    for (final SpeechEvent event in decodeEvents(json)) {
      for (final MultiStreamController<SpeechEvent> c in _listeners.toList()) {
        c.add(event);
      }
      final SpeechOutcome? outcome = switch (event.type) {
        SpeechEventType.finished => SpeechOutcome.finished,
        SpeechEventType.cancelled => SpeechOutcome.cancelled,
        _ => null,
      };
      if (outcome != null) {
        _pending.remove(event.utteranceId)?.complete(outcome);
      }
    }
    _update();
  }
}
