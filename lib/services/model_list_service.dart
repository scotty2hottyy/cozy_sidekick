import '../ai/ai_provider.dart';
import '../ai/openai_compatible_provider.dart';

abstract interface class ModelLister {
  /// Every chat model [provider] offers, sorted. Throws an
  /// [AiProviderException] when the list can't be loaded.
  Future<List<String>> listModels(AiProviderType provider);
}

/// Loads each provider's live model list for AI Settings.
class ModelListService implements ModelLister {
  ModelListService({required Map<AiProviderType, AiProvider> providers})
    : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final Map<AiProviderType, AiProvider> _providers;

  @override
  Future<List<String>> listModels(AiProviderType provider) async {
    final implementation = _providers[provider];
    // Only the OpenAI-compatible APIs have a list. The custom server picks
    // its own model.
    if (implementation is! OpenAiCompatibleProvider) {
      throw ProviderConfigurationException(
        'No model list for ${provider.name}',
      );
    }
    return implementation.listModels();
  }
}
