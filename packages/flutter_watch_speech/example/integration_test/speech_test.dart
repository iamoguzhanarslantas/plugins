// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Against the real AVSpeechSynthesizer, on a watch Simulator: every symbol
// resolves, voices are listed, and an utterance plays to the end or stops.
//
// Run with:
//   flutter-watchos drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/speech_test.dart -d <watch-sim>

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_speech/flutter_watch_speech.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final WatchSpeech speech = WatchSpeech.instance;

  testWidgets('voices and the current language are listed',
      (WidgetTester _) async {
    expect(speech.voices, isNotEmpty);
    expect(speech.currentLanguage, isNotEmpty);
  });

  testWidgets('an utterance plays to the end', (WidgetTester _) async {
    final List<SpeechEventType> seen = <SpeechEventType>[];
    final StreamSubscription<SpeechEvent> sub =
        speech.events.listen((SpeechEvent e) => seen.add(e.type));
    final SpeechOutcome outcome = await speech
        .speak('Test.', options: const SpeechOptions(rate: 0.6))
        .timeout(const Duration(seconds: 20));
    expect(outcome, SpeechOutcome.finished);
    expect(seen.first, SpeechEventType.started);
    expect(seen.last, SpeechEventType.finished);
    await sub.cancel();
    expect(speech.isSpeaking, isFalse);
  });

  testWidgets('stop cancels what is speaking and what is queued',
      (WidgetTester _) async {
    final Future<SpeechOutcome> first = speech
        .speak('This sentence is long enough to be stopped before it ends.');
    final Future<SpeechOutcome> second = speech.speak('Never spoken.');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await speech.stop();
    expect(await first.timeout(const Duration(seconds: 10)),
        SpeechOutcome.cancelled);
    expect(await second.timeout(const Duration(seconds: 10)),
        SpeechOutcome.cancelled);
  });
}
