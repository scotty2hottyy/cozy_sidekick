import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/app.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sends a message and shows the provider reply', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('Say hi to your sidekick 👋'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('messageInput')), 'Hello');
    await tester.pump();
    expect(_button(tester, 'sendButton').onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Sidekick is typing…'), findsOneWidget);
    expect(_button(tester, 'sendButton').onPressed, isNull);
    await tester.pumpAndSettle();
    expect(find.text('Provider: Hello'), findsOneWidget);
    expect(find.text('Sidekick is typing…'), findsNothing);
  });

  testWidgets('settings button opens a settings screen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('AI Settings'), findsOneWidget);
    expect(find.text('API Credentials'), findsOneWidget);
    expect(find.text('Personality'), findsOneWidget);
  });

  testWidgets('speech partial results fill input and listening can stop', (
    tester,
  ) async {
    final speech = FakeSpeechService();
    await tester.pumpWidget(_app(speechService: speech));
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    speech.emitText('A partial thought');
    await tester.pump();
    expect(find.text('A partial thought'), findsOneWidget);
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    expect(speech.stopCalls, 1);
    expect(find.text('Listening…'), findsNothing);
  });

  testWidgets('speech permission denial is explained', (tester) async {
    final speech = FakeSpeechService(
      startState: SpeechServiceState.permissionDenied,
    );
    await tester.pumpWidget(_app(speechService: speech));
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    expect(find.textContaining('permissions are needed'), findsOneWidget);
  });
}

CozySidekickApp _app({SpeechService? speechService}) {
  final settings = InMemorySettingsStore();
  final keys = InMemoryApiKeyStore();
  final providers = <AiProviderType, AiProvider>{
    AiProviderType.openRouter: _FakeProvider(),
  };
  return CozySidekickApp(
    chatService: ChatService(settingsStore: settings, providers: providers),
    speechService: speechService ?? FakeSpeechService(),
    settingsStore: settings,
    keyStore: keys,
    connectionTester: ProviderConnectionService(providers: providers),
  );
}

class _FakeProvider implements AiProvider {
  @override
  Future<String> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return 'Provider: ${messages.last.text}';
  }
}

IconButton _button(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(Key(key)));

class FakeSpeechService implements SpeechService {
  FakeSpeechService({this.startState = SpeechServiceState.listening});
  final SpeechServiceState startState;
  SpeechServiceState _state = SpeechServiceState.idle;
  ValueChanged<String>? _onText;
  ValueChanged<SpeechServiceState>? _onStateChanged;
  int stopCalls = 0;

  @override
  SpeechServiceState get state => _state;

  @override
  Future<SpeechServiceState> startListening({
    required ValueChanged<String> onText,
    required ValueChanged<SpeechServiceState> onStateChanged,
  }) async {
    _onText = onText;
    _onStateChanged = onStateChanged;
    _state = startState;
    onStateChanged(_state);
    return _state;
  }

  void emitText(String text) => _onText?.call(text);

  @override
  Future<void> stopListening() async {
    stopCalls++;
    _state = SpeechServiceState.idle;
    _onStateChanged?.call(_state);
  }

  @override
  Future<void> dispose() async {}
}
