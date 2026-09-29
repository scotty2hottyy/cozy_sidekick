import 'dart:async';

import '../fake_chat_history_store.dart';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/models/personality.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reply stays with originating chat when active chat changes during streaming', () async {
    final provider = _ControlledProvider();
    final service = ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: {AiProviderType.openRouter: provider},
    );
    await service.loadHistory();
    final origin = service.conversations.active.id;
    final done = service.streamReply([
      ChatMessage.user('Only in A'),
    ], conversationId: origin).toList();
    await provider.started.future;
    await service.conversations.create();
    final other = service.conversations.active.id;
    provider.replies.add(const AiReply(text: 'Answer for A'));
    await provider.replies.close();
    await done;
    expect(service.conversations.active.id, other);
    expect(service.conversations.active.messages, isEmpty);
    await service.conversations.select(origin);
    expect(service.conversations.active.messages.map((m) => m.text), [
      'Only in A',
      'Answer for A',
    ]);
    expect(provider.context.single.text, 'Only in A');
  });
  test('deleting origin during streaming cannot recreate it', () async {
    final provider = _ControlledProvider();
    final service = ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: {AiProviderType.openRouter: provider},
    );
    await service.loadHistory();
    final origin = service.conversations.active.id;
    final done = service.streamReply([
      ChatMessage.user('Delete me'),
    ], conversationId: origin).toList();
    await provider.started.future;
    await service.conversations.delete(origin);
    provider.replies.add(const AiReply(text: 'Late answer'));
    await provider.replies.close();
    await done;
    expect(
      service.conversations.conversations.any((c) => c.id == origin),
      isFalse,
    );
    expect(service.conversations.active.messages, isEmpty);
  });

  test('restores and clears saved history', () async {
    final history = FakeChatHistoryStore()
      ..messages = [ChatMessage.user('saved')];
    final service = ChatService(
      conversationStore: history,
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: {},
    );
    expect(await service.loadHistory(), history.messages);
    await service.clearHistory();
    expect(await service.loadHistory(), isEmpty);
    expect(history.clearCalls, 1);
  });
  test(
    'saves user before request and assistant after, limits context to 20',
    () async {
      final history = FakeChatHistoryStore();
      final provider = _FakeProvider(
        'answer',
        beforeReply: () {
          expect(history.saves, hasLength(1));
          expect(history.messages, hasLength(25));
        },
      );
      final service = ChatService(
        conversationStore: history,
        settingsStore: InMemorySettingsStore(),
        personalityStore: InMemoryPersonalityStore(),
        providers: {AiProviderType.openRouter: provider},
      );
      final messages = List.generate(25, (i) => ChatMessage.user('$i'));
      final reply = await service.getReply(messages);
      expect(provider.lastMessages, messages.sublist(5));
      expect(history.saves, hasLength(2));
      expect(history.messages, [...messages, reply]);
      expect(messages, hasLength(25));
    },
  );
  test('provider failure still retains user message', () async {
    final history = FakeChatHistoryStore();
    final service = ChatService(
      conversationStore: history,
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: {
        AiProviderType.openRouter: _FakeProvider(
          '',
          beforeReply: () => throw const MissingApiKeyException(),
        ),
      },
    );
    final messages = [ChatMessage.user('keep me')];
    await expectLater(
      service.getReply(messages),
      throwsA(isA<MissingApiKeyException>()),
    );
    expect(history.messages, messages);
    expect(history.saves, hasLength(1));
  });
  test('uses the currently selected provider for every reply', () async {
    final settings = InMemorySettingsStore();
    final personalities = InMemoryPersonalityStore();
    final openRouter = _FakeProvider('router reply');
    final custom = _FakeProvider('custom reply');
    final service = ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: settings,
      personalityStore: personalities,
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: openRouter,
        AiProviderType.customServer: custom,
      },
    );
    expect(
      (await service.getReply(<ChatMessage>[ChatMessage.user('Hi')])).text,
      'router reply',
    );
    await settings.saveSelectedProvider(AiProviderType.customServer);
    expect(
      (await service.getReply(<ChatMessage>[ChatMessage.user('Hi')])).text,
      'custom reply',
    );
    expect(custom.lastMessages.single.text, 'Hi');

    final curious = Personality.presets.first;
    await personalities.savePersonalities([
      ...await personalities.loadPersonalities(),
      curious,
    ]);
    await personalities.setActivePersonality(curious.id);
    await service.getReply(<ChatMessage>[ChatMessage.user('Who are you?')]);
    expect(
      custom.lastSystemPrompt,
      '${curious.systemPrompt}\n\n${ChatService.mathInstruction}',
    );
  });

  test('asks each provider for the model saved for it', () async {
    final settings = InMemorySettingsStore(
      models: <AiProviderType, String>{AiProviderType.openAi: 'gpt-6-sol'},
    );
    final openRouter = _FakeProvider('router reply');
    final openAi = _FakeProvider('OpenAI reply');
    final service = ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: settings,
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: openRouter,
        AiProviderType.openAi: openAi,
      },
    );
    final hi = <ChatMessage>[ChatMessage.user('Hi')];

    // Nothing saved for OpenRouter, so it uses its default.
    await service.getReply(hi);
    expect(openRouter.lastModel, isNull);

    await settings.saveSelectedProvider(AiProviderType.openAi);
    await service.getReply(hi);
    expect(openAi.lastModel, 'gpt-6-sol');

    // A change applies to the next reply.
    await settings.saveModel(AiProviderType.openAi, null);
    await service.getReply(hi);
    expect(openAi.lastModel, isNull);
  });

  test('asks for LaTeX delimiters only while math is shown', () async {
    final settings = InMemorySettingsStore();
    final personalities = InMemoryPersonalityStore();
    final provider = _FakeProvider('reply');
    final service = ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: settings,
      personalityStore: personalities,
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: provider,
      },
    );
    final prompt = (await personalities.loadActivePersonality()).systemPrompt;
    final hi = <ChatMessage>[ChatMessage.user('Hi')];

    await service.getReply(hi);
    expect(provider.lastSystemPrompt, startsWith(prompt));
    expect(provider.lastSystemPrompt, endsWith(ChatService.mathInstruction));

    for (final off in const <MessageFormatting>[
      MessageFormatting(showMath: false),
      MessageFormatting(formatReplies: false),
    ]) {
      await settings.saveMessageFormatting(off);
      await service.getReply(hi);
      expect(provider.lastSystemPrompt, prompt, reason: '$off');
    }
  });

  test('saves reasoning with the reply even while it is hidden', () async {
    final history = FakeChatHistoryStore();
    final settings = InMemorySettingsStore();
    final service = ChatService(
      conversationStore: history,
      settingsStore: settings,
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: _FakeProvider(
          'No.',
          reasoning: 'Try dividing by 7.',
        ),
      },
    );
    expect(await settings.loadShowReasoning(), isFalse);

    final reply = await service.getReply(<ChatMessage>[
      ChatMessage.user('Is 1001 prime?'),
    ]);

    expect(reply.text, 'No.');
    expect(reply.reasoning, 'Try dividing by 7.');
    expect(history.messages.last, reply);
  });

  test('streams the reply so far and saves it once, at the end', () async {
    final history = FakeChatHistoryStore();
    const pieces = <AiReply>[
      AiReply(text: '', reasoning: 'Try'),
      AiReply(text: '', reasoning: 'Try dividing by 7.'),
      AiReply(text: 'No,', reasoning: 'Try dividing by 7.'),
      AiReply(text: 'No, 1001 = 7 * 143.', reasoning: 'Try dividing by 7.'),
    ];
    final service = ChatService(
      conversationStore: history,
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: _FakeProvider.streaming(pieces),
      },
    );
    final question = ChatMessage.user('Is 1001 prime?');

    final replies = <ChatMessage>[];
    await for (final reply in service.streamReply(<ChatMessage>[question])) {
      // Nothing but the question is saved while the reply arrives.
      expect(history.messages, <ChatMessage>[question]);
      replies.add(reply);
    }

    expect(
      replies.map(
        (reply) => AiReply(text: reply.text, reasoning: reply.reasoning),
      ),
      pieces,
    );
    expect(
      replies.every((reply) => reply.role == MessageRole.assistant),
      isTrue,
    );
    expect(replies.map((reply) => reply.createdAt).toSet(), hasLength(1));
    expect(history.saves, hasLength(2));
    expect(history.messages, <ChatMessage>[question, replies.last]);
  });

  test('a reply that fails while it arrives saves only the question', () async {
    final history = FakeChatHistoryStore();
    final service = ChatService(
      conversationStore: history,
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: _FakeProvider.streaming(const <AiReply>[
          AiReply(text: 'No,'),
        ], error: const NetworkException()),
      },
    );
    final question = ChatMessage.user('Is 1001 prime?');

    await expectLater(
      service.streamReply(<ChatMessage>[question]),
      emitsInOrder(<Object>[
        isA<ChatMessage>().having((reply) => reply.text, 'text', 'No,'),
        emitsError(isA<NetworkException>()),
      ]),
    );
    expect(history.messages, <ChatMessage>[question]);
    expect(history.saves, hasLength(1));
  });

  test('a provider that sends nothing is a bad response', () async {
    final history = FakeChatHistoryStore();
    final service = ChatService(
      conversationStore: history,
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{
        AiProviderType.openRouter: _FakeProvider.streaming(const <AiReply>[]),
      },
    );
    await expectLater(
      service.getReply(<ChatMessage>[ChatMessage.user('Hi')]),
      throwsA(isA<BadResponseException>()),
    );
    expect(history.saves, hasLength(1));
  });

  test('rejects an empty conversation', () {
    final service = ChatService(
      conversationStore: FakeChatHistoryStore(),
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{},
    );
    expect(() => service.getReply(<ChatMessage>[]), throwsArgumentError);
  });
}

