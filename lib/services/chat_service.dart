import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import 'chat_history_store.dart';
import 'personality_service.dart';
import 'settings_service.dart';

class ChatService {
  ChatService({
    required this.settingsStore,
    required this.personalityStore,
    required this.historyStore,
    required Map<AiProviderType, AiProvider> providers,
  }) : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final ChatHistoryStore historyStore;
  final AppSettingsStore settingsStore;
  final PersonalityStore personalityStore;
  final Map<AiProviderType, AiProvider> _providers;

  Future<List<ChatMessage>> loadHistory() => historyStore.load();
  Future<void> clearHistory() => historyStore.clear();

  Future<ChatMessage> getReply(List<ChatMessage> conversation) async {
    if (conversation.isEmpty) {
      throw ArgumentError('conversation cannot be empty');
    }
    final snapshot = List<ChatMessage>.of(conversation);
    await historyStore.save(snapshot);
    final selected = await settingsStore.loadSelectedProvider();
    final provider = _providers[selected];
    if (provider == null) {
      throw ProviderConfigurationException(
        'No implementation registered for ${selected.name}',
      );
    }
    final personality = await personalityStore.loadActivePersonality();
    final reply = await provider.sendChat(
      systemPrompt: personality.systemPrompt,
      messages: snapshot.length > 20
          ? snapshot.sublist(snapshot.length - 20)
          : snapshot,
    );
    final message = ChatMessage.assistant(reply);
    await historyStore.save(<ChatMessage>[...snapshot, message]);
    return message;
  }
}
