import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class OpenRouterProvider extends OpenAiCompatibleProvider {
  OpenRouterProvider({required super.keyStore, super.client})
    : super(
        type: AiProviderType.openRouter,
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'openrouter/free',
        extraHeaders: const <String, String>{'X-Title': 'Cozy Sidekick'},
      );
}
