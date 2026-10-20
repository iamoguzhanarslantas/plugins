## 0.0.1

First version, staged: checked on the watchOS 27.0 Simulator, not yet on a
physical watch.

* `WatchSpeech`: one `AVSpeechSynthesizer` for the app. `speak` queues an
  utterance and completes with how it ended; `stop`, `pause` and `resume`;
  `isSpeaking` and `isPaused`; the installed `voices` and the
  `currentLanguage`; an `events` stream.
* `SpeechOptions`: language or voice, rate, pitch, volume, delays, and
  ducking other audio while speech plays.
* Native wakes Dart through one `NativeCallable.listener` carrying a signal
  kind; events come back as JSON through synchronous reads.
