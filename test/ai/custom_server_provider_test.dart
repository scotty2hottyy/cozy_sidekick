import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/custom_server_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uses saved URL/token, ordered messages, and parses reply', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.customServer, 'token');
    late http.Request captured;
    final provider = CustomServerProvider(
      keyStore: keys,
      settingsStore: InMemorySettingsStore(
        customServerBaseUrl: 'https://example.com/',
      ),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"message":" hi "}', 200);
      }),
    );
    final reply = await provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('hello')],
    );
    expect(reply, const AiReply(text: 'hi'));
    expect(captured.url.toString(), 'https://example.com/chat');
    expect(captured.headers['authorization'], 'Bearer token');
    final messages =
        (jsonDecode(captured.body) as Map<String, dynamic>)['messages'] as List;
    expect(messages.map((e) => e['role']), <String>['system', 'user']);
  });

  test('streams its whole reply as one event', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.customServer, 'token');
    final provider = CustomServerProvider(
      keyStore: keys,
      settingsStore: InMemorySettingsStore(
        customServerBaseUrl: 'https://example.com',
      ),
      client: MockClient(
        (_) async => http.Response(
          '{"message":"No.","reasoning":"Try dividing by 7."}',
          200,
        ),
      ),
    );
    Stream<AiReply> stream() => provider.streamChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Is 1001 prime?')],
    );

    expect(await stream().toList(), const <AiReply>[
      AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
    ]);
    await keys.delete(AiProviderType.customServer);
    await expectLater(stream(), emitsError(isA<MissingApiKeyException>()));
  });

  test('reads optional reasoning and never sends it back', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.customServer, 'token');
    late http.Request captured;
    var response = '{"message":"No.","reasoning":" Try dividing by 7. "}';
    final provider = CustomServerProvider(
      keyStore: keys,
      settingsStore: InMemorySettingsStore(
        customServerBaseUrl: 'https://example.com',
      ),
      client: MockClient((request) async {
        captured = request;
        return http.Response(response, 200);
      }),
    );
    Future<AiReply> send() => provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[
        ChatMessage.user('Is 1001 prime?'),
        ChatMessage.assistant('Maybe.', reasoning: 'Earlier thinking'),
        ChatMessage.user('Are you sure?'),
      ],
    );

    expect(
      await send(),
      const AiReply(text: 'No.', reasoning: 'Try dividing by 7.'),
    );
    expect(captured.body, isNot(contains('Earlier thinking')));
    for (final body in <String>[
      '{"message":"No."}',
      '{"message":"No.","reasoning":"  "}',
      '{"message":"No.","reasoning":5}',
    ]) {
      response = body;
      expect(await send(), const AiReply(text: 'No.'), reason: body);
    }
  });

  test(
    'rejects missing config, missing token, auth, and malformed replies',
    () async {
      final keys = InMemoryApiKeyStore();
      final noConfig = CustomServerProvider(
        keyStore: keys,
        settingsStore: InMemorySettingsStore(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        noConfig.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
        throwsA(isA<ProviderConfigurationException>()),
      );
      final noToken = CustomServerProvider(
        keyStore: keys,
        settingsStore: InMemorySettingsStore(
          customServerBaseUrl: 'https://example.com',
        ),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        noToken.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
        throwsA(isA<MissingApiKeyException>()),
      );
      await keys.save(AiProviderType.customServer, 'token');
      final auth = CustomServerProvider(
        keyStore: keys,
        settingsStore: InMemorySettingsStore(
          customServerBaseUrl: 'https://example.com',
        ),
        client: MockClient((_) async => http.Response('{}', 403)),
      );
      await expectLater(
        auth.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
        throwsA(isA<InvalidApiKeyException>()),
      );
      final bad = CustomServerProvider(
        keyStore: keys,
        settingsStore: InMemorySettingsStore(
          customServerBaseUrl: 'https://example.com',
        ),
        client: MockClient((_) async => http.Response('{"message":""}', 200)),
      );
      await expectLater(
        bad.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
        throwsA(isA<BadResponseException>()),
      );
    },
  );

  test('ignores a model, because the server picks its own', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.customServer, 'token');
    late http.Request captured;
    final provider = CustomServerProvider(
      keyStore: keys,
      settingsStore: InMemorySettingsStore(
        customServerBaseUrl: 'https://example.com',
      ),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"message":"hi"}', 200);
      }),
    );
    await provider.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('hello')],
      model: 'gpt-6-sol',
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.keys, <String>['messages']);
    expect(captured.body, isNot(contains('gpt-6-sol')));
  });

  test('a saved URL only loses trailing slashes before /chat', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.customServer, 'token');
    for (final (saved, posted) in <(String, String)>[
      // Saving already dropped a typed /chat, so this one is the base.
      ('https://example.com/chat', 'https://example.com/chat/chat'),
      (' https://example.com/api// ', 'https://example.com/api/chat'),
    ]) {
      final urls = <Uri>[];
      final provider = CustomServerProvider(
        keyStore: keys,
        settingsStore: InMemorySettingsStore(customServerBaseUrl: saved),
        client: MockClient((request) async {
          urls.add(request.url);
          return http.Response('{"message":"hi"}', 200);
        }),
      );
      await provider.sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('hello')],
      );
      expect(urls, <Uri>[Uri.parse(posted)], reason: saved);
    }
  });

  test('a saved URL with a bad port is a setup problem', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.customServer, 'token');
    var sent = 0;
    final provider = CustomServerProvider(
      keyStore: keys,
      settingsStore: InMemorySettingsStore(
        customServerBaseUrl: 'http://192.168.1.10:80800',
      ),
      client: MockClient((_) async {
        sent++;
        return http.Response('{"message":"hi"}', 200);
      }),
    );
    await expectLater(
      provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<ProviderConfigurationException>()),
    );
    expect(sent, 0);
  });
}
