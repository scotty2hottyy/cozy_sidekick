import 'dart:math' as math;

import 'package:flutter/material.dart';

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onMicrophoneTap,
    this.enabled = true,
    this.isListening = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onMicrophoneTap;
  final bool enabled;
  final bool isListening;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  void _submit() {
    final text = widget.controller.text.trim();
    if (!widget.enabled || text.isEmpty) return;
    widget.onSend(text);
    widget.controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 8,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        10,
        10,
        math.max(12, MediaQuery.viewPaddingOf(context).bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.isListening)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text('Listening…'),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('messageInput'),
                  controller: widget.controller,
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Message your sidekick',
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('microphoneButton'),
                onPressed: widget.enabled ? widget.onMicrophoneTap : null,
                icon: Icon(
                  widget.isListening
                      ? Icons.stop_circle_rounded
                      : Icons.mic_rounded,
                ),
                tooltip: widget.isListening
                    ? 'Stop listening'
                    : 'Start listening',
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  iconSize: 27,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const Key('sendButton'),
                onPressed:
                    widget.enabled && widget.controller.text.trim().isNotEmpty
                    ? _submit
                    : null,
                icon: const Icon(Icons.send_rounded),
                tooltip: 'Send',
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  iconSize: 27,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
