import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import 'personality_service.dart';
import 'settings_service.dart';

class ChatService {
  ChatService({
    required this.settingsStore,
    required this.personalityStore,
    required Map<AiProviderType, AiProvider> providers,
  }) : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final AppSettingsStore settingsStore;
  final PersonalityStore personalityStore;
  final Map<AiProviderType, AiProvider> _providers;

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
    final personality = await personalityStore.loadActivePersonality();
    final reply = await provider.sendChat(
      systemPrompt: personality.systemPrompt,
      messages: conversation,
    );
    return ChatMessage.assistant(reply);
  }
}
