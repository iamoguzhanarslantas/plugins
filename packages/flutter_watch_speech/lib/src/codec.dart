// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The JSON native hands over, turned into this package's types.

import 'dart:convert';

import 'types.dart';

/// What woke Dart up. Mirrored in `watchos/Classes/flutter_watch_speech_ffi.h`.
abstract final class SpeechSignal {
  /// Events are queued.
  static const int events = 1;
}

/// The `poll_events` JSON array.
List<SpeechEvent> decodeEvents(String json) => <SpeechEvent>[
      for (final Object? item in jsonDecode(json) as List<Object?>)
        if (item is Map<Object?, Object?>)
          for (final SpeechEventType type in SpeechEventType.values)
            if (type.name == item['type'])
              SpeechEvent((item['id']! as num).toInt(), type),
    ];

/// The `voices` JSON array.
List<SpeechVoice> decodeVoices(String json) => <SpeechVoice>[
      for (final Object? item in jsonDecode(json) as List<Object?>)
        if (item is Map<Object?, Object?>)
          SpeechVoice(
            identifier: item['identifier'] as String? ?? '',
            name: item['name'] as String? ?? '',
            language: item['language'] as String? ?? '',
            quality: switch (item['quality']) {
              'enhanced' => SpeechVoiceQuality.enhanced,
              'premium' => SpeechVoiceQuality.premium,
              _ => SpeechVoiceQuality.standard,
            },
          ),
    ];
