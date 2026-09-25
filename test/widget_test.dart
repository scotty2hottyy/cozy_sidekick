import 'dart:async';

import 'package:cozy_sidekick/services/chat_history_store.dart';

import 'fake_chat_history_store.dart';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/app.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/speech_service.dart';
import 'package:cozy_sidekick/widgets/formatted_reply.dart';
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

  testWidgets('formatting settings apply at startup and after Settings', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(
      messageFormatting: const MessageFormatting(formatReplies: false),
    );
    final history = FakeChatHistoryStore()
      ..messages = [
        ChatMessage.user('Hi'),
        ChatMessage.assistant('**Bold** hi'),
      ];
    await tester.pumpWidget(
      _app(historyStore: history, settingsStore: settings),
    );
    await tester.pumpAndSettle();
    expect(find.text('**Bold** hi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('formatRepliesSwitch')));
    await tester.pumpAndSettle();
    expect(settings.messageFormatting.formatReplies, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('**Bold** hi'), findsNothing);
    expect(find.byType(FormattedReply), findsOneWidget);
  });

  testWidgets('reasoning shows only while Show reasoning is on', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(showReasoning: true);
    final history = FakeChatHistoryStore()
      ..messages = [
        ChatMessage.user('Is 1001 prime?'),
        ChatMessage.assistant('No.', reasoning: 'Try dividing by 7.'),
      ];
    await tester.pumpWidget(
      _app(historyStore: history, settingsStore: settings),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('reasoningToggle'));
    expect(toggle, findsOneWidget);
    expect(find.text('Try dividing by 7.'), findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Try dividing by 7.'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Try dividing by 7.'), findsNothing);

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('showReasoningSwitch')));
    await tester.pumpAndSettle();
    expect(settings.showReasoning, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(toggle, findsNothing);
    expect(find.text('No.'), findsOneWidget);
    expect(history.messages.last.reasoning, 'Try dividing by 7.');
  });

  testWidgets('an open reply stays open while new messages arrive', (
    tester,
  ) async {
    final history = FakeChatHistoryStore()
      ..messages = [
        ChatMessage.user('Is 1001 prime?'),
        ChatMessage.assistant('No.', reasoning: 'Try dividing by 7.'),
      ];
    await tester.pumpWidget(
      _app(
        historyStore: history,
        settingsStore: InMemorySettingsStore(showReasoning: true),
        provider: _FakeProvider(reasoning: '1001 = 7 * 143.'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reasoningToggle')));
    await tester.pumpAndSettle();

    await _sendMessage(tester, 'Why?');

    expect(find.text('Provider: Why?'), findsOneWidget);
    expect(find.byKey(const Key('reasoningToggle')), findsNWidgets(2));
    expect(find.text('Try dividing by 7.'), findsOneWidget);
    expect(find.text('1001 = 7 * 143.'), findsNothing);
    expect(history.messages.last.reasoning, '1001 = 7 * 143.');
  });

  testWidgets('long reasoning opens below its row and closes back into place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longReasoning = List<String>.generate(
      80,
      (i) => 'Step $i of the thinking.',
    ).join('\n');
    final history = FakeChatHistoryStore()
      ..messages = [
        for (var i = 0; i < 8; i++) ...[
          ChatMessage.user('Question $i'),
          ChatMessage.assistant('Answer $i'),
        ],
        ChatMessage.user('Is 1001 prime?'),
        ChatMessage.assistant('No.', reasoning: longReasoning),
      ];
    await tester.pumpWidget(
      _app(
        historyStore: history,
        settingsStore: InMemorySettingsStore(showReasoning: true),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('reasoningToggle'));
    final list = tester.getRect(find.byType(ListView));
    final closedTop = tester.getTopLeft(toggle).dy;

    // The reply grows upward, so the list scrolls to keep its row in view.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final openTop = tester.getTopLeft(toggle).dy;
    expect(openTop, greaterThanOrEqualTo(list.top));
    expect(openTop, lessThan(closedTop));
    expect(
      tester.getTopLeft(find.textContaining('Step 0 of')).dy,
      greaterThan(openTop),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(toggle).dy, moreOrLessEquals(closedTop));
    expect(find.text('No.'), findsOneWidget);
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

  group('streaming', () {
    const thinking = 'Try dividing by 7.';
    const answer = 'No, 1001 is 7 times 143.';
    final toggle = find.byKey(const Key('reasoningToggle'));

    testWidgets('thinking streams under an open row until the answer starts', (
      tester,
    ) async {
      final history = FakeChatHistoryStore();
      final provider = _StreamingProvider();
      await tester.pumpWidget(
        _app(
          historyStore: history,
          settingsStore: InMemorySettingsStore(showReasoning: true),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();
      await _startMessage(tester, 'Is 1001 prime?');
      expect(find.text('Sidekick is typing…'), findsOneWidget);

      provider.add('', reasoning: 'Try dividing');
      await tester.pump(Duration.zero);
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.text('Try dividing'), findsOneWidget);
      expect(find.text('Sidekick is typing…'), findsNothing);
      expect(toggle, findsNothing);

      provider.add('', reasoning: thinking);
      await tester.pump(Duration.zero);
      expect(find.text(thinking), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Thinking… 2s'), findsOneWidget);

      // The reasoning collapses into the usual row, and the answer types out.
      provider.add('No,', reasoning: thinking);
      await tester.pump(Duration.zero);
      expect(find.textContaining('Thinking…'), findsNothing);
      expect(toggle, findsOneWidget);
      expect(find.text(thinking), findsNothing);
      expect(find.text('No,'), findsOneWidget);

      provider.add(answer, reasoning: thinking);
      await tester.pump(Duration.zero);
      expect(find.text(answer), findsOneWidget);
      expect(history.messages.map((m) => m.text), <String>['Is 1001 prime?']);

      await provider.finish();
      await tester.pumpAndSettle();
      expect(find.text(answer), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(history.saves, hasLength(2));
      expect(history.messages.last.text, answer);
      expect(history.messages.last.reasoning, thinking);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text(thinking), findsOneWidget);
    });

    testWidgets('reasoning opened while the answer arrives stays open', (
      tester,
    ) async {
      final provider = _StreamingProvider();
      await tester.pumpWidget(
        _app(
          settingsStore: InMemorySettingsStore(showReasoning: true),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();
      await _startMessage(tester, 'Is 1001 prime?');
      provider.add('No,', reasoning: thinking);
      await tester.pump(Duration.zero);

      await tester.tap(toggle);
      await tester.pump();
      expect(find.text(thinking), findsOneWidget);
      provider.add(answer, reasoning: thinking);
      await tester.pump(Duration.zero);
      expect(find.text(thinking), findsOneWidget);

      await provider.finish();
      await tester.pumpAndSettle();
      expect(find.text(thinking), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text(thinking), findsNothing);
    });

    testWidgets('with Show reasoning off, the typing line says thinking', (
      tester,
    ) async {
      final provider = _StreamingProvider();
      await tester.pumpWidget(_app(provider: provider));
      await tester.pumpAndSettle();
      await _startMessage(tester, 'Is 1001 prime?');
      expect(find.text('Sidekick is typing…'), findsOneWidget);

      provider.add('', reasoning: thinking);
      await tester.pump(Duration.zero);
      expect(find.text('Sidekick is thinking…'), findsOneWidget);
      expect(find.text('Sidekick is typing…'), findsNothing);
      expect(find.text('Thinking…'), findsNothing);
      expect(find.text(thinking), findsNothing);

      provider.add('No,', reasoning: thinking);
      await tester.pump(Duration.zero);
      expect(find.text('Sidekick is thinking…'), findsNothing);
      expect(find.text('No,'), findsOneWidget);
      expect(toggle, findsNothing);
      expect(find.text(thinking), findsNothing);

      await provider.finish();
      await tester.pumpAndSettle();
      expect(find.text('No,'), findsOneWidget);
      expect(toggle, findsNothing);
    });

    testWidgets('an error mid-reply removes it, and Retry asks again', (
      tester,
    ) async {
      final history = FakeChatHistoryStore();
      final provider = _StreamingProvider();
      await tester.pumpWidget(_app(historyStore: history, provider: provider));
      await tester.pumpAndSettle();
      await _startMessage(tester, 'Hello');
      provider.add('Half of a');
      await tester.pump(Duration.zero);
      expect(find.text('Half of a'), findsOneWidget);

      provider.fail(const NetworkException());
      await tester.pumpAndSettle();
      expect(find.text('Half of a'), findsNothing);
      expect(find.text('Hello'), findsOneWidget);
      expect(
        find.text("Can't connect. Check your internet connection."),
        findsOneWidget,
      );
      expect(history.messages.map((m) => m.text), <String>['Hello']);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
      await tester.pump();
      expect(provider.calls, 2);
      provider.add('Hi there!');
      await provider.finish();
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Hi there!'), findsOneWidget);
      expect(history.messages.map((m) => m.text), <String>[
        'Hello',
        'Hi there!',
      ]);
    });

    testWidgets('leaving the chat stops the reply', (tester) async {
      final history = FakeChatHistoryStore();
      final provider = _StreamingProvider();
      await tester.pumpWidget(_app(historyStore: history, provider: provider));
      await tester.pumpAndSettle();
      await _startMessage(tester, 'Hello');
      provider.add('Half of a');
      await tester.pump(Duration.zero);
      expect(provider.listening, isTrue);

      // An `await for` in an async* function only notices the cancel when
      // the next piece arrives, so that's when the request stops.
      await tester.pumpWidget(const SizedBox());
      provider.add('Half of a sentence');
      await tester.pump(Duration.zero);
      expect(provider.listening, isFalse);
      expect(history.messages.map((m) => m.text), <String>['Hello']);
    });
  });
}

Future<void> _sendMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('messageInput')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('sendButton')));
  await tester.pumpAndSettle();
}

/// Sends [text] without waiting for the reply.
Future<void> _startMessage(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('messageInput')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('sendButton')));
  await tester.pump();
}

CozySidekickApp _app({
  SpeechService? speechService,
  PersonalityStore? personalityStore,
  ChatHistoryStore? historyStore,
  AiProvider? provider,
  InMemorySettingsStore? settingsStore,
}) {
  final settings = settingsStore ?? InMemorySettingsStore();
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
  _FakeProvider({this.reasoning});
  final String? reasoning;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return AiReply(
      text: 'Provider: ${messages.last.text}',
      reasoning: reasoning,
    );
  }

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async* {
    yield await sendChat(systemPrompt: systemPrompt, messages: messages);
  }
}

/// Throws each of [errors] in turn, then replies like [_FakeProvider].
class _FlakyProvider implements AiProvider {
  _FlakyProvider(this.errors);
  final List<Object> errors;
  int calls = 0;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    calls++;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    return AiReply(text: 'Provider: ${messages.last.text}');
  }

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async* {
    yield await sendChat(systemPrompt: systemPrompt, messages: messages);
  }
}

/// Hands out the pieces of each reply as the test adds them.
///
/// After adding a piece, call `tester.pump(Duration.zero)`. It runs the
/// microtasks that carry the piece to the chat, then draws it. A plain
/// `pump()` only draws when a frame was already scheduled.
class _StreamingProvider implements AiProvider {
  StreamController<AiReply> _reply = StreamController<AiReply>();
  int calls = 0;

  /// Sends the reply so far.
  void add(String text, {String? reasoning}) =>
      _reply.add(AiReply(text: text, reasoning: reasoning));

  void fail(Object error) => _reply.addError(error);

  Future<void> finish() => _reply.close();

  /// Whether anyone is still waiting for the reply.
  bool get listening => _reply.hasListener;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) => streamChat(systemPrompt: systemPrompt, messages: messages).last;

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) {
    calls++;
    _reply = StreamController<AiReply>();
    return _reply.stream;
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
