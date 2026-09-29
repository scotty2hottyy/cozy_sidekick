import 'dart:async';

import 'package:cozy_sidekick/models/speech_settings.dart';
import 'package:cozy_sidekick/screens/voice_speech_screen.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/speech_service.dart';
import 'package:cozy_sidekick/services/text_to_speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads languages without starting the microphone', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    final speech = _FakeSpeechService(
      languages: const <SpeechLanguage>[
        SpeechLanguage(id: 'fr-FR', name: 'French (France)'),
        SpeechLanguage(id: 'en-US', name: 'English (United States)'),
      ],
    );
    final tts = _FakeTextToSpeechService();
    await tester.pumpWidget(_screen(settings, speech, tts));
    await tester.pumpAndSettle();

    expect(speech.localeCalls, 1);
    expect(speech.startCalls, 0);
    expect(find.text("Phone's language"), findsOneWidget);
    await tester.tap(find.byKey(const Key('speechLanguageDropdown')));
    await tester.pumpAndSettle();
    expect(find.text('French (France)'), findsOneWidget);
  });

  testWidgets('a language query timeout falls back to phone language', (
    tester,
  ) async {
    final speech = _FakeSpeechService(
      localesCompleter: Completer<List<SpeechLanguage>>(),
    );
    await tester.pumpWidget(
      _screen(InMemorySettingsStore(), speech, _FakeTextToSpeechService()),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text("Phone's language"), findsOneWidget);
    expect(speech.startCalls, 0);
  });

  testWidgets(
    'settings save immediately and sample uses selected voice/speed',
    (tester) async {
      final settings = InMemorySettingsStore();
      final tts = _FakeTextToSpeechService(
        availableVoices: const <SpeechVoice>[
          SpeechVoice(name: 'Zed', locale: 'fr-FR'),
          SpeechVoice(name: 'Amelie', locale: 'fr-FR'),
          SpeechVoice(name: 'English Voice', locale: 'en-US'),
        ],
      );
      await tester.pumpWidget(
        _screen(
          settings,
          _FakeSpeechService(
            languages: const <SpeechLanguage>[
              SpeechLanguage(id: 'fr-FR', name: 'French (France)'),
            ],
          ),
          tts,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('speechLanguageDropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French (France)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speechAutoSendSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speechVoiceDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Amelie (fr-FR)'), findsOneWidget);
      expect(find.text('English Voice (en-US)'), findsNothing);
      await tester.tap(find.text('Amelie (fr-FR)').last);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('speechRateSlider')),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playSpeechSample')));
      await tester.pumpAndSettle();

      expect(settings.speechSettings.languageId, 'fr-FR');
      expect(settings.speechSettings.sendWhenDone, isTrue);
      expect(settings.speechSettings.readAloud, ReadAloudMode.always);
      expect(settings.speechSettings.voiceName, 'Amelie');
      expect(settings.speechSettings.rate, isNot(0.5));
      expect(tts.lastVoiceName, 'Amelie');
      expect(tts.lastVoiceLocale, 'fr-FR');
      expect(tts.lastRate, settings.speechSettings.rate);
    },
  );
}

Widget _screen(
  AppSettingsStore settings,
  SpeechService speech,
  TextToSpeechService tts,
) => MaterialApp(
  home: VoiceSpeechScreen(
    settingsStore: settings,
    speechService: speech,
    textToSpeechService: tts,
  ),
);

class _FakeSpeechService implements SpeechService {
  _FakeSpeechService({
    this.languages = const <SpeechLanguage>[],
    this.localesCompleter,
  });

  final List<SpeechLanguage> languages;
  final Completer<List<SpeechLanguage>>? localesCompleter;
  int localeCalls = 0;
  int startCalls = 0;

  @override
  SpeechServiceState get state => SpeechServiceState.idle;

  @override
  Future<List<SpeechLanguage>> locales() {
    localeCalls++;
    return localesCompleter?.future ??
        Future<List<SpeechLanguage>>.value(languages);
  }

  @override
  Future<SpeechServiceState> startListening({
    required ValueChanged<String> onText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<SpeechServiceState> onStateChanged,
    String? localeId,
    bool sendWhenDone = false,
  }) async {
    startCalls++;
    return SpeechServiceState.listening;
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeTextToSpeechService implements TextToSpeechService {
  _FakeTextToSpeechService({this.availableVoices = const <SpeechVoice>[]});

  final List<SpeechVoice> availableVoices;
  String? lastVoiceName;
  String? lastVoiceLocale;
  double? lastRate;

  @override
  Future<List<SpeechVoice>> voices() async => availableVoices;

  @override
  Future<void> speak(
    String text, {
    String? voiceName,
    String? voiceLocale,
    double rate = 0.5,
  }) async {
    lastVoiceName = voiceName;
    lastVoiceLocale = voiceLocale;
    lastRate = rate;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
