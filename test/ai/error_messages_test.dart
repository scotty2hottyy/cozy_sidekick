import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/error_messages.dart';
import 'package:cozy_sidekick/ai/openai_provider.dart';
import 'package:cozy_sidekick/ai/openrouter_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const errors = <AiProviderException>[
    MissingApiKeyException(),
    InvalidApiKeyException(),
    ModelNotAvailableException('HTTP 403 model_not_found'),
    RateLimitException(),
    ProviderUnavailableException(),
    NetworkException(),
    ProviderTimeoutException(),
    BadResponseException('HTTP 418'),
    ProviderConfigurationException('Custom server URL is missing'),
  ];

  test('every exception type has its own friendly message', () {
    for (final error in errors) {
      expect(friendlyMessage(error), isNotEmpty);
      expect(friendlyMessage(error), isNot(contains(error.debugMessage)));
    }
    expect(errors.map(friendlyMessage).toSet(), hasLength(errors.length));
  });

  test('only key and setup problems point to Settings', () {
    expect(errors.where(needsSettings).map((e) => e.runtimeType), <Type>[
      MissingApiKeyException,
      InvalidApiKeyException,
      ModelNotAvailableException,
      ProviderConfigurationException,
    ]);
  });

  test('a 429 from the provider asks the user to wait', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'key');
    final provider = OpenRouterProvider(
      keyStore: keys,
      client: MockClient((_) async => http.Response('{}', 429)),
    );
    await expectLater(
      provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(
        isA<RateLimitException>().having(
          friendlyMessage,
          'friendly message',
          'Too many messages right now. Wait a moment and try again.',
        ),
      ),
    );
  });

  test("a model OpenAI won't serve isn't blamed on the key", () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openAi, 'key');
    final provider = OpenAiProvider(
      keyStore: keys,
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"message":"Project `proj_abc` does not have access to '
          'model `gpt-6-luna`","type":"invalid_request_error","param":null,'
          '"code":"model_not_found"}}',
          403,
        ),
      ),
    );
    await expectLater(
      provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(
        isA<ModelNotAvailableException>().having(
          friendlyMessage,
          'friendly message',
          "This model isn't available for your account. Check the model or "
              "your provider's settings.",
        ),
      ),
    );
  });
}
