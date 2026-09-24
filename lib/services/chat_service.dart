import '../models/chat_message.dart';

class ChatService {
  ChatService({this.replyDelay = const Duration(seconds: 1)});
  final Duration replyDelay;

  Future<ChatMessage> getReply(List<ChatMessage> conversation) async {
    if (conversation.isEmpty) {
      throw ArgumentError('conversation cannot be empty');
    }
    await Future<void>.delayed(replyDelay);
    return ChatMessage.assistant('You said: ${conversation.last.text}');
  }
}
