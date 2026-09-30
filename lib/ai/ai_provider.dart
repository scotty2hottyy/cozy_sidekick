import '../models/chat_message.dart';

enum AiProviderType {
  openRouter(
    'OpenRouter',
    secretLabel: 'API key',
    keyUrl: 'https://openrouter.ai/keys',
    defaultModel: 'openrouter/free',
    suggestedModels: <String>[
      'openrouter/free',
      'openai/gpt-6-luna',
      'deepseek/deepseek-v4-flash',
      'google/gemini-3.5-flash-lite',
      'anthropic/claude-sonnet-5.5',
    ],
  ),
  openAi(
    'OpenAI',
    secretLabel: 'API key',
    keyUrl: 'https://platform.openai.com/api-keys',
    defaultModel: 'gpt-6-luna',
    suggestedModels: <String>['gpt-6-luna', 'gpt-6-sol', 'gpt-6-astra'],
  ),
  groq(
    'Groq',
    secretLabel: 'API key',
    keyUrl: 'https://console.groq.com/keys',
    defaultModel: 'openai/gpt-oss-20b',
    suggestedModels: <String>[
      'openai/gpt-oss-20b',
      'openai/gpt-oss-120b',
      'qwen/qwen3.8-27b',
    ],
  ),
  customServer('Custom Server', secretLabel: 'Access token');

  const AiProviderType(
    this.displayName, {
    required this.secretLabel,
    this.keyUrl,
    this.defaultModel,
    this.suggestedModels = const <String>[],
  });

  final String displayName;
  final String secretLabel;
  final String? keyUrl;

  /// The model used until the user picks another. Null when the provider
  /// picks its own, like the custom server.
  final String? defaultModel;

  /// The models AI Settings offers first, starting with [defaultModel]. The
  /// IDs are copied from each provider's models page, because names change
  /// often. Keep the default cheap.
  final List<String> suggestedModels;
}

/// What a provider sends back for one chat request.
class AiReply {
  const AiReply({required this.text, this.reasoning, this.totalTokens});

  /// The answer to show in the chat.
  final String text;

  /// The model's thinking before it answered, or null when it didn't share
  /// any.
  final String? reasoning;

  /// The provider's total input and output token usage, when reported.
  final int? totalTokens;

  @override
  bool operator ==(Object other) =>
      other is AiReply &&
      other.text == text &&
      other.reasoning == reasoning &&
      other.totalTokens == totalTokens;

  @override
  int get hashCode => Object.hash(text, reasoning, totalTokens);

  @override
  String toString() => 'AiReply("$text", reasoning: $reasoning)';
}

/// [model] is the model to ask, or null for the provider's default. Providers
/// that pick their own model, like the custom server, ignore it.
abstract interface class AiProvider {
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  });

  /// The reply as it's written. Each event is the whole reply so far, and
  /// the last event is the finished reply, the same one [sendChat] returns.
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
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
  const RateLimitException({this.retryAt}) : super('HTTP 429');

  final DateTime? retryAt;
}

class QuotaExhaustedException extends AiProviderException {
  const QuotaExhaustedException({this.resetAt})
    : super('No free AI route is currently available');

  final DateTime? resetAt;
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
