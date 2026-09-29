import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/ai/openai_compatible_provider.dart';
import 'package:cozy_sidekick/ai/openai_provider.dart';
import 'package:cozy_sidekick/ai/open_code_zen_provider.dart';
import 'package:cozy_sidekick/ai/openrouter_provider.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each API provider suggests its default model first', () {
    final keys = InMemoryApiKeyStore();
    for (final provider in <OpenAiCompatibleProvider>[
      OpenRouterProvider(keyStore: keys),
      OpenAiProvider(keyStore: keys),
      GroqProvider(keyStore: keys),
      OpenCodeZenProvider(keyStore: keys),
    ]) {
      final type = provider.type;
      expect(provider.model, type.defaultModel, reason: '$type');
      expect(type.suggestedModels.first, type.defaultModel, reason: '$type');
      expect(
        type.suggestedModels.toSet(),
        hasLength(type.suggestedModels.length),
        reason: '$type suggests a model twice',
      );
    }
  });

  test('the custom server picks its own model', () {
    expect(AiProviderType.customServer.defaultModel, isNull);
    expect(AiProviderType.customServer.suggestedModels, isEmpty);
  });
}
