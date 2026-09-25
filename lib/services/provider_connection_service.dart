import '../ai/ai_provider.dart';
import '../models/chat_message.dart';

enum ConnectionTestStatus {
  success,
  noCredential,
  invalidCredential,
  modelNotAvailable,
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

class ProviderConnectionService implements ConnectionTester {
  ProviderConnectionService({
    required Map<AiProviderType, AiProvider> providers,
  }) : _providers = Map<AiProviderType, AiProvider>.unmodifiable(providers);

  final Map<AiProviderType, AiProvider> _providers;

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
      );
      return const ConnectionTestResult(ConnectionTestStatus.success);
    } on MissingApiKeyException {
      return const ConnectionTestResult(ConnectionTestStatus.noCredential);
    } on InvalidApiKeyException {
      return const ConnectionTestResult(ConnectionTestStatus.invalidCredential);
    } on ModelNotAvailableException {
      return const ConnectionTestResult(ConnectionTestStatus.modelNotAvailable);
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
    } on Exception {
      return const ConnectionTestResult(ConnectionTestStatus.otherError);
    }
  }
}
