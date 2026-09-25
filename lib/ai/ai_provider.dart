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

/// [debugMessage] is for logs only. Show users `friendlyMessage` from
/// `error_messages.dart` instead.
sealed class AiProviderException implements Exception {
  const AiProviderException(this.debugMessage);
  final String debugMessage;

  @override
  String toString() => '$runtimeType: $debugMessage';
}

class MissingApiKeyException extends AiProviderException {
  const MissingApiKeyException() : super('No credential saved');
}

class InvalidApiKeyException extends AiProviderException {
  const InvalidApiKeyException() : super('HTTP 401/403');
}

class ModelNotAvailableException extends AiProviderException {
  const ModelNotAvailableException(super.debugMessage);
}

class RateLimitException extends AiProviderException {
  const RateLimitException() : super('HTTP 429');
}

class ProviderUnavailableException extends AiProviderException {
  const ProviderUnavailableException() : super('HTTP 5xx');
}

class NetworkException extends AiProviderException {
  const NetworkException() : super('Could not connect');
}

class ProviderTimeoutException extends AiProviderException {
  const ProviderTimeoutException() : super('Request timed out');
}

class ProviderConfigurationException extends AiProviderException {
  const ProviderConfigurationException(super.debugMessage);
}

class BadResponseException extends AiProviderException {
  const BadResponseException(super.debugMessage);
}
