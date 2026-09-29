import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class GroqProvider extends OpenAiCompatibleProvider {
  GroqProvider({required super.keyStore, super.client})
    : super(
        type: AiProviderType.groq,
        baseUrl: 'https://api.groq.com/openai/v1',
        model: 'openai/gpt-oss-20b',
      );
}
