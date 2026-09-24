import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import 'settings_service.dart';

class ChatService {
  ChatService({
    required this.settingsStore,
    required Map<AiProviderType, AiProvider> providers,
    this.systemPrompt =
        'You are Cozy Sidekick, a helpful conversational assistant.',
  }) : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final AppSettingsStore settingsStore;
  final Map<AiProviderType, AiProvider> _providers;
  final String systemPrompt;

  Future<ChatMessage> getReply(List<ChatMessage> conversation) async {
    if (conversation.isEmpty) {
      throw ArgumentError('conversation cannot be empty');
    }
    final selected = await settingsStore.loadSelectedProvider();
    final provider = _providers[selected];
    if (provider == null) {
      throw ProviderConfigurationException(
        'No implementation registered for ${selected.name}',
      );
    }
    final reply = await provider.sendChat(
      systemPrompt: systemPrompt,
      messages: conversation,
    );
    return ChatMessage.assistant(reply);
  }
}
