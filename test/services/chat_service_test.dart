import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns a placeholder reply to the latest message', () async {
    final service = ChatService(replyDelay: Duration.zero);
    final reply = await service.getReply(<ChatMessage>[
      ChatMessage.user('first'),
      ChatMessage.user('latest'),
    ]);
    expect(reply.role, MessageRole.assistant);
    expect(reply.text, 'You said: latest');
  });

  test('rejects an empty conversation', () {
    final service = ChatService(replyDelay: Duration.zero);
    expect(() => service.getReply(<ChatMessage>[]), throwsArgumentError);
  });
}
