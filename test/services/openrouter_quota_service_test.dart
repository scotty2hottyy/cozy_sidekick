import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/openrouter_quota_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads OpenRouter free requests remaining with the saved key', () async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'router-key');
    late http.Request sent;
    final service = OpenRouterQuotaService(
      keyStore: keys,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'free_model_daily_requests': <String, Object?>{'remaining': 12},
            },
          }),
          200,
        );
      }),
    );

    expect(await service.freeRequestsRemaining(), 12);
    expect(sent.url.toString(), 'https://openrouter.ai/api/v1/key');
    expect(sent.headers['authorization'], 'Bearer router-key');
  });

  test('does not make an OpenRouter request without a key', () async {
    var requests = 0;
    final service = OpenRouterQuotaService(
      keyStore: InMemoryApiKeyStore(),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    expect(await service.freeRequestsRemaining(), isNull);
    expect(requests, 0);
  });
}
