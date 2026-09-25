import 'dart:async';

import 'package:cozy_sidekick/services/chat_history_store.dart';

import 'fake_chat_history_store.dart';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/app.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/speech_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sent conversation is restored after screen recreation', (
    tester,
  ) async {
    final history = FakeChatHistoryStore();
    await tester.pumpWidget(_app(historyStore: history));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('messageInput')),
      'Remember this',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pump();
    expect(history.messages.single.text, 'Remember this');
    expect(_button(tester, 'settingsButton').onPressed, isNull);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.pumpAndSettle();
    expect(history.messages.map((m) => m.text), [
      'Remember this',
      'Provider: Remember this',
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(historyStore: history));
    await tester.pumpAndSettle();
    expect(find.text('Remember this'), findsOneWidget);
    expect(find.text('Provider: Remember this'), findsOneWidget);
  });

  testWidgets('loads history before enabling composer and preserves order', (
    tester,
  ) async {
    final history = _DelayedHistoryStore();
    await tester.pumpWidget(_app(historyStore: history));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_button(tester, 'sendButton').onPressed, isNull);
    expect(_button(tester, 'microphoneButton').onPressed, isNull);
    history.loaded.complete([
      ChatMessage.user('First saved'),
      ChatMessage.assistant('Second saved'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('First saved'), findsOneWidget);
    expect(find.text('Second saved'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('First saved')).dy,
      lessThan(tester.getTopLeft(find.text('Second saved')).dy),
    );
  });
  testWidgets(
    'cancel preserves history, confirmed clear survives screen restart',
    (tester) async {
      final history = FakeChatHistoryStore()
        ..messages = [ChatMessage.user('Saved message')];
      await tester.pumpWidget(_app(historyStore: history));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chat History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat History'));
      await tester.pumpAndSettle();
      Future<void> openClear() async {
        await tester.tap(find.text('Clear chat'));
        await tester.pumpAndSettle();
      }

      await openClear();
      expect(
        find.text("Delete all messages? This can't be undone."),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(history.clearCalls, 0);
      expect(history.messages.single.text, 'Saved message');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Saved message'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Chat History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat History'));
      await tester.pumpAndSettle();
      await openClear();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(history.clearCalls, 1);
      expect(history.messages, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Saved message'), findsNothing);
      expect(find.text('Say hi to your sidekick 👋'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(historyStore: history));
      await tester.pumpAndSettle();
      expect(find.text('Say hi to your sidekick 👋'), findsOneWidget);
    },
  );

  testWidgets('sends a message and shows the provider reply', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('microphoneButton')));
    await tester.pump();
    expect(find.textContaining('permissions are needed'), findsOneWidget);
  });

  testWidgets('personality screen loads and saves a custom default', (
    tester,
  ) async {
    final personalities = InMemoryPersonalityStore();
    await tester.pumpWidget(_app(personalityStore: personalities));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personality'));
    await tester.pumpAndSettle();
    expect(find.text('Cozy Sidekick'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const Key('addPersonalityButton')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addPersonalityButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('personalityNameField')),
      'Focused Helper',
    );
    await tester.enterText(
      find.byKey(const Key('personalityPromptField')),
      'Give concise, practical answers.',
    );
    await tester.tap(find.text('Use when app opens'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Focused Helper'), findsWidgets);
    expect(
      (await personalities.loadPersonalities())
          .singleWhere((p) => p.isDefault)
          .name,
      'Focused Helper',
    );
  });

  testWidgets('network error explains itself and re-enables sending', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(provider: _FlakyProvider(<Object>[const NetworkException()])),
    );
    await tester.pumpAndSettle();
    await _sendMessage(tester, 'Hello');
    expect(
      find.text("Can't connect. Check your internet connection."),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Sidekick is typing…'), findsNothing);
    await tester.enterText(find.byKey(const Key('messageInput')), 'Again');
    await tester.pump();
    expect(_button(tester, 'sendButton').onPressed, isNotNull);

    // The SnackBar must not stay over the composer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('retry asks again without repeating the user message', (
    tester,
  ) async {
    final history = FakeChatHistoryStore();
    final provider = _FlakyProvider(<Object>[const NetworkException()]);
    await tester.pumpWidget(_app(historyStore: history, provider: provider));
    await tester.pumpAndSettle();
    await _sendMessage(tester, 'Hello');
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pumpAndSettle();
    expect(provider.calls, 2);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Provider: Hello'), findsOneWidget);
    expect(history.messages.map((m) => m.text), ['Hello', 'Provider: Hello']);
  });

  testWidgets('key errors open credentials, then ask again on return', (
    tester,
  ) async {
    final provider = _FlakyProvider(<Object>[const MissingApiKeyException()]);
    await tester.pumpWidget(_app(provider: provider));
    await tester.pumpAndSettle();
    await _sendMessage(tester, 'Hello');
    expect(
      find.text('Add a key in Settings to start chatting.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.text('API Credentials'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(provider.calls, 2);
    expect(find.text('Provider: Hello'), findsOneWidget);
  });

  testWidgets('unexpected errors never show the raw error', (tester) async {
    await tester.pumpWidget(
      _app(provider: _FlakyProvider(<Object>[StateError('internal detail')])),
    );
    await tester.pumpAndSettle();
    await _sendMessage(tester, 'Hello');
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal detail'), findsNothing);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
  });
}

Future<void> _sendMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('messageInput')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('sendButton')));
  await tester.pumpAndSettle();
}

CozySidekickApp _app({
  SpeechService? speechService,
  PersonalityStore? personalityStore,
  ChatHistoryStore? historyStore,
  AiProvider? provider,
}) {
  final settings = InMemorySettingsStore();
  final personalities = personalityStore ?? InMemoryPersonalityStore();
  final keys = InMemoryApiKeyStore();
  final providers = <AiProviderType, AiProvider>{
    AiProviderType.openRouter: provider ?? _FakeProvider(),
  };
  return CozySidekickApp(
    chatService: ChatService(
      historyStore: historyStore ?? FakeChatHistoryStore(),
      settingsStore: settings,
      personalityStore: personalities,
      providers: providers,
    ),
    speechService: speechService ?? FakeSpeechService(),
    settingsStore: settings,
    personalityStore: personalities,
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

/// Throws each of [errors] in turn, then replies like [_FakeProvider].
class _FlakyProvider implements AiProvider {
  _FlakyProvider(this.errors);
  final List<Object> errors;
  int calls = 0;

  @override
  Future<String> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    calls++;
    if (errors.isNotEmpty) throw errors.removeAt(0);
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

class _DelayedHistoryStore extends FakeChatHistoryStore {
  final loaded = Completer<List<ChatMessage>>();
  @override
  Future<List<ChatMessage>> load() => loaded.future;
}
