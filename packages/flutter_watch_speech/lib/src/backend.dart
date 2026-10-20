// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The native half of a [WatchSpeech], behind an interface so host tests can
/// substitute a fake without a native binary present. Every member maps to
/// one exported C function.
library;

import 'watch_speech.dart';

/// See the library documentation.
abstract class SpeechBackend {
  /// Queues [text] with [optionsJson] and returns its utterance id.
  int speak(String text, String optionsJson);

  /// Stops at once and clears the queue; true when something was speaking.
  bool stop();

  /// Pauses at the next word; true when something was speaking.
  bool pause();

  /// Continues paused speech; true when something was paused.
  bool resume();

  /// Whether anything is speaking, paused included.
  bool isSpeaking();

  /// Whether speech is paused.
  bool isPaused();

  /// The installed voices as JSON.
  String voices();

  /// The system's default speech language.
  String currentLanguage();

  /// The queued events as a JSON array, or null when none are.
  String? pollEvents();

  /// The function native wakes, or null to stop.
  void setSignalHandler(void Function(int kind)? handler);
}
