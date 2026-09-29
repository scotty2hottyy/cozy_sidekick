import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends ordered Groq messages and parses the assistant reply', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'test-key');
    late http.Request captured;
    final provider = GroqProvider(
      keyStore: keys,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"choices":[{"message":{"content":" Hello from Groq "}}]}',
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

    expect(reply, const AiReply(text: 'Hello from Groq'));
    expect(
      captured.url.toString(),
      'https://api.groq.com/openai/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer test-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'openai/gpt-oss-20b');
    expect(body['messages'], <Map<String, String>>[
      <String, String>{'role': 'system', 'content': 'Be helpful'},
      <String, String>{'role': 'user', 'content': 'First'},
      <String, String>{'role': 'assistant', 'content': 'Second'},
      <String, String>{'role': 'user', 'content': 'Third'},
    ]);
  });

  test('missing Groq key prevents a network request', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openAi, 'another-provider-key');
    var called = false;
    final provider = GroqProvider(
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

  test('streams chat replies through the Groq endpoint', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'test-key');
    late http.BaseRequest captured;
    final provider = GroqProvider(
      keyStore: keys,
      client: MockClient.streaming((request, bodyStream) async {
        captured = request;
        final body = jsonDecode(
          await bodyStream.bytesToString(),
        ) as Map<String, dynamic>;
        expect(body['model'], 'openai/gpt-oss-20b');
        expect(body['stream'], isTrue);
        return http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n'
              'data: {"choices":[{"delta":{"content":" there"}}]}\n\n'
              'data: [DONE]\n\n',
            ),
          ),
          200,
        );
      }),
    );

    final replies = await provider
        .streamChat(
          systemPrompt: 'Be helpful',
          messages: <ChatMessage>[ChatMessage.user('Hi')],
        )
        .toList();

    expect(
      captured.url.toString(),
      'https://api.groq.com/openai/v1/chat/completions',
    );
    expect(captured.headers['authorization'], 'Bearer test-key');
    expect(replies, const <AiReply>[
      AiReply(text: 'Hello'),
      AiReply(text: 'Hello there'),
    ]);
  });

  test('existing Test Connection service uses the Groq provider', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'test-key');
    var requests = 0;
    final provider = GroqProvider(
      keyStore: keys,
      client: MockClient((request) async {
        requests++;
        expect(
          request.url.toString(),
          'https://api.groq.com/openai/v1/chat/completions',
        );
        return http.Response('{"choices":[{"message":{"content":"OK"}}]}', 200);
      }),
    );
    final connectionTester = ProviderConnectionService(
      providers: <AiProviderType, AiProvider>{AiProviderType.groq: provider},
      settingsStore: InMemorySettingsStore(),
    );

    final result = await connectionTester.testConnection(AiProviderType.groq);

    expect(result.status, ConnectionTestStatus.success);
    expect(requests, 1);
  });

  test('asks the chosen model and lists models with the key', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'test-key');
    final requests = <http.Request>[];
    final provider = GroqProvider(
      keyStore: keys,
      client: MockClient((request) async {
        requests.add(request);
        return request.method == 'GET'
            ? http.Response(
                '{"object":"list","data":['
                '{"id":"openai/gpt-oss-120b","active":true},'
                '{"id":"llama-3.3-70b-versatile","active":false},'
                '{"id":"whisper-large-v3","active":true}]}',
                200,
              )
            : http.Response('{"choices":[{"message":{"content":"Hi"}}]}', 200);
      }),
    );
    await provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Hi')],
      model: 'openai/gpt-oss-120b',
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['model'], 'openai/gpt-oss-120b');

    expect(await provider.listModels(), <String>['openai/gpt-oss-120b']);
    expect(
      requests.last.url.toString(),
      'https://api.groq.com/openai/v1/models',
    );
    expect(requests.last.headers['authorization'], 'Bearer test-key');
  });
}
