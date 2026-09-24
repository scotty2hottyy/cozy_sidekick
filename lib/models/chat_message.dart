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
  });

  /// Shortcut constructors so callers don't repeat themselves.
  factory ChatMessage.user(String text) => ChatMessage(
    role: MessageRole.user,
    text: text,
    createdAt: DateTime.now(),
  );
  factory ChatMessage.assistant(String text) => ChatMessage(
    role: MessageRole.assistant,
    text: text,
    createdAt: DateTime.now(),
  );

  final MessageRole role;
  final String text;
  final DateTime createdAt;

  bool get isUser => role == MessageRole.user;

  /// Converts the message to a map that `jsonEncode` can save.
  ///
  /// `createdAt` is stored as a UTC ISO-8601 string, e.g.
  /// `2026-09-23T17:05:00.000Z`, so it doesn't depend on the phone's time zone.
  Map<String, Object?> toJson() => {
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Rebuilds a message from the output of [toJson]. The time comes back in
  /// the phone's local time zone.
  ///
  /// Throws if a field is missing or invalid (for example, an unknown role),
  /// so code that loads saved messages should be ready to catch errors.
  factory ChatMessage.fromJson(Map<String, Object?> json) {
    return ChatMessage(
      role: MessageRole.values.byName(json['role'] as String),
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    );
  }

  /// Two messages are equal when they have the same role, text and moment in
  /// time. `isAtSameMomentAs` treats a UTC time and a local time for the same
  /// instant as equal, which plain `DateTime ==` does not.
  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.role == role &&
      other.text == text &&
      other.createdAt.isAtSameMomentAs(createdAt);

  @override
  int get hashCode => Object.hash(role, text, createdAt.microsecondsSinceEpoch);

  @override
  String toString() => 'ChatMessage(${role.name}, "$text", $createdAt)';
}
