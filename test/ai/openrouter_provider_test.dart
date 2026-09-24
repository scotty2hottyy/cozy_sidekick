import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/openrouter_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends ordered messages and parses the assistant reply', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'test-key');
    late http.Request captured;
    final provider = OpenRouterProvider(
      keyStore: keys,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"choices":[{"message":{"content":" Hello "}}]}',
          200,
        );
      }),
    );
    final reply = await provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[
        ChatMessage.user('one'),
        ChatMessage.assistant('two'),
      ],
    );
    expect(reply, 'Hello');
    expect(
      captured.url.toString(),
      'https://openrouter.ai/api/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer test-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'openrouter/free');
    expect((body['messages'] as List).map((e) => e['role']), <String>[
      'system',
      'user',
      'assistant',
    ]);
  });

  test('missing key prevents a request', () async {
    var called = false;
    final provider = OpenRouterProvider(
      keyStore: InMemoryApiKeyStore(),
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

  test('rejects malformed response and authentication failure', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'key');
    final malformed = OpenRouterProvider(
      keyStore: keys,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      malformed.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<BadResponseException>()),
    );
    final unauthorized = OpenRouterProvider(
      keyStore: keys,
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    await expectLater(
      unauthorized.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<InvalidApiKeyException>()),
    );
  });
}
