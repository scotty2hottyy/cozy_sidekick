import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/xai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends xAI chat request and parses the first assistant reply', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.xai, 'test-key');
    late http.Request captured;
    final provider = XaiProvider(
      keyStore: keys,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"choices":[{"message":{"content":" Hello from Grok "}}]}',
          200,
        );
      }),
    );

    final reply = await provider.sendChat(
      systemPrompt: 'Be helpful',
      messages: <ChatMessage>[
        ChatMessage.user('First'),
        ChatMessage.assistant('Second'),
        ChatMessage.user('Third'),
      ],
    );

    expect(reply, const AiReply(text: 'Hello from Grok'));
    expect(captured.url.toString(), 'https://api.x.ai/v1/chat/completions');
    expect(captured.headers['authorization'], 'Bearer test-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'grok-4.3');
    expect(body['messages'], <Map<String, String>>[
      <String, String>{'role': 'system', 'content': 'Be helpful'},
      <String, String>{'role': 'user', 'content': 'First'},
      <String, String>{'role': 'assistant', 'content': 'Second'},
      <String, String>{'role': 'user', 'content': 'Third'},
    ]);
  });

  test('missing xAI key prevents a network request', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openAi, 'another-provider-key');
    var called = false;
    final provider = XaiProvider(
      keyStore: keys,
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<MissingApiKeyException>()),
    );
    expect(called, isFalse);
  });

  test('existing Test Connection service uses the xAI provider', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.xai, 'test-key');
    var requests = 0;
    final provider = XaiProvider(
      keyStore: keys,
      client: MockClient((request) async {
        requests++;
        expect(request.url.toString(), 'https://api.x.ai/v1/chat/completions');
        return http.Response('{"choices":[{"message":{"content":"OK"}}]}', 200);
      }),
    );
    final connectionTester = ProviderConnectionService(
      providers: <AiProviderType, AiProvider>{AiProviderType.xai: provider},
    );

    final result = await connectionTester.testConnection(AiProviderType.xai);

    expect(result.status, ConnectionTestStatus.success);
    expect(requests, 1);
  });
}
