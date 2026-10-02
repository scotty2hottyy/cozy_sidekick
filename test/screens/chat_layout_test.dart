import 'dart:async';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/app.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/screens/settings_screen.dart';
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

import '../fake_chat_history_store.dart';

/// A Pixel-size phone in landscape, and the keyboard's height there.
const _landscape = Size(915, 412);
const _keyboard = 200.0;

void main() {
  // A Pixel-size phone and a small Android phone, each with a status bar.
  for (final (screen, keyboard) in <(Size, double)>[
    (_landscape, _keyboard),
    (const Size(800, 360), 180),
  ]) {
    testWidgets('landscape $screen with the keyboard up keeps the messages '
        'and Send in view', (tester) async {
      _setScreen(tester, screen);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      await tester.pumpWidget(_app(messages: 20));
      await tester.pumpAndSettle();

      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('messageInput')),
        'This is a long message, about two hundred and fifty letters. ' * 4,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final visibleBottom = screen.height - keyboard;
      final send = tester.getRect(find.byKey(const Key('sendButton')));
      expect(send.bottom, lessThanOrEqualTo(visibleBottom));
      final input = tester.getRect(find.byKey(const Key('messageInput')));
      expect(input.bottom, lessThanOrEqualTo(visibleBottom));
      // Room for at least a couple of lines of the conversation.
      final list = tester.getRect(find.byType(CustomScrollView));
      expect(list.top, greaterThanOrEqualTo(24));
      expect(list.height, greaterThan(40));
      expect(find.byKey(const Key('chatsButton')), findsNothing);
      expect(find.textContaining('Chat: '), findsNothing);
      expect(_input(tester).maxLines, 2);
    });
  }

  testWidgets('closing the keyboard brings the header back and keeps focus', (
    tester,
  ) async {
    _setScreen(tester, _landscape);
    await tester.pumpWidget(_app(messages: 20));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byKey(const Key('messageInput')));
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chatsButton')), findsNothing);
    expect(_inputHasFocus(tester), isTrue);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chatsButton')), findsOneWidget);
    expect(find.byKey(const Key('settingsButton')), findsOneWidget);
    expect(find.textContaining('Chat: '), findsOneWidget);
    expect(_input(tester).maxLines, 5);
    expect(_inputHasFocus(tester), isTrue);
  });

  for (final size in [_landscape, const Size(375, 800)]) {
    testWidgets('with the keyboard closed, $size shows the full layout', (
      tester,
    ) async {
      _setScreen(tester, size);
      await tester.pumpWidget(_app(messages: 20));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('chatsButton')), findsOneWidget);
      expect(find.byKey(const Key('settingsButton')), findsOneWidget);
      expect(find.textContaining('Chat: '), findsOneWidget);
      expect(_input(tester).maxLines, 5);
    });
  }

  // Split-screen on a small phone, and landscape at the largest display size.
  for (final size in const [Size(360, 300), Size(360, 280), Size(568, 319)]) {
    testWidgets('a short window $size without the keyboard keeps the header '
        'buttons and the messages', (tester) async {
      _setScreen(tester, size);
      await tester.pumpWidget(_app(messages: 20));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('messageInput')),
        'This is a long message, about two hundred and fifty letters. ' * 4,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('chatsButton')), findsOneWidget);
      expect(find.byKey(const Key('settingsButton')), findsOneWidget);
      expect(find.textContaining('Chat: '), findsNothing);
      expect(_input(tester).maxLines, 2);
      final list = tester.getRect(find.byType(CustomScrollView));
      expect(list.height, greaterThan(0));
    });
  }

  testWidgets('landscape keeps the chat clear of a side navigation bar', (
    tester,
  ) async {
    const size = Size(800, 360);
    const navigationBar = 48.0;
    _setScreen(tester, size);
    tester.view.padding = const FakeViewPadding(right: navigationBar);
    tester.view.viewPadding = const FakeViewPadding(right: navigationBar);
    await tester.pumpWidget(_app(messages: 20));
    await tester.pumpAndSettle();

    final safeRight = size.width - navigationBar;
    expect(
      tester.getRect(find.byKey(const Key('sendButton'))).right,
      lessThanOrEqualTo(safeRight),
    );
    expect(
      tester.getRect(find.byType(CustomScrollView)).right,
      lessThanOrEqualTo(safeRight),
    );
    expect(
      tester.getRect(find.byKey(const Key('settingsButton'))).right,
      lessThanOrEqualTo(safeRight),
    );
  });

  testWidgets('portrait without side insets keeps the full width', (
    tester,
  ) async {
    _setScreen(tester, const Size(375, 800));
    await tester.pumpWidget(_app(messages: 20));
    await tester.pumpAndSettle();

    final list = tester.getRect(find.byType(CustomScrollView));
    expect(list.left, 0);
    expect(list.right, 375);
    expect(tester.getRect(find.byKey(const Key('messageInput'))).left, 10);
  });

  testWidgets('the rename dialog shows its field in landscape with the '
      'keyboard up', (tester) async {
    _setScreen(tester, _landscape);
    final store = FakeChatHistoryStore()
      ..messages = <ChatMessage>[ChatMessage.user('Hello')];
    await tester.pumpWidget(_app(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chatsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('conversationTitleInput'));
    _expectShown(tester, field, visibleBottom: _landscape.height - _keyboard);
    expect(
      tester.getRect(find.text('Save')).bottom,
      lessThanOrEqualTo(_landscape.height - _keyboard),
    );

    await tester.enterText(field, 'Landscape chat');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.state!.conversations.single.title, 'Landscape chat');
  });

  testWidgets('each conversation menu has its own tooltip', (tester) async {
    await tester.pumpWidget(_app(messages: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chatsButton')));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Conversation actions'), findsOneWidget);
    expect(find.byTooltip('Show menu'), findsNothing);
  });

  testWidgets('header buttons work with large text', (tester) async {
    _setScreen(tester, const Size(375, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_app(messages: 2));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byKey(const Key('chatsButton'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('newChatButton')), findsOneWidget);
    tester.state<ScaffoldState>(find.byType(Scaffold)).closeDrawer();
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('settingsButton'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}

void _setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

TextField _input(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('messageInput')));

bool _inputHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('messageInput')),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

/// Expects the text line of [field] to be drawn inside its scroll view and
/// above [visibleBottom], so the user can see what they type.
void _expectShown(
  WidgetTester tester,
  Finder field, {
  required double visibleBottom,
}) {
  final line = tester.getRect(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  final viewport = tester.getRect(
    find.ancestor(of: field, matching: find.byType(Scrollable)).first,
  );
  expect(line.height, greaterThan(0));
  expect(line.top, greaterThanOrEqualTo(viewport.top));
  expect(line.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(line.bottom, lessThanOrEqualTo(visibleBottom));
}

CozySidekickApp _app({int messages = 0, FakeChatHistoryStore? store}) {
  final history =
      store ??
      (FakeChatHistoryStore()
        ..messages = List.generate(
          messages,
          (i) => ChatMessage.user('Message $i'),
        ));
  final settings = InMemorySettingsStore();
  final personalities = InMemoryPersonalityStore();
  final providers = <AiProviderType, AiProvider>{
    AiProviderType.openRouter: _QuietProvider(),
  };
  return CozySidekickApp(
    chatService: ChatService(
      conversationStore: history,
      settingsStore: settings,
      personalityStore: personalities,
      providers: providers,
    ),
    speechService: _FakeSpeechService(),
    textToSpeechService: _FakeTextToSpeechService(),
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

/// Never answers. These tests only look at the layout.
class _QuietProvider implements AiProvider {
  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) => Completer<AiReply>().future;

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) => const Stream<AiReply>.empty();
}

class _FakeSpeechService implements SpeechService {
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

class _FakeTextToSpeechService implements TextToSpeechService {
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
