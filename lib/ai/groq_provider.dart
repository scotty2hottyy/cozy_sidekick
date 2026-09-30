import '../models/free_quota.dart';
import 'ai_provider.dart';
import 'openai_compatible_provider.dart';

class GroqProvider extends OpenAiCompatibleProvider {
  GroqProvider({required super.keyStore, super.client})
    : super(
        type: AiProviderType.groq,
        baseUrl: 'https://api.groq.com/openai/v1',
        model: AiProviderType.groq.defaultModel!,
        // Groq has no quota endpoint, but every reply reports it.
        freeQuotaFromHeaders: FreeQuota.fromGroqHeaders,
      );
}
