import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../services/api_key_store.dart';
import 'ai_provider.dart';
import 'http_helper.dart';

class OpenAiCompatibleProvider implements AiProvider {
  OpenAiCompatibleProvider({
    required this.type,
    required this.baseUrl,
    required this.model,
    required this.keyStore,
    this.extraHeaders = const <String, String>{},
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AiProviderType type;
  final String baseUrl;
  final String model;
  final ApiKeyStore keyStore;
  final Map<String, String> extraHeaders;
  final http.Client _client;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
  }) async {
    final json = await postJson(
      _client,
      _chatUrl,
      headers: await _headers(),
      abortTrigger: abortTrigger,
      body: buildRequestBody(systemPrompt, messages),
    );
    return parseReply(json);
  }

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
  }) async* {
    final events = postEventStream(
      _client,
      _chatUrl,
      headers: await _headers(),
      abortTrigger: abortTrigger,
      body: <String, Object?>{
        ...buildRequestBody(systemPrompt, messages),
        'stream': true,
      },
    );
    final content = StringBuffer();
    // Each field that can carry reasoning has its own buffer, because
    // OpenRouter can send the same text in two of them. The first one with
    // some text is used, like parseReply does.
    final reasoning = StringBuffer();
    final reasoningDetails = StringBuffer();
    final reasoningContent = StringBuffer();
    String? reasoningSoFar() =>
        _nonBlank('$reasoning') ??
        _nonBlank('$reasoningDetails') ??
        _nonBlank('$reasoningContent');

    var shown = const AiReply(text: '');
    await for (final event in events) {
      final delta = _delta(event);
      if (delta == null) continue;
      _append(content, delta['content']);
      _append(reasoning, delta['reasoning']);
      _append(
        reasoningDetails,
        _reasoningDetailsText(delta['reasoning_details']),
      );
      _append(reasoningContent, delta['reasoning_content']);
      final reply = _withReasoningSoFar('$content', reasoningSoFar());
      if (reply != shown) {
        shown = reply;
        yield reply;
      }
    }
    final finished = _withReasoning('$content', reasoningSoFar());
    if (finished.text.isEmpty) {
      throw const BadResponseException('The stream ended without an answer');
    }
    if (finished != shown) yield finished;
  }

  Uri get _chatUrl =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions');

  /// The request headers, with the saved key. Throws [MissingApiKeyException]
  /// when there isn't one.
  Future<Map<String, String>> _headers() async {
    final apiKey = await keyStore.read(type);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const MissingApiKeyException();
    }
    return <String, String>{'Authorization': 'Bearer $apiKey', ...extraHeaders};
  }

  /// Sends only each message's text. Reasoning is never sent back, because
  /// it's often longer than the answer and would crowd out the conversation.
  Map<String, Object?> buildRequestBody(
    String systemPrompt,
    List<ChatMessage> messages,
  ) => <String, Object?>{
    'model': model,
    'messages': <Map<String, String>>[
      <String, String>{'role': 'system', 'content': systemPrompt},
      for (final message in messages)
        <String, String>{'role': message.role.name, 'content': message.text},
    ],
  };

  AiReply parseReply(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      final message = first is Map<String, dynamic> ? first['message'] : null;
      if (message is Map<String, dynamic>) {
        final content = message['content'];
        if (content is String) {
          final reply = _withReasoning(
            content,
            _nonBlank(message['reasoning']) ??
                _nonBlank(message['reasoning_content']),
          );
          if (reply.text.isNotEmpty) return reply;
        }
      }
    }
    throw const BadResponseException('Missing choices[0].message.content');
  }

  /// Splits [content] into the answer and the model's reasoning.
  ///
  /// The reasoning is [reasoning] when the API sent it separately, as
  /// `reasoning` (OpenRouter, Ollama, vLLM) or `reasoning_content` (llama.cpp
  /// and DeepSeek-style APIs). Otherwise it's everything before the
  /// last `</think>` in [content], without a leading `<think>`. Some Qwen3
  /// models send only the closing tag.
  static AiReply _withReasoning(String content, String? reasoning) {
    final end = content.lastIndexOf(_thinkEnd);
    if (reasoning != null || end == -1) {
      return AiReply(text: content.trim(), reasoning: reasoning);
    }
    var thinking = content.substring(0, end).trimLeft();
    if (thinking.startsWith(_thinkStart)) {
      thinking = thinking.substring(_thinkStart.length);
    }
    return AiReply(
      text: content.substring(end + _thinkEnd.length).trim(),
      reasoning: _nonBlank(thinking),
    );
  }

  /// Like [_withReasoning], for a reply that's still arriving. Until a
  /// `<think>` at the start of [content] is closed, everything after it is
  /// reasoning so far.
  static AiReply _withReasoningSoFar(String content, String? reasoning) {
    final start = content.trimLeft();
    if (reasoning == null &&
        start.startsWith(_thinkStart) &&
        !content.contains(_thinkEnd)) {
      return AiReply(
        text: '',
        reasoning: _nonBlank(start.substring(_thinkStart.length)),
      );
    }
    return _withReasoning(content, reasoning);
  }

  static const String _thinkStart = '<think>';
  static const String _thinkEnd = '</think>';

  /// The `choices[0].delta` of a streamed piece, or null when it has none.
  ///
  /// Throws [ProviderUnavailableException] for a piece that reports an error.
  /// OpenRouter sends one, with `"finish_reason": "error"`, when a reply fails
  /// after it has started.
  static Map<String, dynamic>? _delta(Map<String, dynamic> event) {
    final choices = event['choices'];
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    final error = event['error'];
    if (error != null ||
        (choice is Map<String, dynamic> &&
            choice['finish_reason'] == 'error')) {
      final message = error is Map<String, dynamic> ? error['message'] : null;
      throw ProviderUnavailableException(
        'Error during the stream${message is String ? ': $message' : ''}',
      );
    }
    final delta = choice is Map<String, dynamic> ? choice['delta'] : null;
    return delta is Map<String, dynamic> ? delta : null;
  }

  /// The text in OpenRouter's `reasoning_details`: the `text` of
  /// `reasoning.text` entries and the `summary` of `reasoning.summary`
  /// entries. `reasoning.encrypted` entries can't be read.
  static String _reasoningDetailsText(Object? details) {
    final text = StringBuffer();
    if (details is List) {
      for (final detail in details) {
        if (detail is! Map<String, dynamic>) continue;
        _append(text, switch (detail['type']) {
          'reasoning.text' => detail['text'],
          'reasoning.summary' => detail['summary'],
          _ => null,
        });
      }
    }
    return '$text';
  }

  static void _append(StringBuffer buffer, Object? text) {
    if (text is String) buffer.write(text);
  }

  /// [value] without surrounding whitespace, or null when it isn't a string
  /// with some text in it.
  static String? _nonBlank(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
