import 'dart:convert';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/custom_server_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/ai/openai_provider.dart';
import 'package:cozy_sidekick/ai/openrouter_provider.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/model_list_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final keys = InMemoryApiKeyStore();
  final service = ModelListService(
    providers: <AiProviderType, AiProvider>{
      AiProviderType.openRouter: OpenRouterProvider(
        keyStore: keys,
        client: MockClient(
          (_) async => http.Response(
            '{"data":[{"id":"openrouter/free"},{"id":"openai/gpt-6-luna"}]}',
            200,
          ),
        ),
      ),
      AiProviderType.customServer: CustomServerProvider(
        keyStore: keys,
        settingsStore: InMemorySettingsStore(),
      ),
    },
  );

  test("lists an OpenAI-compatible provider's models", () async {
    expect(await service.listModels(AiProviderType.openRouter), <String>[
      'openai/gpt-6-luna',
      'openrouter/free',
    ]);
  });

  test('has no list for the custom server or a missing provider', () async {
    for (final provider in <AiProviderType>[
      AiProviderType.customServer,
      AiProviderType.groq,
    ]) {
      await expectLater(
        service.listModels(provider),
        throwsA(isA<ProviderConfigurationException>()),
        reason: '$provider',
      );
    }
  });

  group('free models', () {
    final requests = <http.Request>[];

    /// A service whose OpenRouter lists [openRouterModels], whose Groq
    /// lists [groqModels], and whose OpenAI answers nothing, with a Groq
    /// key saved when [withGroqKey] is true.
    Future<ModelListService> freeService({
      List<Map<String, Object?>> openRouterModels = const [],
      List<Map<String, Object?>> groqModels = const [],
      bool withGroqKey = true,
    }) async {
      requests.clear();
      final freeKeys = InMemoryApiKeyStore();
      if (withGroqKey) await freeKeys.save(AiProviderType.groq, 'test-key');
      http.Client listing(List<Map<String, Object?>> models) =>
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(<String, Object?>{'object': 'list', 'data': models}),
              200,
            );
          });
      return ModelListService(
        providers: <AiProviderType, AiProvider>{
          AiProviderType.openRouter: OpenRouterProvider(
            keyStore: freeKeys,
            client: listing(openRouterModels),
          ),
          AiProviderType.groq: GroqProvider(
            keyStore: freeKeys,
            client: listing(groqModels),
          ),
          AiProviderType.openAi: OpenAiProvider(
            keyStore: freeKeys,
            client: listing(const <Map<String, Object?>>[]),
          ),
          AiProviderType.customServer: CustomServerProvider(
            keyStore: freeKeys,
            settingsStore: InMemorySettingsStore(),
          ),
        },
      );
    }

    /// An OpenRouter chat model at [price].
    Map<String, Object?> openRouter(String id, {String price = '0'}) =>
        <String, Object?>{
          'id': id,
          'architecture': <String, Object?>{
            'output_modalities': <String>['text'],
          },
          'pricing': <String, Object?>{'prompt': price, 'completion': price},
        };

    test(
      "OpenRouter's free router comes first, then its :free models",
      () async {
        final service = await freeService(
          openRouterModels: <Map<String, Object?>>[
            openRouter('z-ai/glm-5:free'),
            openRouter('anthropic/claude-sonnet-5.5', price: '0.000003'),
            openRouter('openrouter/free'),
            openRouter('deepseek/deepseek-v4-flash:free'),
            openRouter('openrouter/auto', price: '-1'),
          ],
        );
        expect(
          await service.listFreeModels(AiProviderType.openRouter),
          <String>[
            'openrouter/free',
            'deepseek/deepseek-v4-flash:free',
            'z-ai/glm-5:free',
          ],
        );
        expect(
          requests.single.url.toString(),
          'https://openrouter.ai/api/v1/models',
        );
      },
    );

    test('a list without the default is just sorted', () async {
      final service = await freeService(
        openRouterModels: <Map<String, Object?>>[
          openRouter('z-ai/glm-5:free'),
          openRouter('deepseek/deepseek-v4-flash:free'),
        ],
      );
      expect(await service.listFreeModels(AiProviderType.openRouter), <String>[
        'deepseek/deepseek-v4-flash:free',
        'z-ai/glm-5:free',
      ]);
    });

    test('Groq lists all its chat models, its default first', () async {
      final service = await freeService(
        groqModels: <Map<String, Object?>>[
          <String, Object?>{'id': 'qwen/qwen3.8-27b', 'active': true},
          <String, Object?>{'id': 'openai/gpt-oss-120b', 'active': true},
          <String, Object?>{'id': 'openai/gpt-oss-20b', 'active': true},
          <String, Object?>{'id': 'llama-3.3-70b-versatile', 'active': true},
          <String, Object?>{'id': 'llama3-70b-8192', 'active': false},
          <String, Object?>{'id': 'whisper-large-v3', 'active': true},
        ],
      );
      expect(await service.listFreeModels(AiProviderType.groq), <String>[
        'openai/gpt-oss-20b',
        'llama-3.3-70b-versatile',
        'openai/gpt-oss-120b',
        'qwen/qwen3.8-27b',
      ]);
      expect(
        requests.single.url.toString(),
        'https://api.groq.com/openai/v1/models',
      );
      expect(requests.single.headers['authorization'], 'Bearer test-key');
    });

    test("Groq's list needs a key", () async {
      final service = await freeService(
        groqModels: <Map<String, Object?>>[
          <String, Object?>{'id': 'openai/gpt-oss-20b', 'active': true},
        ],
        withGroqKey: false,
      );
      await expectLater(
        service.listFreeModels(AiProviderType.groq),
        throwsA(isA<MissingApiKeyException>()),
      );
      expect(requests, isEmpty);
    });

    test("OpenAI's are the ones offered, without a request", () async {
      final service = await freeService();
      expect(await service.listFreeModels(AiProviderType.openAi), <String>[
        'gpt-6-sol',
        'gpt-5.6-terra',
      ]);
      expect(requests, isEmpty);
    });

    test('the custom server has no free models to list', () async {
      final service = await freeService();
      await expectLater(
        service.listFreeModels(AiProviderType.customServer),
        throwsA(isA<ProviderConfigurationException>()),
      );
      await expectLater(
        ModelListService(providers: <AiProviderType, AiProvider>{})
            .listFreeModels(AiProviderType.groq),
        throwsA(isA<ProviderConfigurationException>()),
      );
    });
  });
}
