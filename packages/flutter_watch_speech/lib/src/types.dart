// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// How to speak an utterance. Every field left null keeps the system's
/// default.
class SpeechOptions {
  /// Options with these values.
  const SpeechOptions({
    this.language,
    this.voiceIdentifier,
    this.rate,
    this.pitch,
    this.volume,
    this.preUtteranceDelay,
    this.postUtteranceDelay,
    this.duckOthers = true,
  });

  /// A BCP 47 language code, for example `en-US` or `tr-TR`. The system's
  /// voice for it speaks, unless [voiceIdentifier] names one.
  final String? language;

  /// A [SpeechVoice.identifier], which wins over [language].
  final String? voiceIdentifier;

  /// Speed from 0 (slowest) to 1 (fastest) across the synthesizer's range.
  final double? rate;

  /// Pitch multiplier from 0.5 to 2.
  final double? pitch;

  /// Volume from 0 to 1, relative to the system volume.
  final double? volume;

  /// Silence before the utterance.
  final Duration? preUtteranceDelay;

  /// Silence after it.
  final Duration? postUtteranceDelay;

  /// Whether other audio, music or a podcast, is lowered while speech plays
  /// and raised again after the last utterance.
  final bool duckOthers;

  /// The JSON the native side reads.
  Map<String, Object?> toJson() => <String, Object?>{
        'language': language,
        'voice': voiceIdentifier,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'preDelay': preUtteranceDelay == null
            ? null
            : preUtteranceDelay!.inMicroseconds / 1000000,
        'postDelay': postUtteranceDelay == null
            ? null
            : postUtteranceDelay!.inMicroseconds / 1000000,
        'duckOthers': duckOthers,
      };
}

/// How an utterance ended.
enum SpeechOutcome {
  /// Spoken to the end.
  finished,

  /// Stopped before the end, by `WatchSpeech.stop`.
  cancelled,
}

/// What happened to an utterance.
enum SpeechEventType {
  /// It began to play.
  started,

  /// It played to the end.
  finished,

  /// It was stopped before the end.
  cancelled,

  /// It paused.
  paused,

  /// It continued after a pause.
  continued,
}

/// One thing that happened to an utterance.
class SpeechEvent {
  /// An event with these values.
  const SpeechEvent(this.utteranceId, this.type);

  /// The id `speak` was given.
  final int utteranceId;

  /// What happened.
  final SpeechEventType type;

  @override
  String toString() => 'SpeechEvent($utteranceId, ${type.name})';
}

/// The quality of a voice.
enum SpeechVoiceQuality {
  /// The compact voice every device has.
  standard,

  /// A larger, more natural voice the wearer downloaded.
  enhanced,

  /// The most natural voices (watchOS 9 and later).
  premium,
}

/// An installed voice.
class SpeechVoice {
  /// A voice with these values.
  const SpeechVoice({
    required this.identifier,
    required this.name,
    required this.language,
    required this.quality,
  });

  /// What [SpeechOptions.voiceIdentifier] takes.
  final String identifier;

  /// Its display name, for example `Samantha`.
  final String name;

  /// Its BCP 47 language code.
  final String language;

  /// Its quality.
  final SpeechVoiceQuality quality;
}
