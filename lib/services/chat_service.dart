import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import 'conversation_store.dart';
import 'conversation_service.dart';
import 'personality_service.dart';
import 'settings_service.dart';
import 'generation_control.dart';

class ChatService {
  ChatService({
    required this.settingsStore,
    required this.personalityStore,
    required ConversationStore conversationStore,
    required Map<AiProviderType, AiProvider> providers,
  }) : conversations = ConversationService(conversationStore),
       _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final ConversationService conversations;
  final AppSettingsStore settingsStore;
  final PersonalityStore personalityStore;
  final Map<AiProviderType, AiProvider> _providers;

  /// Added to the system prompt while math is shown, so models use the
  /// delimiters that render safely. Small free models don't always follow it.
  static const String mathInstruction =
      r'Write math in LaTeX, using \( … \) for inline math and \[ … \] for '
      r"display equations. Don't use $ for math.";

  Future<List<ChatMessage>> loadHistory() async {
    await conversations.initialize();
    return conversations.active.messages;
  }

  Future<void> clearHistory() async {
    await conversations.initialize();
    await conversations.clear(conversations.active.id);
  }

  Future<ChatMessage> getReply(List<ChatMessage> conversation) =>
      streamReply(conversation).last;

  /// The assistant's reply while it arrives. Each event is the reply so far,
  /// and they all have the same `createdAt`. The finished reply is saved
  /// once, at the end, so a reply that fails leaves only the user's message.
  Stream<ChatMessage> streamReply(
    List<ChatMessage> conversation, {
    String? conversationId,
    GenerationControl? control,
  }) async* {
    if (conversation.isEmpty) {
      throw ArgumentError('conversation cannot be empty');
    }
    final snapshot = List<ChatMessage>.of(conversation);
    await conversations.initialize();
    final originId = conversationId ?? conversations.active.id;
    final revision = conversations.revision(originId);
    await conversations.saveMessages(
      originId,
      snapshot,
      expectedRevision: revision,
    );
    if (control?.isStopped ?? false) return;
    ChatMessage? message;
    try {
      final selected = await settingsStore.loadSelectedProvider();
      final provider = _providers[selected];
      if (provider == null) {
        throw ProviderConfigurationException(
          'No implementation registered for ${selected.name}',
        );
      }
      final personality = await personalityStore.loadActivePersonality();
      final formatting = await settingsStore.loadMessageFormatting();
      if (control?.isStopped ?? false) return;
      final replies = provider.streamChat(
        abortTrigger: control?.whenStopped,
        systemPrompt: formatting.rendersMath
            ? '${personality.systemPrompt}\n\n$mathInstruction'
            : personality.systemPrompt,
        messages: snapshot.length > 20
            ? snapshot.sublist(snapshot.length - 20)
            : snapshot,
      );
      final createdAt = DateTime.now();
      await for (final reply
          in control == null ? replies : control.untilStopped(replies)) {
        if (control?.isStopped ?? false) break;
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
    } catch (_) {
      if (!(control?.isStopped ?? false)) rethrow;
    }
    if ((control?.isStopped ?? false) &&
        (!control!.keepPartial ||
            message == null ||
            message.text.trim().isEmpty)) {
      return;
    }
    if (message == null) {
      throw const BadResponseException('The provider sent no reply');
    }
    await conversations.saveMessages(originId, <ChatMessage>[
      ...snapshot,
      message,
    ], expectedRevision: revision);
  }
}
