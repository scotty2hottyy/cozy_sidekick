import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'conversation_store.dart';

/// Serializes read-modify-write operations; only publishes successful writes.
class ConversationService {
  ConversationService(this.store);
  final ConversationStore store;
  ConversationState? _state;
  Future<void> _tail = Future.value();
  final Map<String, int> _revisions = {};
  List<Conversation> get conversations => _state?.conversations ?? const [];
  String? get activeId => _state?.activeId;
  Conversation get active => conversations.firstWhere((c) => c.id == activeId);
  int revision(String id) => _revisions[id] ?? 0;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    if (_state != null) return;
    var state = await store.read();
    if (state.conversations.isEmpty) {
      final fresh = Conversation.empty();
      state = ConversationState(conversations: [fresh], activeId: fresh.id);
      await store.write(state);
    }
    _state = state;
  }

  Future<void> initialize() => _serial(_load);
  Future<void> _commit(List<Conversation> chats, String activeId) async {
    final next = ConversationState(conversations: chats, activeId: activeId);
    await store.write(next);
    _state = next;
  }

  Future<void> create() => _serial(() async {
    await _load();
    final chat = Conversation.empty();
    await _commit([...conversations, chat], chat.id);
  });
  Future<void> select(String id) => _serial(() async {
    await _load();
    if (!conversations.any((c) => c.id == id)) {
      throw StateError('Chat no longer exists');
    }
    await _commit(conversations, id);
  });
  Future<void> rename(String id, String title) => _serial(() async {
    await _load();
    await _commit([
      for (final c in conversations) c.id == id ? c.renamed(title) : c,
    ], activeId!);
  });
  Future<void> saveMessages(
    String id,
    List<ChatMessage> messages, {
    int? expectedRevision,
  }) {
    final snapshot = List<ChatMessage>.of(messages);
    return _serial(() async {
      await _load();
      if (!conversations.any((c) => c.id == id) ||
          (expectedRevision != null && revision(id) != expectedRevision)) {
        return;
      }
      await _commit([
        for (final c in conversations)
          c.id == id ? c.withMessages(snapshot) : c,
      ], activeId!);
    });
  }

  Future<void> clear(String id) => _serial(() async {
    await _load();
    await _commit([
      for (final c in conversations) c.id == id ? c.withMessages([]) : c,
    ], activeId!);
    _revisions[id] = revision(id) + 1;
  });
  Future<void> delete(String id) => _serial(() async {
    await _load();
    final remaining = conversations.where((c) => c.id != id).toList();
    if (remaining.isEmpty) remaining.add(Conversation.empty());
    await _commit(remaining, activeId == id ? remaining.last.id : activeId!);
    _revisions[id] = revision(id) + 1;
  });
  Future<void> deleteAll() => _serial(() async {
    await _load();
    final oldIds = conversations.map((c) => c.id).toList();
    final fresh = Conversation.empty();
    await _commit([fresh], fresh.id);
    for (final id in oldIds) {
      _revisions[id] = revision(id) + 1;
    }
  });
}
