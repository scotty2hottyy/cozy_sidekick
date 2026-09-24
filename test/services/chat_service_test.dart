import '../fake_chat_history_store.dart';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores and clears saved history', () async {
    final history = FakeChatHistoryStore()
      ..messages = [ChatMessage.user('saved')];
    final service = ChatService(
      historyStore: history,
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
        historyStore: history,
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
      historyStore: history,
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
      historyStore: FakeChatHistoryStore(),
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

    await personalities.setActivePersonality('curious-guide');
    await service.getReply(<ChatMessage>[ChatMessage.user('Who are you?')]);
    expect(
      custom.lastSystemPrompt,
      'You are a curious guide. Help explore ideas with clear explanations '
      'and useful questions.',
    );
  });

  test('rejects an empty conversation', () {
    final service = ChatService(
      historyStore: FakeChatHistoryStore(),
      settingsStore: InMemorySettingsStore(),
      personalityStore: InMemoryPersonalityStore(),
      providers: <AiProviderType, AiProvider>{},
    );
    expect(() => service.getReply(<ChatMessage>[]), throwsArgumentError);
  });
}

class _FakeProvider implements AiProvider {
  _FakeProvider(this.reply, {this.beforeReply});
  final void Function()? beforeReply;
  final String reply;
  List<ChatMessage> lastMessages = <ChatMessage>[];
  String? lastSystemPrompt;

  @override
  Future<String> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    beforeReply?.call();
    lastMessages = messages;
    lastSystemPrompt = systemPrompt;
    return reply;
  }
}
