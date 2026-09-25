import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/message_formatting.dart';
import 'formatted_reply.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.formatting = const MessageFormatting(),
  });
  final ChatMessage message;

  /// How replies are drawn. User messages always show their raw text.
  final MessageFormatting formatting;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: message.isUser ? colors.onPrimary : colors.onSurfaceVariant,
      height: 1.35,
    );
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: message.isUser ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(message.isUser ? 22 : 6),
          bottomRight: Radius.circular(message.isUser ? 6 : 22),
        ),
      ),
      child: !message.isUser && formatting.formatReplies
          ? FormattedReply(
              message.text,
              style: textStyle,
              formatting: formatting,
            )
          : Text(message.text, style: textStyle),
    );
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: message.isUser
            ? bubble
            : GestureDetector(
                // Rendered math can't be selected, so replies offer Copy.
                onLongPress: () => _showReplyActions(context),
                child: bubble,
              ),
      ),
    );
  }

  Future<void> _showReplyActions(BuildContext context) async {
    Feedback.forLongPress(context);
    final copy = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.copy_rounded),
          title: const Text('Copy'),
          onTap: () => Navigator.pop(sheetContext, true),
        ),
      ),
    );
    if (copy != true) return;
    // The original Markdown and LaTeX, not the rendered text.
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }
}
