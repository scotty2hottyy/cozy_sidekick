import 'package:http/http.dart' as http;

import '../ai/ai_provider.dart';
import '../ai/http_helper.dart';
import '../models/free_quota.dart';
import 'api_key_store.dart';

abstract interface class FreeQuotaReader {
  /// [provider]'s free daily quota, as its API reports it. Null when the
  /// provider has no endpoint for it or no key is saved.
  Future<FreeQuota?> read(AiProviderType provider);
}

/// Reads the free quotas that have an endpoint: only OpenRouter's.
///
/// OpenRouter's key endpoint reports the free requests left today for the
/// whole account, whatever the model, and reading it is free. Groq has no
/// such endpoint. It reports each model's quota in the headers of its
/// replies, which the auto-router saves. OpenAI reports nothing.
class FreeQuotaService implements FreeQuotaReader {
  FreeQuotaService({required this.keyStore, http.Client? client})
    : _client = client ?? http.Client();

  final ApiKeyStore keyStore;
  final http.Client _client;

  @override
  Future<FreeQuota?> read(AiProviderType provider) async {
    if (provider != AiProviderType.openRouter) return null;
    final key = await keyStore.read(provider);
    if (key == null || key.trim().isEmpty) return null;
    final response = await getJson(
      _client,
      Uri.parse('https://openrouter.ai/api/v1/key'),
      headers: <String, String>{'Authorization': 'Bearer $key'},
    );
    final data = response['data'];
    final freeRequests = data is Map<String, dynamic>
        ? data['free_model_daily_requests']
        : null;
    if (freeRequests is! Map<String, dynamic>) return null;
    final limit = freeRequests['limit'];
    final remaining = freeRequests['remaining'];
    if (limit is! num || remaining is! num || limit < 0 || remaining < 0) {
      return null;
    }
    return FreeQuota(
      limit: limit.toInt(),
      remaining: remaining.clamp(0, limit).toInt(),
    );
  }
}
