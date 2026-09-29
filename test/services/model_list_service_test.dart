import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/custom_server_provider.dart';
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
}
