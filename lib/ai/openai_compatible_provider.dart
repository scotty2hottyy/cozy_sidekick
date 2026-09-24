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
  Future<String> sendChat({
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

  String parseReply(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      final message = first is Map<String, dynamic> ? first['message'] : null;
      final content = message is Map<String, dynamic>
          ? message['content']
          : null;
      if (content is String && content.trim().isNotEmpty) {
        return content.trim();
      }
    }
    throw const BadResponseException('Missing choices[0].message.content');
  }
}
