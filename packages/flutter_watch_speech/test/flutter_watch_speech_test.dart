// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests. The synthesizer is replaced with a fake that queues
// the events the native header documents, so the queueing, the completion
// of each speak, and the event stream are checked off-device.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_speech/flutter_watch_speech.dart';

class _FakeBackend implements SpeechBackend {
  final List<String> spoken = <String>[];
  final List<Map<String, Object?>> options = <Map<String, Object?>>[];
  final List<Map<String, Object?>> queued = <Map<String, Object?>>[];
  int _next = 1;
  bool speaking = false;
  bool paused = false;
  void Function(int kind)? handler;

  /// Queues an event and signals, as the synthesizer delegate does.
  void event(int id, String type) {
    queued.add(<String, Object?>{'id': id, 'type': type});
    handler?.call(1);
  }

  @override
  int speak(String text, String optionsJson) {
    spoken.add(text);
    options.add((jsonDecode(optionsJson) as Map<Object?, Object?>)
        .cast<String, Object?>());
    speaking = true;
    return _next++;
  }

  @override
  bool stop() {
    final bool was = speaking;
    speaking = false;
    return was;
  }

  @override
  bool pause() {
    paused = speaking;
    return speaking;
  }

  @override
  bool resume() {
    final bool was = paused;
    paused = false;
    return was;
  }

  @override
  bool isSpeaking() => speaking;
  @override
  bool isPaused() => paused;
  @override
  String voices() => jsonEncode(<Object?>[
        <String, Object?>{
          'identifier': 'com.apple.voice.compact.en-US.Samantha',
          'name': 'Samantha',
          'language': 'en-US',
          'quality': 'default',
        },
        <String, Object?>{
          'identifier': 'com.apple.voice.enhanced.tr-TR.Yelda',
          'name': 'Yelda',
          'language': 'tr-TR',
          'quality': 'enhanced',
        },
      ]);
  @override
  String currentLanguage() => 'en-GB';
  @override
  String? pollEvents() {
    if (queued.isEmpty) {
      return null;
    }
    final String json = jsonEncode(queued);
    queued.clear();
    return json;
  }

  @override
  void setSignalHandler(void Function(int kind)? h) => handler = h;
}

void main() {
  late _FakeBackend fake;
  late WatchSpeech speech;

  setUp(() {
    fake = _FakeBackend();
    speech = WatchSpeech.withBackend(fake);
  });

  test('speak completes when its utterance finishes', () async {
    bool done = false;
    final Future<SpeechOutcome> spoken =
        speech.speak('One kilometre').then((SpeechOutcome o) {
      done = true;
      return o;
    });
    fake.event(1, 'started');
    await pumpEventQueue();
    expect(done, isFalse);
    fake.event(1, 'finished');
    expect(await spoken, SpeechOutcome.finished);
    expect(fake.handler, isNull, reason: 'nothing waits any more');
  });

  test('queued utterances complete one by one', () async {
    final Future<SpeechOutcome> first = speech.speak('one');
    final Future<SpeechOutcome> second = speech.speak('two');
    fake.event(1, 'finished');
    expect(await first, SpeechOutcome.finished);
    fake.event(2, 'cancelled');
    expect(await second, SpeechOutcome.cancelled);
    expect(fake.spoken, <String>['one', 'two']);
  });

  test('an utterance that ended inside the call still completes', () async {
    fake.queued.add(<String, Object?>{'id': 1, 'type': 'finished'});
    expect(await speech.speak('quick'), SpeechOutcome.finished);
  });

  test('empty text completes at once without speaking', () async {
    expect(await speech.speak('   '), SpeechOutcome.finished);
    expect(fake.spoken, isEmpty);
  });

  test('options reach native, and defaults fill the rest', () async {
    unawaited(speech.speak('a',
        options: const SpeechOptions(
          language: 'tr-TR',
          rate: 0.4,
          pitch: 1.2,
          volume: 0.8,
          preUtteranceDelay: Duration(milliseconds: 250),
          duckOthers: false,
        )));
    expect(fake.options.single, <String, Object?>{
      'language': 'tr-TR',
      'voice': null,
      'rate': 0.4,
      'pitch': 1.2,
      'volume': 0.8,
      'preDelay': 0.25,
      'postDelay': null,
      'duckOthers': false,
    });
    speech.defaultOptions = const SpeechOptions(voiceIdentifier: 'v');
    unawaited(speech.speak('b'));
    expect(fake.options.last['voice'], 'v');
    expect(fake.options.last['duckOthers'], isTrue);
  });

  test('events reach every listener in order', () async {
    final List<SpeechEvent> a = <SpeechEvent>[];
    final List<SpeechEvent> b = <SpeechEvent>[];
    final StreamSubscription<SpeechEvent> subA = speech.events.listen(a.add);
    final StreamSubscription<SpeechEvent> subB = speech.events.listen(b.add);
    unawaited(speech.speak('x'));
    fake
      ..event(1, 'started')
      ..event(1, 'paused')
      ..event(1, 'continued')
      ..event(1, 'finished');
    await pumpEventQueue();
    expect(a.map((SpeechEvent e) => e.type), <SpeechEventType>[
      SpeechEventType.started,
      SpeechEventType.paused,
      SpeechEventType.continued,
      SpeechEventType.finished,
    ]);
    expect(b, hasLength(4));
    await subA.cancel();
    await subB.cancel();
    expect(fake.handler, isNull);
  });

  test('stop, pause and resume report what they changed', () async {
    expect(await speech.stop(), isFalse);
    unawaited(speech.speak('x'));
    expect(speech.isSpeaking, isTrue);
    expect(await speech.pause(), isTrue);
    expect(speech.isPaused, isTrue);
    expect(await speech.resume(), isTrue);
    expect(await speech.stop(), isTrue);
    expect(speech.isSpeaking, isFalse);
  });

  test('voices and the current language are native', () {
    final List<SpeechVoice> voices = speech.voices;
    expect(
        voices.map((SpeechVoice v) => v.name), <String>['Samantha', 'Yelda']);
    expect(voices[1].quality, SpeechVoiceQuality.enhanced);
    expect(voices[1].language, 'tr-TR');
    expect(speech.currentLanguage, 'en-GB');
  });

  test('registerWith does nothing and does not throw', () {
    expect(WatchSpeech.registerWith, returnsNormally);
  });
}
