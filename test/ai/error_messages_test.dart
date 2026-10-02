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
    OutOfCreditException(),
    RequestTooLargeException(),
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

  test('only problems that trying again cannot fix point to Settings', () {
    expect(errors.where(needsSettings).map((e) => e.runtimeType), <Type>[
      MissingApiKeyException,
      InvalidApiKeyException,
      ModelNotAvailableException,
      OutOfCreditException,
      RequestTooLargeException,
      ProviderConfigurationException,
    ]);
  });

  test('credit and chat-length problems say what to change', () {
    expect(
      friendlyMessage(const OutOfCreditException()),
      'Your account is out of credit. Add credit with the provider or pick '
      'a free model.',
    );
    expect(
      friendlyMessage(const RequestTooLargeException()),
      'This chat is too long for this model. Start a new chat or pick '
      'another model.',
    );
  });

  group('a rate limit', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    String messageFor(DateTime? retryAt) =>
        friendlyMessage(RateLimitException(retryAt: retryAt), now: now);

    test('without a time or within a minute says to wait a moment', () {
      for (final retryAt in <DateTime?>[
        null,
        now.add(const Duration(seconds: 59)),
        now.subtract(const Duration(minutes: 5)),
      ]) {
        expect(
          messageFor(retryAt),
          'Too many messages right now. Wait a moment and try again.',
          reason: '$retryAt',
        );
      }
    });

    test('that lasts longer says when to try again, in UTC', () {
      expect(
        messageFor(now.add(const Duration(minutes: 1))),
        'Too many messages right now. Try again after 12:01 PM UTC.',
      );
      // A daily limit that resets at midnight UTC.
      expect(
        messageFor(DateTime.utc(2026, 10, 3)),
        'Too many messages right now. Try again after 12:00 AM UTC.',
      );
      // A local time is shown in UTC too.
      expect(
        messageFor(DateTime.utc(2026, 10, 2, 21, 30).toLocal()),
        'Too many messages right now. Try again after 9:30 PM UTC.',
      );
    });

    test('a far retry time from the provider reaches the message', () async {
      final keys = InMemoryApiKeyStore();
      await keys.save(AiProviderType.openRouter, 'key');
      final provider = OpenRouterProvider(
        keyStore: keys,
        client: MockClient(
          (_) async => http.Response(
            '{}',
            429,
            headers: <String, String>{'retry-after': '7200'},
          ),
        ),
      );
      await expectLater(
        provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
        throwsA(
          isA<RateLimitException>().having(
            friendlyMessage,
            'friendly message',
            startsWith('Too many messages right now. Try again after '),
          ),
        ),
      );
    });
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

  test("an OpenAI account without credit isn't told to wait", () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openAi, 'key');
    final provider = OpenAiProvider(
      keyStore: keys,
      client: MockClient(
        (_) async => http.Response(
          '{"error":{"message":"You exceeded your current quota.",'
          '"type":"insufficient_quota","param":null,'
          '"code":"insufficient_quota"}}',
          429,
        ),
      ),
    );
    await expectLater(
      provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(
        isA<OutOfCreditException>()
            .having(needsSettings, 'needs Settings', isTrue)
            .having(
              friendlyMessage,
              'friendly message',
              startsWith('Your account is out of credit.'),
            ),
      ),
    );
  });
}
