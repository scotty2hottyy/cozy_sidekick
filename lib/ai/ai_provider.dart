import '../models/chat_message.dart';

enum AiProviderType {
  openRouter(
    'OpenRouter',
    secretLabel: 'API key',
    keyUrl: 'https://openrouter.ai/keys',
  ),
  openAi(
    'OpenAI',
    secretLabel: 'API key',
    keyUrl: 'https://platform.openai.com/api-keys',
  ),
  xai('Grok (xAI)', secretLabel: 'API key', keyUrl: 'https://console.x.ai'),
  customServer('Custom Server', secretLabel: 'Access token');

  const AiProviderType(
    this.displayName, {
    required this.secretLabel,
    this.keyUrl,
  });

  final String displayName;
  final String secretLabel;
  final String? keyUrl;
}

abstract interface class AiProvider {
  Future<String> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  });
}

sealed class AiProviderException implements Exception {
  const AiProviderException(this.debugMessage);
  final String debugMessage;

  String get userMessage => 'The AI provider could not complete the request.';

  @override
  String toString() => '$runtimeType: $debugMessage';
}

class MissingApiKeyException extends AiProviderException {
  const MissingApiKeyException() : super('No credential saved');
  @override
  String get userMessage => 'Add this provider’s credential in Settings.';
}

class InvalidApiKeyException extends AiProviderException {
  const InvalidApiKeyException() : super('HTTP 401/403');
  @override
  String get userMessage => 'The saved credential was not accepted.';
}

class RateLimitException extends AiProviderException {
  const RateLimitException() : super('HTTP 429');
  @override
  String get userMessage =>
      'The provider rate limit was reached. Try again later.';
}

class ProviderUnavailableException extends AiProviderException {
  const ProviderUnavailableException() : super('HTTP 5xx');
  @override
  String get userMessage => 'The provider is temporarily unavailable.';
}

class NetworkException extends AiProviderException {
  const NetworkException() : super('Could not connect');
  @override
  String get userMessage =>
      'Could not reach the provider. Check your connection.';
}

class ProviderTimeoutException extends AiProviderException {
  const ProviderTimeoutException() : super('Request timed out');
  @override
  String get userMessage => 'The provider took too long to respond.';
}

class ProviderConfigurationException extends AiProviderException {
  const ProviderConfigurationException(super.debugMessage);
  @override
  String get userMessage => 'The provider configuration is invalid.';
}

class BadResponseException extends AiProviderException {
  const BadResponseException(super.debugMessage);
  @override
  String get userMessage => 'The provider returned an invalid response.';
}
