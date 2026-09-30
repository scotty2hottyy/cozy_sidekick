import '../ai/ai_provider.dart';
import '../ai/openai_compatible_provider.dart';
import '../models/openai_free_tier.dart';

abstract interface class ModelLister {
  /// Every chat model [provider] offers, sorted. Throws an
  /// [AiProviderException] when the list can't be loaded.
  Future<List<String>> listModels(AiProviderType provider);

  /// The chat models [provider] offers for free. A listed provider's default
  /// model comes first. Throws an [AiProviderException] when the list can't
  /// be loaded.
  Future<List<String>> listFreeModels(AiProviderType provider);
}

/// Loads each provider's live model list for AI Settings.
class ModelListService implements ModelLister {
  ModelListService({required Map<AiProviderType, AiProvider> providers})
    : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final Map<AiProviderType, AiProvider> _providers;

  @override
  Future<List<String>> listModels(AiProviderType provider) async =>
      _listed(provider).listModels();

  @override
  Future<List<String>> listFreeModels(AiProviderType provider) async {
    // OpenAI doesn't list its free models, so they're the ones offered from
    // each group of its free-token article.
    if (provider == AiProviderType.openAi) return OpenAiFreeTier.allModels;
    final models = provider == AiProviderType.groq
        // Every model on Groq's free plan is free, within its daily limits.
        ? await _listed(provider).listModels()
        : await _listed(provider).listModels(freeOnly: true);
    final first = provider.defaultModel;
    return <String>[
      if (models.contains(first)) first!,
      for (final model in models)
        if (model != first) model,
    ];
  }

  OpenAiCompatibleProvider _listed(AiProviderType provider) {
    final implementation = _providers[provider];
    // Only the OpenAI-compatible APIs have a list. The custom server picks
    // its own model.
    if (implementation is! OpenAiCompatibleProvider) {
      throw ProviderConfigurationException(
        'No model list for ${provider.name}',
      );
    }
    return implementation;
  }
}
