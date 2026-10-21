# flutter_watch_speech

Text to speech for Flutter apps on Apple Watch: `AVSpeechSynthesizer` over
dart:ffi, for apps built with
[flutter-watchos](https://github.com/flutterwatch/flutter-watchos). Speak
lap times, turn-by-turn cues or anything else, in any installed voice, with
other audio ducked while it plays.

This is a first-party package, not a port: [`flutter_tts`](https://pub.dev/packages/flutter_tts)
is a single method-channel plugin with no platform interface, so a watchOS
package cannot implement it, and method channels do not run on watchOS.
The API follows flutter_tts's shape where it can.

## Installation

```yaml
dependencies:
  flutter_watch_speech: ^0.0.1
```

## Usage

```dart
final WatchSpeech speech = WatchSpeech.instance;

final SpeechOutcome outcome = await speech.speak(
  'One kilometre. Pace five thirty.',
  options: const SpeechOptions(language: 'en-US', rate: 0.45),
);

speech.events.listen((SpeechEvent e) => print(e));
await speech.stop();
```

## What it does

| Member | What it does |
|---|---|
| `speak(text, {options})` | Queues an utterance and completes with `finished` or `cancelled` once it ends |
| `stop()` / `pause()` / `resume()` | Stop at once (cancelling everything queued), pause at the next word, continue |
| `isSpeaking` / `isPaused` | The synthesizer's state |
| `voices` / `currentLanguage` | The installed voices, and the system's default speech language |
| `events` | `started`, `finished`, `cancelled`, `paused`, `continued` for each utterance |
| `defaultOptions` | What `speak` uses for options it is not given |

`SpeechOptions` takes a `language` or a `voiceIdentifier`, a `rate` from 0
to 1 across the synthesizer's range, a `pitch` from 0.5 to 2, a `volume`,
delays before and after, and `duckOthers` (on by default): while speech plays
the audio session is in the voice-prompt mode and other audio is lowered,
then raised again after the last utterance.

## Limits worth knowing

- Speech plays through the watch speaker, or connected Bluetooth headphones.
- The first utterance after launch can take a moment while the voice loads.
- Utterances queue; to interrupt, `stop()` and then `speak`.
- Word-by-word progress (`willSpeakRangeOfSpeechString`) is not reported.

## Status

| Aspect | Result |
|---|---|
| Host unit tests (`flutter test`) | ✅ pass (native backend faked) |
| Integration test (`example/integration_test`) | ✅ passes on the watchOS 27.0 Simulator: voices listed, an utterance played to the end, one paused and continued, a queue stopped |
| Physical watch | not yet checked: the speaker, Bluetooth headphones and ducking need a device |

## License

The FlutterWatch Authors under a BSD-3-Clause license. See `LICENSE` for the full text.
