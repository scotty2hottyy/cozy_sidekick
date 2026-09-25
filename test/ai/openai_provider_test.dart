import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/openai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends ordered messages and parses the assistant reply', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openAi, 'test-key');
    late http.Request captured;
    final provider = OpenAiProvider(
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
      'https://api.openai.com/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer test-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'gpt-6-luna');
    expect(body['messages'], <Map<String, String>>[
      <String, String>{'role': 'system', 'content': 'system'},
      <String, String>{'role': 'user', 'content': 'one'},
      <String, String>{'role': 'assistant', 'content': 'two'},
    ]);
  });

  test('missing OpenAI key prevents a request', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'other-provider-key');
    var called = false;
    final provider = OpenAiProvider(
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

  test('rejects malformed response and authentication failure', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openAi, 'key');
    final malformed = OpenAiProvider(
      keyStore: keys,
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      malformed.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<BadResponseException>()),
    );
    final unauthorized = OpenAiProvider(
      keyStore: keys,
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    await expectLater(
      unauthorized.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<InvalidApiKeyException>()),
    );
  });
}
