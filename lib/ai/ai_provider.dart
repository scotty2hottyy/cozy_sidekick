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

/// What a provider sends back for one chat request.
class AiReply {
  const AiReply({required this.text, this.reasoning});

  /// The answer to show in the chat.
  final String text;

  /// The model's thinking before it answered, or null when it didn't share
  /// any.
  final String? reasoning;

  @override
  bool operator ==(Object other) =>
      other is AiReply && other.text == text && other.reasoning == reasoning;

  @override
  int get hashCode => Object.hash(text, reasoning);

  @override
  String toString() => 'AiReply("$text", reasoning: $reasoning)';
}

abstract interface class AiProvider {
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  });

  /// The reply as it's written. Each event is the whole reply so far, and
  /// the last event is the finished reply, the same one [sendChat] returns.
  Stream<AiReply> streamChat({
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
  const ProviderUnavailableException([super.debugMessage = 'HTTP 5xx']);
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
