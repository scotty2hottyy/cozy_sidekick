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

  Future<ChatMessage> getReply(List<ChatMessage> conversation) =>
      streamReply(conversation).last;

  /// The assistant's reply while it arrives. Each event is the reply so far,
  /// and they all have the same `createdAt`. The finished reply is saved
  /// once, at the end, so a reply that fails leaves only the user's message.
  Stream<ChatMessage> streamReply(List<ChatMessage> conversation) async* {
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
    final replies = provider.streamChat(
      systemPrompt: formatting.rendersMath
          ? '${personality.systemPrompt}\n\n$mathInstruction'
          : personality.systemPrompt,
      messages: snapshot.length > 20
          ? snapshot.sublist(snapshot.length - 20)
          : snapshot,
    );
    final createdAt = DateTime.now();
    ChatMessage? message;
    await for (final reply in replies) {
      // Reasoning is kept even while Show reasoning is off, so turning it on
      // later shows it for earlier replies too.
      message = ChatMessage(
        role: MessageRole.assistant,
        text: reply.text,
        createdAt: createdAt,
        reasoning: reply.reasoning,
      );
      yield message;
    }
    if (message == null) {
      throw const BadResponseException('The provider sent no reply');
    }
    await historyStore.save(<ChatMessage>[...snapshot, message]);
  }
}
