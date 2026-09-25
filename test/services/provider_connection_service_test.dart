import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports success and clean provider failures', () async {
    for (final entry in <Object?, ConnectionTestStatus>{
      null: ConnectionTestStatus.success,
      const MissingApiKeyException(): ConnectionTestStatus.noCredential,
      const InvalidApiKeyException(): ConnectionTestStatus.invalidCredential,
      const ModelNotAvailableException('HTTP 403 model_not_found'):
          ConnectionTestStatus.modelNotAvailable,
      const NetworkException(): ConnectionTestStatus.networkUnavailable,
      const ProviderConfigurationException('bad'):
          ConnectionTestStatus.invalidConfiguration,
      const BadResponseException('bad'): ConnectionTestStatus.invalidResponse,
    }.entries) {
      final service = ProviderConnectionService(
        providers: <AiProviderType, AiProvider>{
          AiProviderType.openRouter: _ResultProvider(entry.key),
        },
      );
      final result = await service.testConnection(AiProviderType.openRouter);
      expect(result.status, entry.value);
      expect(result.message, isNotEmpty);
    }
  });

  test('every status has its own message', () {
    final messages = ConnectionTestStatus.values.map(
      (status) => ConnectionTestResult(status).message,
    );
    expect(messages.toSet(), hasLength(ConnectionTestStatus.values.length));
  });
}

class _ResultProvider implements AiProvider {
  _ResultProvider(this.error);
  final Object? error;
  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async {
    if (error != null) throw error!;
    return const AiReply(text: 'OK');
  }
}
