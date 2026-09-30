import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/free_quota_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    "reads OpenRouter's free limit and remaining with the saved key",
    () async {
      final keys = InMemoryApiKeyStore();
      await keys.save(AiProviderType.openRouter, 'router-key');
      late http.Request sent;
      final service = FreeQuotaService(
        keyStore: keys,
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'is_free_tier': false,
                'free_model_daily_requests': <String, Object?>{
                  'limit': 1000,
                  'used': 12,
                  'remaining': 988,
                },
              },
            }),
            200,
          );
        }),
      );

      expect(
        await service.read(AiProviderType.openRouter),
        const FreeQuota(limit: 1000, remaining: 988),
      );
      expect(sent.method, 'GET');
      expect(sent.url.toString(), 'https://openrouter.ai/api/v1/key');
      expect(sent.headers['authorization'], 'Bearer router-key');
    },
  );

  test('makes no request without a key, or for Groq and OpenAI', () async {
    final keys = InMemoryApiKeyStore();
    var requests = 0;
    final service = FreeQuotaService(
      keyStore: keys,
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    expect(await service.read(AiProviderType.openRouter), isNull);
    await keys.save(AiProviderType.groq, 'groq-key');
    await keys.save(AiProviderType.openAi, 'openai-key');
    expect(await service.read(AiProviderType.groq), isNull);
    expect(await service.read(AiProviderType.openAi), isNull);
    expect(requests, 0);
  });
}
