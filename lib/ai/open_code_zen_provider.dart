import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class OpenCodeZenProvider extends OpenAiCompatibleProvider {
  OpenCodeZenProvider({required super.keyStore, super.client})
    : super(
        type: AiProviderType.openCodeZen,
        baseUrl: 'https://opencode.ai/zen/v1',
        model: AiProviderType.openCodeZen.defaultModel!,
      );
}