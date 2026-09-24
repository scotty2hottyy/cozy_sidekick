import 'package:flutter/material.dart';

import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: message.isUser
                ? colors.primary
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(message.isUser ? 22 : 6),
              bottomRight: Radius.circular(message.isUser ? 6 : 22),
            ),
          ),
          child: Text(
            message.text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: message.isUser
                  ? colors.onPrimary
                  : colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
