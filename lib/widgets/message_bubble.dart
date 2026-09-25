import 'dart:async';
import 'dart:math' as math;

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
    this.showReasoning = false,
    this.reasoningExpanded = false,
    this.onReasoningToggle,
  });
  final ChatMessage message;

  /// How replies are drawn. User messages always show their raw text.
  final MessageFormatting formatting;

  /// Whether a reply that includes the model's reasoning shows a Reasoning
  /// row above it. Show reasoning in AI Settings turns this on.
  final bool showReasoning;

  /// Whether the reasoning is shown under its row. The chat keeps track of
  /// this, so a reply stays open while new messages arrive.
  final bool reasoningExpanded;

  /// Called when the Reasoning row is tapped.
  final VoidCallback? onReasoningToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: message.isUser ? colors.onPrimary : colors.onSurfaceVariant,
      height: 1.35,
    );
    final Widget text = !message.isUser && formatting.formatReplies
        ? FormattedReply(message.text, style: textStyle, formatting: formatting)
        : Text(message.text, style: textStyle);
    final reasoning = showReasoning && !message.isUser
        ? message.reasoning
        : null;
    // A reply that's still arriving can have reasoning but no answer yet.
    final thinking = reasoning != null && message.text.isEmpty;
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
      child: reasoning == null
          ? text
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Reasoning(
                  reasoning,
                  thinking: thinking,
                  expanded: reasoningExpanded,
                  onToggle: onReasoningToggle,
                ),
                if (!thinking) text,
              ],
            ),
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

/// The Reasoning row at the top of a reply and, while it's expanded, the
/// reasoning itself with a divider under it.
class _Reasoning extends StatefulWidget {
  const _Reasoning(
    this.reasoning, {
    required this.thinking,
    required this.expanded,
    required this.onToggle,
  });
  final String reasoning;

  /// Whether the model is still thinking, before its answer starts. The row
  /// then reads Thinking… and stays open, with the reasoning growing under
  /// it.
  final bool thinking;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  State<_Reasoning> createState() => _ReasoningState();
}

class _ReasoningState extends State<_Reasoning> {
  /// Measures the reasoning before it's hidden.
  final GlobalKey _body = GlobalKey();

  /// Space kept between an opened row and the top of the chat list.
  static const double _topMargin = 8;

  /// Ticks once a second while the model thinks, to show how long it's been.
  Timer? _thinkingTimer;

  @override
  void initState() {
    super.initState();
    _updateThinkingTimer();
  }

  @override
  void didUpdateWidget(_Reasoning oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateThinkingTimer();
  }

  @override
  void dispose() {
    _thinkingTimer?.cancel();
    super.dispose();
  }

  void _updateThinkingTimer() {
    if (widget.thinking) {
      _thinkingTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _thinkingTimer?.cancel();
      _thinkingTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final thinking = widget.thinking;
    final seconds = _thinkingTimer?.tick ?? 0;
    final onToggle = widget.onToggle;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.psychology_outlined, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            !thinking
                ? 'Reasoning'
                : seconds == 0
                ? 'Thinking…'
                : 'Thinking… ${seconds}s',
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
          if (!thinking)
            Icon(
              widget.expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: color,
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          // Its own node, so screen readers don't read the reply as part of
          // the button.
          container: true,
          button: !thinking,
          expanded: thinking ? null : widget.expanded,
          child: thinking
              ? row
              : Material(
                  // Draws the tap ripple on top of the bubble instead of
                  // behind it.
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('reasoningToggle'),
                    onTap: onToggle == null ? null : () => _toggle(onToggle),
                    borderRadius: BorderRadius.circular(8),
                    child: row,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        if (thinking || widget.expanded)
          Column(
            key: _body,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.reasoning,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
              // It divides the reasoning from the answer, which hasn't
              // started while the model is thinking.
              if (!thinking) const Divider(height: 24),
            ],
          ),
      ],
    );
  }

  /// The chat list starts from the bottom, so a reply grows upward when its
  /// reasoning opens and shrinks downward when it closes, taking this row
  /// with it. Opening scrolls just enough to keep the row in view, so long
  /// reasoning reads from its start. Closing scrolls the row back to where it
  /// is now, instead of leaving older messages in view.
  void _toggle(VoidCallback onToggle) {
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (scrollable == null ||
        !axisDirectionIsReversed(scrollable.position.axisDirection)) {
      onToggle();
      return;
    }
    if (widget.expanded) {
      // Measured now, because a reply that shrinks far below the screen is
      // disposed before it could be measured again. The scroll happens in
      // the same frame as the close.
      final height = _body.currentContext?.size?.height ?? 0;
      final position = scrollable.position;
      onToggle();
      position.jumpTo(
        math.max(position.minScrollExtent, position.pixels - height),
      );
      return;
    }
    onToggle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final top = _topOf(context);
      final listTop = _topOf(scrollable.context);
      if (top == null || listTop == null) return;
      final hidden = listTop + _topMargin - top;
      final position = scrollable.position;
      if (hidden > 0) {
        position.jumpTo(
          math.min(position.maxScrollExtent, position.pixels + hidden),
        );
      }
    });
  }

  /// Where the top of [context]'s widget is on screen, or null before it has
  /// been laid out.
  static double? _topOf(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero).dy
        : null;
  }
}
