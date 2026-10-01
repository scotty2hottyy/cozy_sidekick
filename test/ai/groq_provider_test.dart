import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/ai/openai_provider.dart';
import 'package:cozy_sidekick/ai/openrouter_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
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

  group('free quota', () {
    // What Groq sends with every reply. Its token headers count tokens per
    // minute, so only the requests ones are its daily quota.
    const quotaHeaders = <String, String>{
      'x-ratelimit-limit-requests': '1000',
      'x-ratelimit-remaining-requests': '998',
      'x-ratelimit-limit-tokens': '8000',
      'x-ratelimit-remaining-tokens': '7400',
    };
    const quota = FreeQuota(limit: 1000, remaining: 998);

    test('a reply carries the quota from its headers', () async {
      final provider = await _answering(AiProviderType.groq, quotaHeaders);

      expect(
        await provider.sendChat(systemPrompt: 'system', messages: _hi),
        const AiReply(text: 'Hi', freeQuota: quota),
      );
      expect(
        (await provider.streamChat(systemPrompt: 'system', messages: _hi).last),
        const AiReply(text: 'Hi', freeQuota: quota),
      );
    });

    test('a reply without both requests headers has no quota', () async {
      for (final headers in <Map<String, String>>[
        <String, String>{},
        <String, String>{'x-ratelimit-limit-requests': '1000'},
        <String, String>{'x-ratelimit-remaining-requests': '998'},
        <String, String>{
          'x-ratelimit-limit-requests': '1000',
          'x-ratelimit-remaining-requests': 'soon',
        },
        <String, String>{
          'x-ratelimit-limit-tokens': '8000',
          'x-ratelimit-remaining-tokens': '7400',
        },
      ]) {
        final provider = await _answering(AiProviderType.groq, headers);
        expect(
          (await provider.sendChat(
            systemPrompt: 'system',
            messages: _hi,
          )).freeQuota,
          isNull,
          reason: '$headers',
        );
        expect(
          (await provider
                  .streamChat(systemPrompt: 'system', messages: _hi)
                  .last)
              .freeQuota,
          isNull,
          reason: '$headers',
        );
      }
    });

    test('only Groq reads its quota from the headers', () async {
      for (final type in <AiProviderType>[
        AiProviderType.openRouter,
        AiProviderType.openAi,
      ]) {
        final provider = await _answering(type, quotaHeaders);
        expect(
          await provider.sendChat(systemPrompt: 'system', messages: _hi),
          const AiReply(text: 'Hi'),
          reason: '$type',
        );
        expect(
          await provider.streamChat(systemPrompt: 'system', messages: _hi).last,
          const AiReply(text: 'Hi'),
          reason: '$type',
        );
      }
    });
  });
}

final List<ChatMessage> _hi = <ChatMessage>[ChatMessage.user('Hi')];

/// The [type]'s provider, with a saved key, whose API answers "Hi" with
/// [headers], streamed or not.
Future<AiProvider> _answering(
  AiProviderType type,
  Map<String, String> headers,
) async {
  final keys = InMemoryApiKeyStore();
  await keys.save(type, 'test-key');
  final client = MockClient.streaming((request, bodyStream) async {
    final body =
        jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(
          body['stream'] == true
              ? 'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n'
                    'data: [DONE]\n\n'
              : '{"choices":[{"message":{"content":"Hi"}}]}',
        ),
      ),
      200,
      headers: headers,
    );
  });
  return switch (type) {
    AiProviderType.groq => GroqProvider(keyStore: keys, client: client),
    AiProviderType.openRouter => OpenRouterProvider(
      keyStore: keys,
      client: client,
    ),
    AiProviderType.openAi => OpenAiProvider(keyStore: keys, client: client),
    AiProviderType.customServer => throw ArgumentError.value(type),
  };
}
