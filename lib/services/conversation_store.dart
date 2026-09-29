import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/conversation.dart';
import '../models/chat_message.dart';

abstract interface class ConversationStore {
  Future<ConversationState> read();
  Future<void> write(ConversationState state);
}

/// One atomic snapshot keeps messages, metadata and active selection together.
class FileConversationStore implements ConversationStore {
  FileConversationStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;
  final Future<Directory> Function() _directory;

  @override
  Future<ConversationState> read() async {
    final dir = await _directory();
    final file = File('${dir.path}/conversations.json');
    if (await file.exists()) {
      // Do not overwrite unreadable history: callers show a recoverable error.
      return ConversationState.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    }
    final legacy = File('${dir.path}/chat_history.json');
    if (await legacy.exists()) {
      // Parse strictly so a damaged legacy file is not silently discarded.
      final decoded = jsonDecode(await legacy.readAsString()) as List;
      final messages = decoded
          .map((m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)))
          .toList();
      final conversation = Conversation.empty().withMessages(messages);
      final state = ConversationState(
        conversations: [conversation],
        activeId: conversation.id,
      );
      await write(state);
      // The committed snapshot is authoritative, including after delete-all.
      return state;
    }
    return ConversationState(conversations: []);
  }

  @override
  Future<void> write(ConversationState state) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final temporary = File('${dir.path}/conversations.json.tmp');
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temporary.rename('${dir.path}/conversations.json');
    // Remove legacy history only after the replacement is safely committed.
    final legacy = File('${dir.path}/chat_history.json');
    if (await legacy.exists()) await legacy.delete();
  }
}
