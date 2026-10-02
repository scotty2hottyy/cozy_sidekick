import '../ai/ai_provider.dart';
import '../models/chat_message.dart';
import 'settings_service.dart';

enum ConnectionTestStatus {
  success,
  noCredential,
  invalidCredential,
  modelNotAvailable,
  outOfCredit,
  requestTooLarge,
  rateLimit,
  networkUnavailable,
  providerUnavailable,
  invalidConfiguration,
  invalidResponse,
  otherError,
}

class ConnectionTestResult {
  const ConnectionTestResult(this.status);
  final ConnectionTestStatus status;

  bool get isSuccess => status == ConnectionTestStatus.success;
  String get message => switch (status) {
    ConnectionTestStatus.success => 'Connection successful',
    ConnectionTestStatus.noCredential => 'No credential saved',
    ConnectionTestStatus.invalidCredential =>
      'Authentication failed. Check the saved credential.',
    ConnectionTestStatus.modelNotAvailable =>
      "The credential was accepted, but the model isn't available for this "
          'account.',
    ConnectionTestStatus.outOfCredit =>
      'The credential was accepted, but the account is out of credit.',
    ConnectionTestStatus.requestTooLarge =>
      'The request was too large for this model.',
    ConnectionTestStatus.rateLimit => 'Rate limit reached. Try again later.',
    ConnectionTestStatus.networkUnavailable =>
      'Network unavailable or the request timed out.',
    ConnectionTestStatus.providerUnavailable =>
      'The provider is temporarily unavailable.',
    ConnectionTestStatus.invalidConfiguration =>
      'The provider configuration is missing or invalid.',
    ConnectionTestStatus.invalidResponse =>
      'The provider returned an invalid response.',
    ConnectionTestStatus.otherError => 'Connection test failed.',
  };
}

abstract interface class ConnectionTester {
  Future<ConnectionTestResult> testConnection(AiProviderType provider);
}

/// Tests a provider with the model chosen for it, the same one chat uses.
class ProviderConnectionService implements ConnectionTester {
  ProviderConnectionService({
    required Map<AiProviderType, AiProvider> providers,
    required this.settingsStore,
  }) : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final Map<AiProviderType, AiProvider> _providers;
  final AppSettingsStore settingsStore;

  @override
  Future<ConnectionTestResult> testConnection(AiProviderType provider) async {
    final implementation = _providers[provider];
    if (implementation == null) {
      return const ConnectionTestResult(
        ConnectionTestStatus.providerUnavailable,
      );
    }
    try {
      await implementation.sendChat(
        systemPrompt: 'This is a connection test.',
        messages: <ChatMessage>[ChatMessage.user('Reply with OK.')],
        model: await settingsStore.loadModel(provider),
      );
      return const ConnectionTestResult(ConnectionTestStatus.success);
    } on MissingApiKeyException {
      return const ConnectionTestResult(ConnectionTestStatus.noCredential);
    } on InvalidApiKeyException {
      return const ConnectionTestResult(ConnectionTestStatus.invalidCredential);
    } on ModelNotAvailableException {
      return const ConnectionTestResult(ConnectionTestStatus.modelNotAvailable);
    } on OutOfCreditException {
      return const ConnectionTestResult(ConnectionTestStatus.outOfCredit);
    } on RequestTooLargeException {
      return const ConnectionTestResult(ConnectionTestStatus.requestTooLarge);
    } on RateLimitException {
      return const ConnectionTestResult(ConnectionTestStatus.rateLimit);
    } on NetworkException catch (_) {
      return const ConnectionTestResult(
        ConnectionTestStatus.networkUnavailable,
      );
    } on ProviderTimeoutException catch (_) {
      return const ConnectionTestResult(
        ConnectionTestStatus.networkUnavailable,
      );
    } on ProviderUnavailableException {
      return const ConnectionTestResult(
        ConnectionTestStatus.providerUnavailable,
      );
    } on ProviderConfigurationException {
      return const ConnectionTestResult(
        ConnectionTestStatus.invalidConfiguration,
      );
    } on BadResponseException {
      return const ConnectionTestResult(ConnectionTestStatus.invalidResponse);
    } on Object {
      // An Error too, like dart:io's ArgumentError for a bad port, so the
      // Test Connection button can't stay on "Testing…".
      return const ConnectionTestResult(ConnectionTestStatus.otherError);
    }
  }
}
