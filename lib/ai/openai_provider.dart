import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class OpenAiProvider extends OpenAiCompatibleProvider {
  OpenAiProvider({required super.keyStore, super.client})
    : super(
        type: AiProviderType.openAi,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-6-luna',
      );
}
