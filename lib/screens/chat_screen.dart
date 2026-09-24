import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import '../services/api_key_store.dart';
import '../services/chat_service.dart';
import '../services/provider_connection_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../widgets/chat_header.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatService,
    required this.speechService,
    required this.settingsStore,
    required this.keyStore,
    required this.connectionTester,
  });
  final ChatService chatService;
  final SpeechService speechService;
  final AppSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final ConnectionTester connectionTester;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = <ChatMessage>[];
  final TextEditingController _composerController = TextEditingController();
  bool _isSending = false;
  SpeechServiceState _speechState = SpeechServiceState.idle;

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;
    setState(() {
      _messages.add(ChatMessage.user(trimmed));
      _isSending = true;
    });
    try {
      final reply = await widget.chatService.getReply(
        List<ChatMessage>.of(_messages),
      );
      if (mounted) setState(() => _messages.add(reply));
    } on AiProviderException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleSpeech() async {
    if (_speechState == SpeechServiceState.listening) {
      await widget.speechService.stopListening();
      return;
    }
    await widget.speechService.startListening(
      onText: (text) {
        if (!mounted) return;
        _composerController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        setState(() {});
      },
      onStateChanged: _handleSpeechState,
    );
  }

  void _handleSpeechState(SpeechServiceState state) {
    if (!mounted) return;
    final changed = state != _speechState;
    setState(() => _speechState = state);
    if (!changed) return;
    final message = switch (state) {
      SpeechServiceState.unavailable =>
        'Speech recognition is not available on this device.',
      SpeechServiceState.permissionDenied => 'Microphone and speech recognition permissions are needed for voice input.',
      SpeechServiceState.error =>
        'Voice input had trouble. Please try again or type your message.',
      SpeechServiceState.idle || SpeechServiceState.listening => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _composerController.dispose();
    unawaited(widget.speechService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: ChatHeader(
                onSettingsTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      settingsStore: widget.settingsStore,
                      keyStore: widget.keyStore,
                      connectionTester: widget.connectionTester,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Say hi to your sidekick 👋',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) => MessageBubble(
                        message: _messages[_messages.length - 1 - index],
                      ),
                    ),
            ),
            if (_isSending)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Sidekick is typing…'),
                  ],
                ),
              ),
            MessageComposer(
              controller: _composerController,
              onSend: _send,
              onMicrophoneTap: _toggleSpeech,
              enabled: !_isSending,
              isListening: _speechState == SpeechServiceState.listening,
            ),
          ],
        ),
      ),
    ),
  );
}
