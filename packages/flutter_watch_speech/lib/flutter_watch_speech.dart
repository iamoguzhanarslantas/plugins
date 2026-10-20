// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Text to speech for Flutter apps on the Apple Watch, through
/// `AVSpeechSynthesizer` over dart:ffi.
///
/// Start with [WatchSpeech.instance].
library;

export 'src/backend.dart' show SpeechBackend;
export 'src/types.dart';
export 'src/watch_speech.dart' show WatchSpeech;
