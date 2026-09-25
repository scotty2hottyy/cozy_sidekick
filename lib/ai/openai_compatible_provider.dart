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
  }) async {
    final apiKey = await keyStore.read(type);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const MissingApiKeyException();
    }
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final json = await postJson(
      _client,
      Uri.parse('$base/chat/completions'),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        ...extraHeaders,
      },
      body: buildRequestBody(systemPrompt, messages),
    );
    return parseReply(json);
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
  /// `reasoning` (OpenRouter, Ollama, vLLM) or `reasoning_content` (xAI,
  /// llama.cpp and DeepSeek-style APIs). Otherwise it's everything before the
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

  static const String _thinkStart = '<think>';
  static const String _thinkEnd = '</think>';

  /// [value] without surrounding whitespace, or null when it isn't a string
  /// with some text in it.
  static String? _nonBlank(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
