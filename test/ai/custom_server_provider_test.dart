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
    expect(reply, 'hi');
    expect(captured.url.toString(), 'https://example.com/chat');
    expect(captured.headers['authorization'], 'Bearer token');
    final messages =
        (jsonDecode(captured.body) as Map<String, dynamic>)['messages'] as List;
    expect(messages.map((e) => e['role']), <String>['system', 'user']);
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
}
