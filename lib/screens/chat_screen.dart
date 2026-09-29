import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../ai/error_messages.dart';
import '../models/chat_message.dart';
import '../models/message_formatting.dart';
import '../services/api_key_store.dart';
import '../services/chat_service.dart';
import '../services/model_list_service.dart';
import '../services/personality_service.dart';
import '../services/provider_connection_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../widgets/chat_header.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import 'ai_settings_screen.dart';
import 'api_credentials_screen.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatService,
    required this.speechService,
    required this.settingsStore,
    required this.personalityStore,
    required this.keyStore,
    required this.connectionTester,
    required this.modelLister,
  });
  final ChatService chatService;
  final SpeechService speechService;
  final AppSettingsStore settingsStore;
  final PersonalityStore personalityStore;
  final ApiKeyStore keyStore;
  final ConnectionTester connectionTester;
  final ModelLister modelLister;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = <ChatMessage>[];
  final TextEditingController _composerController = TextEditingController();
  bool _isSending = false;
  bool _isLoading = true;
  bool _isClearing = false;
  bool get _busy => _isLoading || _isSending || _isClearing;
  MessageFormatting _formatting = const MessageFormatting();
  bool _showReasoning = false;

  /// Replies whose reasoning is open. They're kept here rather than in each
  /// bubble, so a reply stays open while new messages arrive or it scrolls
  /// out of view.
  final Set<ChatMessage> _expandedReasoning = Set<ChatMessage>.identity();

  /// The reply while it arrives, shown as the newest bubble. It moves into
  /// [_messages] when it's finished. Every event is a new [ChatMessage], so
  /// whether its reasoning is open is kept in [_liveReasoningExpanded]
  /// instead of [_expandedReasoning].
  ChatMessage? _liveReply;
  bool _liveReasoningExpanded = false;
  StreamSubscription<ChatMessage>? _replySubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChatSettings());
    unawaited(_loadHistory());
  }

  /// Loads the settings that change how the chat looks. Runs at startup and
  /// again when the user comes back from Settings, so changes apply right
  /// away.
  Future<void> _loadChatSettings() async {
    final formatting = await widget.settingsStore.loadMessageFormatting();
    final showReasoning = await widget.settingsStore.loadShowReasoning();
    if (mounted) {
      setState(() {
        _formatting = formatting;
        _showReasoning = showReasoning;
      });
    }
  }

  void _toggleReasoning(ChatMessage message) => setState(() {
    if (!_expandedReasoning.remove(message)) _expandedReasoning.add(message);
  });

  void _toggleLiveReasoning() =>
      setState(() => _liveReasoningExpanded = !_liveReasoningExpanded);

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          onClearChat: _clearChat,
          settingsStore: widget.settingsStore,
          personalityStore: widget.personalityStore,
          keyStore: widget.keyStore,
          connectionTester: widget.connectionTester,
          modelLister: widget.modelLister,
        ),
      ),
    );
    if (mounted) await _loadChatSettings();
  }

  Future<void> _loadHistory() async {
    try {
      final messages = await widget.chatService.loadHistory();
      if (mounted) setState(() => _messages.addAll(messages));
    } on Exception {
      _showStorageError('Could not load saved chat.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStorageError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _clearChat() async {
    if (_busy) return;
    setState(() => _isClearing = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear chat'),
          content: const Text("Delete all messages? This can't be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.chatService.clearHistory();
      if (mounted) {
        setState(() {
          _messages.clear();
          _expandedReasoning.clear();
        });
      }
    } on Exception {
      _showStorageError('Could not clear saved chat. Please try again.');
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  SpeechServiceState _speechState = SpeechServiceState.idle;

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    setState(() => _messages.add(ChatMessage.user(trimmed)));
    _requestReply();
  }

  /// Asks again for a reply to the last message. A failed request leaves the
  /// user's message in the list, so nothing they typed is lost.
  void _retry() {
    if (_busy || _messages.isEmpty || !_messages.last.isUser) return;
    _requestReply();
  }

  void _requestReply() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _isSending = true;
      _liveReasoningExpanded = false;
    });
    _replySubscription = widget.chatService
        .streamReply(List<ChatMessage>.of(_messages))
        .listen(
          (reply) => setState(() => _liveReply = reply),
          onDone: _finishReply,
          onError: _failReply,
          cancelOnError: true,
        );
  }

  void _finishReply() => setState(() {
    final reply = _liveReply;
    if (reply != null) {
      _messages.add(reply);
      if (_liveReasoningExpanded) _expandedReasoning.add(reply);
    }
    _liveReply = null;
    _replySubscription = null;
    _isSending = false;
  });

  /// The half-finished reply disappears, and the user's message stays so
  /// Retry can ask again.
  void _failReply(Object error) {
    setState(() {
      _liveReply = null;
      _replySubscription = null;
      _isSending = false;
    });
    if (error is AiProviderException) {
      debugPrint('Chat failed: $error'); // never includes keys
      _showError(
        friendlyMessage(error),
        fixIn: needsSettings(error) ? _settingsFor(error) : null,
      );
    } else {
      debugPrint('Unexpected chat error: $error');
      _showError('Something went wrong. Please try again.');
    }
  }

  /// The reply that's arriving, once it has something to show: some of the
  /// answer, or reasoning while Show reasoning is on.
  ChatMessage? get _shownLiveReply {
    final reply = _liveReply;
    if (reply == null) return null;
    final hasReasoning = _showReasoning && reply.reasoning != null;
    return reply.text.isNotEmpty || hasReasoning ? reply : null;
  }

  /// With [fixIn], the action opens that screen instead of trying again.
  void _showError(String message, {Widget? fixIn}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        // A SnackBar with an action stays up until tapped, covering the
        // composer. Only keep it up for screen readers, which need the time.
        persist: MediaQuery.accessibleNavigationOf(context),
        action: fixIn != null
            ? SnackBarAction(
                label: 'Settings',
                onPressed: () => _openToFix(fixIn),
              )
            : SnackBarAction(label: 'Retry', onPressed: _retry),
      ),
    );
  }

  /// The screen where the user fixes [error]. The model is chosen in AI
  /// Settings, and keys and the custom server URL are set in API Credentials.
  Widget _settingsFor(AiProviderException error) =>
      error is ModelNotAvailableException
      ? AiSettingsScreen(
          settingsStore: widget.settingsStore,
          modelLister: widget.modelLister,
        )
      : ApiCredentialsScreen(
          settingsStore: widget.settingsStore,
          keyStore: widget.keyStore,
          connectionTester: widget.connectionTester,
        );

  /// Opens [screen]. The user has likely fixed the problem when they come
  /// back, so it asks again.
  Future<void> _openToFix(Widget screen) async {
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _retry();
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
    // The request itself stops when its next piece arrives, because the
    // `await for` loops under this stream only notice a cancel then.
    unawaited(_replySubscription?.cancel());
    _composerController.dispose();
    unawaited(widget.speechService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveReply = _shownLiveReply;
    final messages = <ChatMessage>[..._messages, ?liveReply];
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: ChatHeader(onSettingsTap: _busy ? null : _openSettings),
              ),
              const Divider(height: 1),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : messages.isEmpty
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
                        itemCount: messages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, index) {
                          final message = messages[messages.length - 1 - index];
                          final isLive = identical(message, liveReply);
                          return MessageBubble(
                            message: message,
                            formatting: _formatting,
                            showReasoning: _showReasoning,
                            reasoningExpanded: isLive
                                ? _liveReasoningExpanded
                                : _expandedReasoning.contains(message),
                            onReasoningToggle: isLive
                                ? _toggleLiveReasoning
                                : () => _toggleReasoning(message),
                          );
                        },
                      ),
              ),
              if (_isSending && liveReply == null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      // Reasoning that's arriving while Show reasoning is off.
                      Text(
                        _liveReply?.reasoning == null
                            ? 'Sidekick is typing…'
                            : 'Sidekick is thinking…',
                      ),
                    ],
                  ),
                ),
              MessageComposer(
                controller: _composerController,
                onSend: _send,
                onMicrophoneTap: _toggleSpeech,
                enabled: !_busy,
                isListening: _speechState == SpeechServiceState.listening,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
