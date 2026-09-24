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
  Future<String> sendChat({
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
    return reply.trim();
  }
}
