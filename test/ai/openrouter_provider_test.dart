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
    expect(reply, const AiReply(text: 'Hello'));
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

  test('asks the chosen model and lists models without a key', () async {
    final keys = InMemoryApiKeyStore();
    final requests = <http.Request>[];
    final provider = OpenRouterProvider(
      keyStore: keys,
      client: MockClient((request) async {
        requests.add(request);
        return request.method == 'GET'
            ? http.Response(
                '{"data":[{"id":"x-ai/grok-4.7","architecture":'
                '{"output_modalities":["text"]}}]}',
                200,
              )
            : http.Response('{"choices":[{"message":{"content":"Hi"}}]}', 200);
      }),
    );
    // Anyone can read OpenRouter's list.
    expect(await provider.listModels(), <String>['x-ai/grok-4.7']);
    expect(
      requests.single.url.toString(),
      'https://openrouter.ai/api/v1/models',
    );
    expect(requests.single.headers.containsKey('authorization'), isFalse);

    await keys.save(AiProviderType.openRouter, 'test-key');
    await provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Hi')],
      model: 'x-ai/grok-4.7',
    );
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['model'], 'x-ai/grok-4.7');
  });
}
