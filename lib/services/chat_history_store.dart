import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';

abstract interface class ChatHistoryStore {
  Future<List<ChatMessage>> load();
  Future<void> save(List<ChatMessage> messages);
  Future<void> clear();
}

class FileChatHistoryStore implements ChatHistoryStore {
  FileChatHistoryStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  static const int maxMessages = 500;

  Future<File> _file() async =>
      File('${(await _directory()).path}/chat_history.json');

  @override
  Future<List<ChatMessage>> load() async {
    final file = await _file();
    if (!await file.exists()) return <ChatMessage>[];
    final bytes = await file.readAsBytes();
    try {
      final contents = utf8.decode(bytes);
      final decoded = jsonDecode(contents) as List<dynamic>;
      final messages = decoded
          .map((value) => ChatMessage.fromJson(value as Map<String, dynamic>))
          .toList();
      return messages.length > maxMessages
          ? messages.sublist(messages.length - maxMessages)
          : messages;
    } on FormatException {
      return <ChatMessage>[];
    } on TypeError {
      return <ChatMessage>[];
    } on ArgumentError {
      return <ChatMessage>[];
    }
  }

  @override
  Future<void> save(List<ChatMessage> messages) async {
    final recent = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : List<ChatMessage>.of(messages);
    final contents = jsonEncode(
      recent.map((message) => message.toJson()).toList(),
    );
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
