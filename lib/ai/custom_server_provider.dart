import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../services/api_key_store.dart';
import '../services/settings_service.dart';
import 'ai_provider.dart';
import 'http_helper.dart';

class CustomServerProvider implements AiProvider {
  CustomServerProvider({
    required this.keyStore,
    required this.settingsStore,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final ApiKeyStore keyStore;
  final AppSettingsStore settingsStore;
  final http.Client _client;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    final baseUrl = await settingsStore.loadCustomServerBaseUrl();
    if (!SettingsService.isValidBaseUrl(baseUrl)) {
      throw const ProviderConfigurationException(
        'Custom server base URL is missing or invalid',
      );
    }
    final token = await keyStore.read(AiProviderType.customServer);
    if (token == null || token.trim().isEmpty) {
      throw const MissingApiKeyException();
    }
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final json = await postJson(
      _client,
      Uri.parse('$base/chat'),
      headers: <String, String>{'Authorization': 'Bearer $token'},
      body: <String, Object?>{
        'messages': <Map<String, String>>[
          <String, String>{'role': 'system', 'content': systemPrompt},
          // Only the text. Reasoning is never sent back to the server.
          for (final message in messages)
            <String, String>{
              'role': message.role.name,
              'content': message.text,
            },
        ],
      },
    );
    final reply = json['message'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const BadResponseException('Missing message');
    }
    // A server can share the model's thinking in an optional field.
    final reasoning = json['reasoning'];
    return AiReply(
      text: reply.trim(),
      reasoning: reasoning is String && reasoning.trim().isNotEmpty
          ? reasoning.trim()
          : null,
    );
  }

  /// The server's `/chat` endpoint sends one JSON reply, so the stream has a
  /// single event.
  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async* {
    yield await sendChat(systemPrompt: systemPrompt, messages: messages);
  }
}
