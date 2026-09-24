import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/chat_history_store.dart';

class FakeChatHistoryStore implements ChatHistoryStore {
  List<ChatMessage> messages = [];
  final List<List<ChatMessage>> saves = [];
  int clearCalls = 0;
  @override
  Future<List<ChatMessage>> load() async => List.of(messages);
  @override
  Future<void> save(List<ChatMessage> value) async {
    messages = List.of(value);
    saves.add(List.of(value));
  }

  @override
  Future<void> clear() async {
    messages.clear();
    clearCalls++;
  }
}
