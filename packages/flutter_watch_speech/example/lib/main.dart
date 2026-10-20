// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_watch_speech/flutter_watch_speech.dart';

void main() => runApp(const SpeechExampleApp());

/// A watch app that speaks lap announcements.
class SpeechExampleApp extends StatelessWidget {
  /// The example app.
  const SpeechExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const SpeechPage(),
      );
}

/// Speak, stop, and pick a voice.
class SpeechPage extends StatefulWidget {
  /// The one page.
  const SpeechPage({super.key});

  @override
  State<SpeechPage> createState() => _SpeechPageState();
}

class _SpeechPageState extends State<SpeechPage> {
  final WatchSpeech _speech = WatchSpeech.instance;
  late final List<SpeechVoice> _voices = _speech.voices;
  StreamSubscription<SpeechEvent>? _events;
  int _lap = 0;
  int _voice = -1; // the system's voice
  String _last = 'ready';

  @override
  void initState() {
    super.initState();
    _events = _speech.events.listen((SpeechEvent e) {
      setState(() => _last = '#${e.utteranceId} ${e.type.name}');
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _announce() async {
    _lap++;
    final SpeechVoice? voice = _voice < 0 ? null : _voices[_voice];
    await _speech.speak(
      'Lap $_lap. Pace five minutes thirty.',
      options: SpeechOptions(voiceIdentifier: voice?.identifier, rate: 0.45),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String voice = _voice < 0
        ? 'System (${_speech.currentLanguage})'
        : '${_voices[_voice].name} (${_voices[_voice].language})';
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 24),
        children: <Widget>[
          Text(_last,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          Text('${_voices.length} voices'),
          TextButton(
            onPressed: _voices.isEmpty
                ? null
                : () => setState(() {
                      _voice = _voice + 1 >= _voices.length ? -1 : _voice + 1;
                    }),
            child: Text(voice),
          ),
          FilledButton(onPressed: _announce, child: const Text('Announce lap')),
          TextButton(onPressed: _speech.stop, child: const Text('Stop')),
        ],
      ),
    );
  }
}
