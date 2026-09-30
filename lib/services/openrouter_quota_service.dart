import 'package:http/http.dart' as http;

import '../ai/ai_provider.dart';
import '../ai/http_helper.dart';
import 'api_key_store.dart';

abstract interface class OpenRouterQuotaReader {
  Future<int?> freeRequestsRemaining();
}

class OpenRouterQuotaService implements OpenRouterQuotaReader {
  OpenRouterQuotaService({required this.keyStore, http.Client? client})
    : _client = client ?? http.Client();

  final ApiKeyStore keyStore;
  final http.Client _client;

  @override
  Future<int?> freeRequestsRemaining() async {
    final key = await keyStore.read(AiProviderType.openRouter);
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
    final remaining = freeRequests is Map<String, dynamic>
        ? freeRequests['remaining']
        : null;
    return remaining is num ? remaining.toInt() : null;
  }
}