class _FakeProvider implements AiProvider {
  _FakeProvider(String text, {String? reasoning, this.beforeReply})
    : pieces = <AiReply>[AiReply(text: text, reasoning: reasoning)],
      error = null;

  /// Streams each of [pieces], then fails with [error] if there is one.
  _FakeProvider.streaming(this.pieces, {this.error}) : beforeReply = null;

  final void Function()? beforeReply;
  final List<AiReply> pieces;
  final Object? error;
  List<ChatMessage> lastMessages = <ChatMessage>[];
  String? lastSystemPrompt;
  String? lastModel;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? model,
  }) => streamChat(systemPrompt: systemPrompt, messages: messages).last;

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? model,
  }) async* {
    beforeReply?.call();
    lastMessages = messages;
    lastSystemPrompt = systemPrompt;
    lastModel = model;
    yield* Stream<AiReply>.fromIterable(pieces);
    if (error != null) throw error!;
  }
}

class _ControlledProvider implements AiProvider {
  final started = Completer<void>();
  final replies = StreamController<AiReply>();
  List<ChatMessage> context = [];
  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? model,
  }) {
    context = messages;
    started.complete();
    return replies.stream;
  }

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? model,
  }) => streamChat(systemPrompt: systemPrompt, messages: messages).last;
}
