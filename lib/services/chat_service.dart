import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import 'chat_history_store.dart';
import 'settings_service.dart';

class ChatService {
  ChatService({
    required this.settingsStore,
    required this.historyStore,
    required Map<AiProviderType, AiProvider> providers,
    this.systemPrompt =
        'You are Cozy Sidekick, a helpful conversational assistant.',
  }) : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final ChatHistoryStore historyStore;
  final AppSettingsStore settingsStore;

  final Map<AiProviderType, AiProvider> _providers;
  final String systemPrompt;

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
    final reply = await provider.sendChat(
      systemPrompt: systemPrompt,
      messages: snapshot.length > 20
          ? snapshot.sublist(snapshot.length - 20)
          : snapshot,
    );
    final message = ChatMessage.assistant(reply);
    await historyStore.save(<ChatMessage>[...snapshot, message]);
    return message;
  }
}
