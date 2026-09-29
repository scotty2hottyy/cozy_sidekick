import 'dart:math';

import 'chat_message.dart';

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    List<ChatMessage> messages = const [],
    this.isTitleCustom = false,
  }) : messages = List.unmodifiable(
         messages.length > 500
             ? messages.sublist(messages.length - 500)
             : messages,
       );

  factory Conversation.empty() {
    final now = DateTime.now();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return Conversation(
      id: id,
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
    );
  }
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isTitleCustom;
  final List<ChatMessage> messages;

  static String titleFrom(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'New chat';
    final chars = normalized.runes.toList();
    return chars.length > 60
        ? '${String.fromCharCodes(chars.take(60))}…'
        : normalized;
  }

  Conversation withMessages(List<ChatMessage> value) {
    var nextTitle = title;
    if (!isTitleCustom && messages.isEmpty) {
      final users = value.where((m) => m.isUser);
      if (users.isNotEmpty) nextTitle = titleFrom(users.first.text);
    }
    return Conversation(
      id: id,
      title: nextTitle,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      messages: value,
      isTitleCustom: isTitleCustom,
    );
  }

  Conversation renamed(String value) {
    final name = value.trim();
    if (name.isEmpty) throw ArgumentError('Title cannot be empty');
    return Conversation(
      id: id,
      title: name,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      messages: messages,
      isTitleCustom: true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isTitleCustom': isTitleCustom,
    'messages': messages.map((m) => m.toJson()).toList(),
  };
  factory Conversation.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final title = json['title'] as String;
    if (id.isEmpty || title.trim().isEmpty) {
      throw const FormatException('Invalid conversation');
    }
    return Conversation(
      id: id,
      title: title,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isTitleCustom: json['isTitleCustom'] as bool? ?? false,
      messages: (json['messages'] as List)
          .map((m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)))
          .toList(),
    );
  }
}

class ConversationState {
  ConversationState({required List<Conversation> conversations, this.activeId})
    : conversations = List.unmodifiable(conversations);
  final List<Conversation> conversations;
  final String? activeId;
  Map<String, Object?> toJson() => {
    'version': 1,
    'activeId': activeId,
    'conversations': conversations.map((c) => c.toJson()).toList(),
  };
  factory ConversationState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported conversation file');
    }
    final conversations = (json['conversations'] as List)
        .map((c) => Conversation.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
    if (conversations.map((c) => c.id).toSet().length != conversations.length) {
      throw const FormatException('Duplicate conversation IDs');
    }
    final active = json['activeId'] as String?;
    return ConversationState(
      conversations: conversations,
      activeId: conversations.any((c) => c.id == active)
          ? active
          : conversations.firstOrNull?.id,
    );
  }
}
