import 'package:flutter/material.dart';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key, required this.onClearChat});

  final Future<void> Function() onClearChat;

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  bool _isClearing = false;

  Future<void> _clearChat() async {
    if (_isClearing) return;
    setState(() => _isClearing = true);
    try {
      await widget.onClearChat();
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat History')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Your current conversation is saved on this device.'),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Clear chat'),
              subtitle: const Text('Delete all messages from this device'),
              enabled: !_isClearing,
              onTap: _isClearing ? null : _clearChat,
            ),
          ],
        ),
      ),
    ),
  );
}
