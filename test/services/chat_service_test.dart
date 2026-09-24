import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the currently selected provider for every reply', () async {
    final settings = InMemorySettingsStore();
    final openRouter = _FakeProvider('router reply');
    final custom = _FakeProvider('custom reply');
    final service = ChatService(
      settingsStore: settings,
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
  });

  test('rejects an empty conversation', () {
    final service = ChatService(
      settingsStore: InMemorySettingsStore(),
      providers: <AiProviderType, AiProvider>{},
    );
    expect(() => service.getReply(<ChatMessage>[]), throwsArgumentError);
  });
}

class _FakeProvider implements AiProvider {
  _FakeProvider(this.reply);
  final String reply;
  List<ChatMessage> lastMessages = <ChatMessage>[];

  @override
  Future<String> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    lastMessages = messages;
    return reply;
  }
}
