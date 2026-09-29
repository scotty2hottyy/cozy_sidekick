import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/open_code_zen_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends the editable Zen model to its chat completions endpoint', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openCodeZen, 'zen-key');
    late http.Request sent;
    final provider = OpenCodeZenProvider(
      keyStore: keys,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          '{"choices":[{"message":{"content":"Hello"}}]}',
          200,
        );
      }),
    );

    await provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Hi')],
      model: 'custom-free-model',
    );

    expect(
      sent.url.toString(),
      'https://opencode.ai/zen/v1/chat/completions',
    );
    expect(sent.headers['authorization'], 'Bearer zen-key');
    expect(
      (jsonDecode(sent.body) as Map<String, dynamic>)['model'],
      'custom-free-model',
    );
  });
}