import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/conversation_store.dart';
import 'package:cozy_sidekick/models/conversation.dart';

class FakeChatHistoryStore implements ConversationStore {
  ConversationState? state;
  List<ChatMessage> messages = [];
  @override
  Future<ConversationState> read() async {
    if (state != null) return state!;
    final initial = Conversation.empty().withMessages(await load());
    return ConversationState(conversations: [initial], activeId: initial.id);
  }

  @override
  Future<void> write(ConversationState value) async {
    state = value;
    final next = value.conversations
        .firstWhere((c) => c.id == value.activeId)
        .messages;
    if (next.isEmpty && messages.isNotEmpty) {
      await clear();
    } else if (next.isNotEmpty) {
      await save(next);
    }
  }

  final List<List<ChatMessage>> saves = [];
  int clearCalls = 0;
  Future<List<ChatMessage>> load() async => List.of(messages);
  Future<void> save(List<ChatMessage> value) async {
    messages = List.of(value);
    saves.add(List.of(value));
  }

  Future<void> clear() async {
    messages.clear();
    clearCalls++;
  }
}
