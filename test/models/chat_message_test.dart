import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cozy_sidekick/models/chat_message.dart';

void main() {
  /// A valid saved message, for tests that break one field at a time.
  Map<String, Object?> validJson() => {
    'role': 'user',
    'text': 'hi',
    'createdAt': '2026-09-23T17:05:00.000Z',
  };

  group('ChatMessage', () {
    test('survives toJson and fromJson with the same role, text and time', () {
      final original = ChatMessage.user('Hello, sidekick!');

      final restored = ChatMessage.fromJson(original.toJson());

      expect(restored, original);
      // Times are saved in UTC but come back in the phone's local time.
      expect(restored.createdAt.isUtc, isFalse);
    });

    test('isUser is true only for user messages', () {
      expect(ChatMessage.user('hi').isUser, isTrue);
      expect(ChatMessage.assistant('hello').isUser, isFalse);
    });

    test('role.name is "user" or "assistant", as the AI APIs require', () {
      expect(ChatMessage.user('hi').role.name, 'user');
      expect(ChatMessage.assistant('hello').role.name, 'assistant');
    });

    test('survives a round trip through a real JSON string', () {
      final messages = [
        ChatMessage.user('Hi! 👋'),
        ChatMessage.assistant(
          '"Quotes", \\backslashes\\ and\nnew lines are fine.',
        ),
      ];

      // The same steps chat history uses to save to and load from a file.
      final saved = jsonEncode([for (final m in messages) m.toJson()]);
      final loaded = [
        for (final item in jsonDecode(saved) as List<dynamic>)
          ChatMessage.fromJson(item as Map<String, Object?>),
      ];

      expect(loaded, messages);
    });

    test('keeps reasoning through toJson and fromJson', () {
      final original = ChatMessage.assistant(
        'No.',
        reasoning: 'Try dividing by 7.',
      );

      final json = original.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(json['reasoning'], 'Try dividing by 7.');
      expect(restored, original);
      expect(restored.reasoning, 'Try dividing by 7.');
    });

    test('only stores reasoning when there is some', () {
      final original = ChatMessage.assistant('No.');

      final json = original.toJson();

      expect(json.containsKey('reasoning'), isFalse);
      expect(ChatMessage.fromJson(json), original);
    });

    test('loads messages saved before reasoning existed', () {
      final restored = ChatMessage.fromJson({
        'role': 'assistant',
        'text': 'Hello!',
        'createdAt': '2026-09-23T17:05:00.000Z',
      });

      expect(restored.text, 'Hello!');
      expect(restored.reasoning, isNull);
    });

    test('toJson stores createdAt as a UTC ISO-8601 string', () {
      // A local time, so the test checks the conversion to UTC.
      final localTime = DateTime.utc(2026, 9, 23, 17, 5).toLocal();
      final message = ChatMessage(
        role: MessageRole.user,
        text: 'hi',
        createdAt: localTime,
      );

      expect(message.toJson()['createdAt'], '2026-09-23T17:05:00.000Z');
    });

    test('fromJson throws on an unknown role', () {
      final json = validJson();
      json['role'] = 'robot';

      expect(() => ChatMessage.fromJson(json), throwsArgumentError);
    });

    test('fromJson throws when a field is missing', () {
      for (final field in ['role', 'text', 'createdAt']) {
        final json = validJson();
        json.remove(field);

        expect(
          () => ChatMessage.fromJson(json),
          throwsA(isA<TypeError>()),
          reason: 'missing "$field"',
        );
      }
    });

    test(
      'messages are equal only when role, text, reasoning and time match',
      () {
        final time = DateTime.utc(2026, 9, 23, 17, 5);
        final message = ChatMessage(
          role: MessageRole.user,
          text: 'hi',
          createdAt: time,
        );

        // The same moment written in local time still counts as equal.
        final sameMoment = ChatMessage(
          role: MessageRole.user,
          text: 'hi',
          createdAt: time.toLocal(),
        );
        expect(sameMoment, message);
        expect(sameMoment.hashCode, message.hashCode);

        expect(
          ChatMessage(role: MessageRole.assistant, text: 'hi', createdAt: time),
          isNot(message),
        );
        expect(
          ChatMessage(role: MessageRole.user, text: 'bye', createdAt: time),
          isNot(message),
        );
        expect(
          ChatMessage(
            role: MessageRole.user,
            text: 'hi',
            createdAt: time,
            reasoning: 'thinking',
          ),
          isNot(message),
        );
        expect(
          ChatMessage(
            role: MessageRole.user,
            text: 'hi',
            createdAt: time.add(const Duration(microseconds: 1)),
          ),
          isNot(message),
        );
      },
    );
  });
}
