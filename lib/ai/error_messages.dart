import 'ai_provider.dart';

/// A short, friendly message for [e] that is safe to show the user.
///
/// The switch is exhaustive, so a new [AiProviderException] subtype won't
/// compile until it has a message here.
String friendlyMessage(AiProviderException e) => switch (e) {
  MissingApiKeyException() => 'Add a key in Settings to start chatting.',
  InvalidApiKeyException() => "That key wasn't accepted. Check it in Settings.",
  RateLimitException() =>
    'Too many messages right now. Wait a moment and try again.',
  ProviderUnavailableException() =>
    'The AI service is having trouble. Try again soon.',
  NetworkException() => "Can't connect. Check your internet connection.",
  ProviderTimeoutException() => 'That took too long. Please try again.',
  BadResponseException() => 'Got an unexpected reply. Please try again.',
  ProviderConfigurationException() =>
    "This provider isn't set up correctly. Check it in Settings.",
};

/// Whether the user fixes [e] in Settings rather than by trying again.
bool needsSettings(AiProviderException e) => switch (e) {
  MissingApiKeyException() ||
  InvalidApiKeyException() ||
  ProviderConfigurationException() => true,
  RateLimitException() ||
  ProviderUnavailableException() ||
  NetworkException() ||
  ProviderTimeoutException() ||
  BadResponseException() => false,
};
