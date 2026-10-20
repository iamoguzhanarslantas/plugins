// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Text to speech on the Apple Watch, over dart:ffi: one AVSpeechSynthesizer.
//
// Each `speak` returns an utterance id at once. What happens to utterances
// afterwards (started, finished, cancelled, paused, continued) is queued as
// events; native wakes Dart through one callback that carries a kind, never
// a payload, and Dart drains the queue as JSON that native allocates and
// `flutter_watch_speech_release` releases.

#ifndef FLUTTER_WATCH_SPEECH_FFI_H
#define FLUTTER_WATCH_SPEECH_FFI_H

#include <stdint.h>

// Each exported symbol is marked `used` + default-visibility so it survives
// the linker's `-dead_strip` and lands in the executable's dynamic symbol
// table, where `DynamicLibrary.process()` / dlsym can resolve it.
#define FWS_EXPORT __attribute__((visibility("default"))) __attribute__((used))

// What woke Dart up. Mirrored in lib/src/codec.dart.
#define FWS_SIGNAL_EVENTS 1

// How many events native holds for Dart before it drops the oldest.
#define FWS_EVENT_BUFFER 256

typedef void (*fws_signal_callback)(int64_t kind);

// Registers the callback Dart wants woken, or NULL to stop signalling.
FWS_EXPORT
void flutter_watch_speech_set_callback(fws_signal_callback callback);

// Queues `text` for speaking and returns its utterance id (1 or more). The
// options are a JSON object whose keys may each be missing or null:
// {"language", "voice" (an identifier), "rate" (0..1), "pitch" (0.5..2),
// "volume" (0..1), "preDelay" and "postDelay" (seconds), "duckOthers"}.
FWS_EXPORT
int64_t flutter_watch_speech_speak(const char* text, const char* options_json);

// Stops at once and clears the queue; 1 when something was speaking.
FWS_EXPORT
int flutter_watch_speech_stop(void);

// Pauses at the next word; 1 when something was speaking.
FWS_EXPORT
int flutter_watch_speech_pause(void);

// Continues paused speech; 1 when something was paused.
FWS_EXPORT
int flutter_watch_speech_resume(void);

// 1 while speaking (paused included), 0 otherwise.
FWS_EXPORT
int flutter_watch_speech_is_speaking(void);

// 1 while paused, 0 otherwise.
FWS_EXPORT
int flutter_watch_speech_is_paused(void);

// The installed voices as a JSON array of {"identifier", "name", "language",
// "quality": "default"|"enhanced"|"premium"}.
FWS_EXPORT
char* flutter_watch_speech_voices(void);

// The language the system speaks in by default, as a BCP 47 code.
FWS_EXPORT
char* flutter_watch_speech_current_language(void);

// Drains the queued events as a JSON array of {"id", "type"}, type one of
// "started", "finished", "cancelled", "paused", "continued"; NULL when none
// are queued.
FWS_EXPORT
char* flutter_watch_speech_poll_events(void);

// Releases a string this file returned.
FWS_EXPORT
void flutter_watch_speech_release(char* string);

#endif  // FLUTTER_WATCH_SPEECH_FFI_H
