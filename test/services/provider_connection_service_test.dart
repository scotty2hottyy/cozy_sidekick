import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
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
        settingsStore: InMemorySettingsStore(),
      );
      final result = await service.testConnection(AiProviderType.openRouter);
      expect(result.status, entry.value);
      expect(result.message, isNotEmpty);
    }
  });

  test('tests the model saved for the provider', () async {
    final provider = _ResultProvider(null);
    final settings = InMemorySettingsStore();
    final service = ProviderConnectionService(
      providers: <AiProviderType, AiProvider>{AiProviderType.openAi: provider},
      settingsStore: settings,
    );

    await service.testConnection(AiProviderType.openAi);
    expect(provider.lastModel, isNull);

    await settings.saveModel(AiProviderType.openAi, 'gpt-6-sol');
    await service.testConnection(AiProviderType.openAi);
    expect(provider.lastModel, 'gpt-6-sol');
  });

  test(
    'an Error from the provider is a failed test, not a stuck one',
    () async {
      // dart:io's error for a URL with a port like 80800.
      for (final error in <Object>[
        ArgumentError('Invalid port 80800'),
        StateError('internal detail'),
        const FormatException('bad'),
      ]) {
        final service = ProviderConnectionService(
          providers: <AiProviderType, AiProvider>{
            AiProviderType.customServer: _ResultProvider(error),
          },
          settingsStore: InMemorySettingsStore(),
        );
        final result = await service.testConnection(
          AiProviderType.customServer,
        );
        expect(
          result.status,
          ConnectionTestStatus.otherError,
          reason: '$error',
        );
        expect(result.message, 'Connection test failed.');
      }
    },
  );

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
  String? lastModel;
  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async {
    lastModel = model;
    if (error != null) throw error!;
    return const AiReply(text: 'OK');
  }

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) => Stream<AiReply>.fromFuture(
    sendChat(systemPrompt: systemPrompt, messages: messages),
  );
}
