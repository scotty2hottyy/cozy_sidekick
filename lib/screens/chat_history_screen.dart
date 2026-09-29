import 'package:flutter/material.dart';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({
    super.key,
    required this.onClearChat,
    this.onDeleteAllChats,
  });

  final Future<void> Function() onClearChat;
  final Future<void> Function()? onDeleteAllChats;

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
            const Text('Your conversations are saved on this device.'),
            const SizedBox(height: 16),
            if (widget.onDeleteAllChats != null)
              ListTile(
                title: const Text('Delete all conversations'),
                leading: const Icon(Icons.delete_sweep_outlined),
                onTap: _isClearing ? null : widget.onDeleteAllChats,
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Clear chat'),
              subtitle: const Text(
                'Delete messages in the current conversation',
              ),
              enabled: !_isClearing,
              onTap: _isClearing ? null : _clearChat,
            ),
          ],
        ),
      ),
    ),
  );
}
