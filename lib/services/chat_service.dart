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

  /// Added to the system prompt while math is shown, so models use the
  /// delimiters that render safely. Small free models don't always follow it.
  static const String mathInstruction =
      r'Write math in LaTeX, using \( … \) for inline math and \[ … \] for '
      r"display equations. Don't use $ for math.";

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
    final formatting = await settingsStore.loadMessageFormatting();
    final reply = await provider.sendChat(
      systemPrompt: formatting.rendersMath
          ? '${personality.systemPrompt}\n\n$mathInstruction'
          : personality.systemPrompt,
      messages: snapshot.length > 20
          ? snapshot.sublist(snapshot.length - 20)
          : snapshot,
    );
    // Reasoning is kept even while Show reasoning is off, so turning it on
    // later shows it for earlier replies too.
    final message = ChatMessage.assistant(
      reply.text,
      reasoning: reply.reasoning,
    );
    await historyStore.save(<ChatMessage>[...snapshot, message]);
    return message;
  }
}
