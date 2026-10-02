import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/app.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/model_list_service.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/speech_service.dart';
import 'package:cozy_sidekick/services/text_to_speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fake_chat_history_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final (error, logged) in <(Object, String)>[
    (
      const ModelNotAvailableException(
        'HTTP 403 model_not_found: Project `proj_abc` does not have access',
      ),
      'Chat failed: ModelNotAvailableException',
    ),
    // dart:io used to put a key it couldn't send in its error.
    (
      const FormatException('Invalid HTTP header field value: "Bearer FAKE"'),
      'Unexpected chat error: FormatException',
    ),
  ]) {
    testWidgets('the log names only the type of ${error.runtimeType}', (
      tester,
    ) async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        await tester.pumpWidget(_app(_FlakyProvider(<Object>[error])));
        await tester.pumpAndSettle();
        await _sendMessage(tester, 'Hello');
      } finally {
        debugPrint = original;
      }

      expect(logs, <String>[logged]);
    });
  }
}

Future<void> _sendMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('messageInput')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('sendButton')));
  await tester.pumpAndSettle();
}

CozySidekickApp _app(AiProvider provider) {
  final settings = InMemorySettingsStore();
  final personalities = InMemoryPersonalityStore();
  final providers = <AiProviderType, AiProvider>{
    AiProviderType.openRouter: provider,
  };
  return CozySidekickApp(
    chatService: ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: settings,
      personalityStore: personalities,
      providers: providers,
    ),
    speechService: _NoSpeech(),
    textToSpeechService: _NoTextToSpeech(),
    settingsStore: settings,
    personalityStore: personalities,
    keyStore: InMemoryApiKeyStore(),
    connectionTester: ProviderConnectionService(
      providers: providers,
      settingsStore: settings,
    ),
    modelLister: ModelListService(providers: providers),
  );
}

/// Throws each of [errors] in turn, then echoes the last message.
class _FlakyProvider implements AiProvider {
  _FlakyProvider(this.errors);
  final List<Object> errors;
  int calls = 0;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async {
    calls++;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    return AiReply(text: 'Provider: ${messages.last.text}');
  }

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async* {
    yield await sendChat(systemPrompt: systemPrompt, messages: messages);
  }
}

class _NoSpeech implements SpeechService {
  @override
  SpeechServiceState get state => SpeechServiceState.idle;

  @override
  Future<List<SpeechLanguage>> locales() async => const <SpeechLanguage>[];

  @override
  Future<SpeechServiceState> startListening({
    required ValueChanged<String> onText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<SpeechServiceState> onStateChanged,
    String? localeId,
    bool sendWhenDone = false,
  }) async => SpeechServiceState.idle;

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> dispose() async {}
}

class _NoTextToSpeech implements TextToSpeechService {
  @override
  Future<List<SpeechVoice>> voices() async => const <SpeechVoice>[];

  @override
  Future<void> speak(
    String text, {
    String? voiceName,
    String? voiceLocale,
    double rate = 0.5,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
