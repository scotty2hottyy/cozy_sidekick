import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class XaiProvider extends OpenAiCompatibleProvider {
  XaiProvider({required super.keyStore, super.client})
    : super(
        type: AiProviderType.xai,
        baseUrl: 'https://api.x.ai/v1',
        model: 'grok-4.3',
      );
}
