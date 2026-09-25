/// Who wrote the message. The names match what AI APIs expect
/// ("user" / "assistant").
enum MessageRole { user, assistant }

/// One message in the conversation, written by the user or by the sidekick.
///
/// Messages are immutable: to "change" one, create a new [ChatMessage].
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    required this.createdAt,
    this.reasoning,
  });

  /// Shortcut constructors so callers don't repeat themselves.
  factory ChatMessage.user(String text) => ChatMessage(
    role: MessageRole.user,
    text: text,
    createdAt: DateTime.now(),
  );
  factory ChatMessage.assistant(String text, {String? reasoning}) =>
      ChatMessage(
        role: MessageRole.assistant,
        text: text,
        createdAt: DateTime.now(),
        reasoning: reasoning,
      );

  final MessageRole role;
  final String text;
  final DateTime createdAt;

  /// The model's thinking before it replied, or null when it didn't share
  /// any. It's saved with the chat, but it's never sent back to the model.
  final String? reasoning;

  bool get isUser => role == MessageRole.user;

  /// Converts the message to a map that `jsonEncode` can save.
  ///
  /// `createdAt` is stored as a UTC ISO-8601 string, e.g.
  /// `2026-09-23T17:05:00.000Z`, so it doesn't depend on the phone's time zone.
  /// `reasoning` is only stored when there is some.
  Map<String, Object?> toJson() => {
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (reasoning != null) 'reasoning': reasoning,
  };

  /// Rebuilds a message from the output of [toJson]. The time comes back in
  /// the phone's local time zone. Messages saved without `reasoning`, such as
  /// chats from before it existed, load with none.
  ///
  /// Throws if a field is missing or invalid (for example, an unknown role),
  /// so code that loads saved messages should be ready to catch errors.
  factory ChatMessage.fromJson(Map<String, Object?> json) {
    return ChatMessage(
      role: MessageRole.values.byName(json['role'] as String),
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      reasoning: json['reasoning'] as String?,
    );
  }

  /// Two messages are equal when they have the same role, text, reasoning and
  /// moment in time. `isAtSameMomentAs` treats a UTC time and a local time for
  /// the same instant as equal, which plain `DateTime ==` does not.
  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.role == role &&
      other.text == text &&
      other.reasoning == reasoning &&
      other.createdAt.isAtSameMomentAs(createdAt);

  @override
  int get hashCode =>
      Object.hash(role, text, reasoning, createdAt.microsecondsSinceEpoch);

  @override
  String toString() => reasoning == null
      ? 'ChatMessage(${role.name}, "$text", $createdAt)'
      : 'ChatMessage(${role.name}, "$text", reasoning: "$reasoning", '
            '$createdAt)';
}
