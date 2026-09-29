import 'dart:async';

import 'package:cozy_sidekick/services/conversation_store.dart';

import 'fake_chat_history_store.dart';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/app.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/model_list_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/speech_service.dart';
import 'package:cozy_sidekick/services/text_to_speech_service.dart';
import 'package:cozy_sidekick/widgets/formatted_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final partial in [false, true]) {
    testWidgets(
      'Stop ${partial ? "keeps partial text" : "before first chunk"} and permits another request',
      (tester) async {
        final history = FakeChatHistoryStore();
        final provider = _StreamingProvider();
        await tester.pumpWidget(
          _app(conversationStore: history, provider: provider),
        );
        await tester.pumpAndSettle();
        await _startMessage(tester, 'First question');
        if (partial) {
          provider.add('Partial answer');
          await tester.pump(Duration.zero);
        }
        final oldStream = provider._reply;
        await tester.tap(find.byKey(const Key('stopGenerationButton')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('stopGenerationButton')), findsNothing);
        expect(
          history.messages.map((m) => m.text),
          partial ? ['First question', 'Partial answer'] : ['First question'],
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('messageInput')))
              .enabled,
          isTrue,
        );
        await _startMessage(tester, 'Second question');
        oldStream.add(const AiReply(text: 'Unwanted late answer'));
        unawaited(oldStream.close());
        await tester.pump(Duration.zero);
        expect(find.text('Unwanted late answer'), findsNothing);
        provider.add('Second answer');
        await tester.pump(Duration.zero);
        await provider.finish();
        await tester.pumpAndSettle();
        expect(history.messages.last.text, 'Second answer');
        expect(
          history.messages.where((m) => m.text == 'Partial answer').length,
          partial ? 1 : 0,
        );
      },
    );
  }
  testWidgets('Stop during reasoning does not save an empty assistant reply', (
    tester,
  ) async {
    final history = FakeChatHistoryStore();
    final provider = _StreamingProvider();
    await tester.pumpWidget(
      _app(
        conversationStore: history,
        provider: provider,
        settingsStore: InMemorySettingsStore(showReasoning: true),
      ),
    );
    await tester.pumpAndSettle();
    await _startMessage(tester, 'Think');
    provider.add('', reasoning: 'Working on it');
    await tester.pump(Duration.zero);
    await tester.tap(find.byKey(const Key('stopGenerationButton')));
    await tester.pumpAndSettle();
    expect(history.messages.single.text, 'Think');
    expect(find.text('Working on it'), findsNothing);
    unawaited(provider.finish());
    await tester.pump();
  });

  for (final fails in [false, true]) {
    testWidgets(
      'reading position survives reasoning growth and ${fails ? "failure" : "completion"}',
      (tester) async {
        final history = FakeChatHistoryStore()
          ..messages = List.generate(30, (i) => ChatMessage.user('Anchor $i'));
        final provider = _StreamingProvider();
        await tester.pumpWidget(
          _app(
            conversationStore: history,
            provider: provider,
            settingsStore: InMemorySettingsStore(showReasoning: true),
          ),
        );
        await tester.pumpAndSettle();
        await _startMessage(tester, 'Think about this');
        provider.add('', reasoning: 'First thought');
        await tester.pump(Duration.zero);
        final viewport = find.byType(CustomScrollView);
        await tester.drag(viewport, const Offset(0, 350));
        // Thinking has a timer, so don't wait for all animations to settle.
        await tester.pump(const Duration(seconds: 1));
        final bounds = tester.getRect(viewport);
        String? anchor;
        for (var i = 0; i < 30; i++) {
          final finder = find.text('Anchor $i');
          if (finder.evaluate().isNotEmpty &&
              tester.getTopLeft(finder).dy > bounds.top + 30 &&
              tester.getTopLeft(finder).dy < bounds.bottom - 80) {
            anchor = 'Anchor $i';
            break;
          }
        }
        expect(anchor, isNotNull);
        final before = tester.getTopLeft(find.text(anchor!)).dy;
        provider.add(
          '',
          reasoning: List.generate(35, (i) => 'Thought $i').join('\n'),
        );
        await tester.pump(Duration.zero);
        expect(tester.getTopLeft(find.text(anchor)).dy, closeTo(before, 1));
        if (fails) {
          provider.fail(const NetworkException());
        } else {
          provider.add('Final answer', reasoning: 'Finished thinking');
          await tester.pump(Duration.zero);
          expect(tester.getTopLeft(find.text(anchor)).dy, closeTo(before, 1));
          await provider.finish();
        }
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.text(anchor)).dy, closeTo(before, 1));
        expect(find.byKey(const Key('jumpToLatestButton')), findsOneWidget);
      },
    );
  }

  testWidgets('changing conversation resets scroll and hides jump control', (
    tester,
  ) async {
    final history = FakeChatHistoryStore()
      ..messages = List.generate(30, (i) => ChatMessage.user('Old $i'));
    await tester.pumpWidget(_app(conversationStore: history));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jumpToLatestButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chatsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newChatButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jumpToLatestButton')), findsNothing);
    expect(find.text('Say hi to your sidekick 👋'), findsOneWidget);
  });

  testWidgets(
    'stream growth preserves older message position and jump resumes following',
    (tester) async {
      final history = FakeChatHistoryStore()
        ..messages = List.generate(30, (i) => ChatMessage.user('History $i'));
      final provider = _StreamingProvider();
      await tester.pumpWidget(
        _app(
          conversationStore: history,
          provider: provider,
          settingsStore: InMemorySettingsStore(
            messageFormatting: const MessageFormatting(formatReplies: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _startMessage(tester, 'New question');
      provider.add('Short answer');
      await tester.pump(Duration.zero);
      final viewport = find.byType(CustomScrollView);
      final scrollable = find
          .descendant(of: viewport, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      await tester.drag(viewport, const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('jumpToLatestButton')), findsOneWidget);
      final bounds = tester.getRect(viewport);
      String? anchor;
      for (var i = 0; i < 30; i++) {
        final text = find.text('History $i');
        if (text.evaluate().isNotEmpty) {
          final y = tester.getTopLeft(text).dy;
          if (y > bounds.top + 30 && y < bounds.bottom - 60) {
            anchor = 'History $i';
            break;
          }
        }
      }
      expect(anchor, isNotNull);
      final before = tester.getTopLeft(find.text(anchor!)).dy;
      for (final lines in [20, 40, 60]) {
        provider.add(List.generate(lines, (i) => 'Answer line $i').join('\n'));
        await tester.pump(Duration.zero);
        expect(tester.getTopLeft(find.text(anchor)).dy, closeTo(before, 1));
      }
      await tester.tap(find.byKey(const Key('jumpToLatestButton')));
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(0, 0.1));
      expect(find.byKey(const Key('jumpToLatestButton')), findsNothing);
      provider.add(List.generate(80, (i) => 'Answer line $i').join('\n'));
      await tester.pump(Duration.zero);
      expect(position.pixels, closeTo(0, 0.1));
      await provider.finish();
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(0, 0.1));
    },
  );

  testWidgets(
    'jump button appears on old history and stays hidden for short chats',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('jumpToLatestButton')), findsNothing);
      final history = FakeChatHistoryStore()
        ..messages = List.generate(30, (i) => ChatMessage.user('Older $i'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(conversationStore: history));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('jumpToLatestButton')), findsOneWidget);
      await tester.tap(find.byKey(const Key('jumpToLatestButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('jumpToLatestButton')), findsNothing);
    },
  );

  testWidgets('rename and confirmed individual/all deletion from drawer', (
    tester,
  ) async {
    final store = FakeChatHistoryStore()
      ..messages = [ChatMessage.user('Original')];
    await tester.pumpWidget(_app(conversationStore: store));
    await tester.pumpAndSettle();
    final originalId = store.state?.activeId;
    // The initial read is enough to show the chat, even before a write.
    Future<void> openDrawer() async {
      await tester.tap(find.byKey(const Key('chatsButton')));
      await tester.pumpAndSettle();
    }

    await openDrawer();
    final actionMenu = find.byWidgetPredicate(
      (w) =>
          w is PopupMenuButton<String> &&
          w.key.toString().contains('conversation-actions-'),
    );
    await tester.tap(actionMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('conversationTitleInput')),
      '  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a title'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('conversationTitleInput')),
      'Renamed chat',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.state!.conversations.single.title, 'Renamed chat');
    final id = store.state!.activeId!;
    if (originalId != null) expect(id, originalId);
    await openDrawer();
    await tester.tap(find.byKey(const Key('newChatButton')));
    await tester.pumpAndSettle();
    Future<void> askDeleteOriginal() async {
      await openDrawer();
      await tester.tap(find.byKey(ValueKey('conversation-actions-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    await askDeleteOriginal();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.state!.conversations, hasLength(2));
    await askDeleteOriginal();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.state!.conversations, hasLength(1));
    expect(store.state!.conversations.any((c) => c.id == id), isFalse);
    await openDrawer();
    await tester.tap(find.byKey(const Key('newChatButton')));
    await tester.pumpAndSettle();
    final before = store.state!.conversations.map((c) => c.id).toList();
    Future<void> askDeleteAll() async {
      await openDrawer();
      await tester.tap(find.text('Delete all conversations'));
      await tester.pumpAndSettle();
    }

    await askDeleteAll();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.state!.conversations.map((c) => c.id), before);
    await askDeleteAll();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.state!.conversations, hasLength(1));
    expect(before, isNot(contains(store.state!.activeId)));
    expect(find.text('Say hi to your sidekick 👋'), findsOneWidget);
  });

  testWidgets(
    'new chat isolates messages and drawer restores previous chat after restart',
    (tester) async {
      final store = FakeChatHistoryStore();
      final provider = _FakeProvider();
      await tester.pumpWidget(
        _app(conversationStore: store, provider: provider),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('messageInput')),
        'First question',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sendButton')));
      await tester.pumpAndSettle();
      final firstId = store.state!.activeId!;
      await tester.tap(find.byKey(const Key('chatsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('newChatButton')));
      await tester.pumpAndSettle();
      expect(find.text('First question'), findsNothing);
      expect(find.text('Say hi to your sidekick 👋'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('messageInput')),
        'Second question',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sendButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chatsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('conversation-$firstId')));
      await tester.pumpAndSettle();
      expect(find.text('First question'), findsOneWidget);
      expect(find.text('Second question'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(conversationStore: store));
      await tester.pumpAndSettle();
      expect(find.text('First question'), findsOneWidget);
      expect(store.state!.activeId, firstId);
    },
  );

  testWidgets('sent conversation is restored after screen recreation', (
    tester,
  ) async {
    final history = FakeChatHistoryStore();
    await tester.pumpWidget(_app(conversationStore: history));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('messageInput')),
      'Remember this',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pump();
    expect(history.messages.single.text, 'Remember this');
    expect(_button(tester, 'chatsButton').onPressed, isNull);
    expect(_button(tester, 'settingsButton').onPressed, isNull);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.pumpAndSettle();
    expect(history.messages.map((m) => m.text), [
      'Remember this',
      'Provider: Remember this',
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(conversationStore: history));
    await tester.pumpAndSettle();
    expect(find.text('Remember this'), findsOneWidget);
    expect(find.text('Provider: Remember this'), findsOneWidget);
  });

  testWidgets('loads history before enabling composer and preserves order', (
    tester,
  ) async {
    final history = _DelayedHistoryStore();
    await tester.pumpWidget(_app(conversationStore: history));
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
    'Voice & Speech opens from Settings without starting the microphone',
    (tester) async {
      final speech = FakeSpeechService();
      await tester.pumpWidget(_app(speechService: speech));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();
      expect(find.text('Customize tone and instructions'), findsOneWidget);
      await tester.ensureVisible(find.text('Voice & Speech'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice & Speech'));
      await tester.pumpAndSettle();

      expect(find.text('Voice & Speech'), findsOneWidget);
      expect(speech.startCalls, 0);
    },
  );

  testWidgets(
    'cancel preserves history, confirmed clear survives screen restart',
    (tester) async {
      final history = FakeChatHistoryStore()
        ..messages = [ChatMessage.user('Saved message')];
      await tester.pumpWidget(_app(conversationStore: history));
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
      await tester.pumpWidget(_app(conversationStore: history));
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
    expect(_button(tester, 'stopGenerationButton').onPressed, isNotNull);
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

  testWidgets('the model picked in AI Settings answers the next message', (
    tester,
  ) async {
    final provider = _FakeProvider();
    await tester.pumpWidget(_app(provider: provider));
    await tester.pumpAndSettle();
    await _sendMessage(tester, 'Hi');
    expect(provider.lastModel, isNull);

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Settings'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DropdownMenu<String>),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai/gpt-6-luna').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _sendMessage(tester, 'Hello');
    expect(provider.lastModel, 'openai/gpt-6-luna');
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
      _app(conversationStore: history, settingsStore: settings),
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
      _app(conversationStore: history, settingsStore: settings),
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
        conversationStore: history,
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
        conversationStore: history,
        settingsStore: InMemorySettingsStore(showReasoning: true),
      ),
    );
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('reasoningToggle'));
    final list = tester.getRect(find.byType(CustomScrollView));
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
    await tester.pumpWidget(
      _app(conversationStore: history, provider: provider),
    );
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

  testWidgets('model errors open AI Settings, then ask again on return', (
    tester,
  ) async {
    final provider = _FlakyProvider(<Object>[
      const ModelNotAvailableException('HTTP 404 model_not_found'),
    ]);
    await tester.pumpWidget(_app(provider: provider));
    await tester.pumpAndSettle();
    await _sendMessage(tester, 'Hello');
    expect(
      find.text(
        "This model isn't available for your account. Check the model or "
        "your provider's settings.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pumpAndSettle();
    expect(find.text('AI Settings'), findsOneWidget);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);
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
          conversationStore: history,
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
      await tester.pumpWidget(
        _app(conversationStore: history, provider: provider),
      );
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
      await tester.pumpWidget(
        _app(conversationStore: history, provider: provider),
      );
      await tester.pumpAndSettle();
      await _startMessage(tester, 'Hello');
      provider.add('Half of a');
      await tester.pump(Duration.zero);
      expect(provider.listening, isTrue);

      // Leaving cancels promptly; a later piece cannot update saved history.
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
  ConversationStore? conversationStore,
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
      conversationStore: conversationStore ?? FakeChatHistoryStore(),
      settingsStore: settings,
      personalityStore: personalities,
      providers: providers,
    ),
    speechService: speechService ?? FakeSpeechService(),
    textToSpeechService: FakeTextToSpeechService(),
    settingsStore: settings,
    personalityStore: personalities,
    keyStore: keys,
    connectionTester: ProviderConnectionService(
      providers: providers,
      settingsStore: settings,
    ),
    modelLister: ModelListService(providers: providers),
  );
}

class _FakeProvider implements AiProvider {
  _FakeProvider({this.reasoning});
  final String? reasoning;
  String? lastModel;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async {
    lastModel = model;
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
    Future<void>? abortTrigger,
    String? model,
  }) async* {
    yield await sendChat(
      systemPrompt: systemPrompt,
      messages: messages,
      model: model,
    );
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
    Future<void>? abortTrigger,
    String? model,
  }) => streamChat(systemPrompt: systemPrompt, messages: messages).last;

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
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
  List<SpeechLanguage> languages = const <SpeechLanguage>[];
  ValueChanged<String>? _onText;
  ValueChanged<String>? _onFinalResult;
  ValueChanged<SpeechServiceState>? _onStateChanged;
  int stopCalls = 0;
  int startCalls = 0;
  String? lastLocaleId;
  bool lastSendWhenDone = false;

  @override
  Future<List<SpeechLanguage>> locales() async => languages;

  @override
  SpeechServiceState get state => _state;

  @override
  Future<SpeechServiceState> startListening({
    required ValueChanged<String> onText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<SpeechServiceState> onStateChanged,
    String? localeId,
    bool sendWhenDone = false,
  }) async {
    startCalls++;
    _onText = onText;
    _onFinalResult = onFinalResult;
    _onStateChanged = onStateChanged;
    lastLocaleId = localeId;
    lastSendWhenDone = sendWhenDone;
    _state = startState;
    onStateChanged(_state);
    return _state;
  }

  void emitText(String text) => _onText?.call(text);
  void emitFinal(String text) => _onFinalResult?.call(text);

  @override
  Future<void> stopListening() async {
    stopCalls++;
    _state = SpeechServiceState.idle;
    _onStateChanged?.call(_state);
  }

  @override
  Future<void> dispose() async {}
}

class FakeTextToSpeechService implements TextToSpeechService {
  List<SpeechVoice> availableVoices = const <SpeechVoice>[];
  String? lastVoiceName;
  String? lastVoiceLocale;
  double? lastRate;
  String? lastText;
  int stopCalls = 0;

  @override
  Future<List<SpeechVoice>> voices() async => availableVoices;

  @override
  Future<void> speak(
    String text, {
    String? voiceName,
    String? voiceLocale,
    double rate = 0.5,
  }) async {
    lastText = text;
    lastVoiceName = voiceName;
    lastVoiceLocale = voiceLocale;
    lastRate = rate;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}
}

class _DelayedHistoryStore extends FakeChatHistoryStore {
  final loaded = Completer<List<ChatMessage>>();
  @override
  Future<List<ChatMessage>> load() => loaded.future;
}
