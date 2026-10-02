import 'ai_provider.dart';

/// A short, friendly message for [e] that is safe to show the user.
///
/// The switch is exhaustive, so a new [AiProviderException] subtype won't
/// compile until it has a message here. [now] is for tests.
String friendlyMessage(AiProviderException e, {DateTime? now}) => switch (e) {
  MissingApiKeyException() => 'Add a key in Settings to start chatting.',
  InvalidApiKeyException() => "That key wasn't accepted. Check it in Settings.",
  ModelNotAvailableException() =>
    "This model isn't available for your account. Check the model or your "
        "provider's settings.",
  RateLimitException() => _rateLimitMessage(e, now ?? DateTime.now()),
  QuotaExhaustedException() => _quotaExhaustedMessage(e),
  OutOfCreditException() =>
    'Your account is out of credit. Add credit with the provider or pick a '
        'free model.',
  RequestTooLargeException() =>
    'This chat is too long for this model. Start a new chat or pick another '
        'model.',
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
  ModelNotAvailableException() ||
  OutOfCreditException() ||
  RequestTooLargeException() ||
  ProviderConfigurationException() => true,
  RateLimitException() ||
  QuotaExhaustedException() ||
  ProviderUnavailableException() ||
  NetworkException() ||
  ProviderTimeoutException() ||
  BadResponseException() => false,
};

/// Whether a wait until [retryAt] is short enough to call "a moment". AI
/// Settings words a busy route the same way.
bool isShortWait(DateTime retryAt, DateTime now) =>
    retryAt.toUtc().difference(now.toUtc()) < const Duration(minutes: 1);

/// [dateTime] in UTC, like "12:00 AM UTC".
String formatUtcTime(DateTime dateTime) {
  final time = dateTime.toUtc();
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'} UTC';
}

/// A daily limit can last hours, so a wait over a minute says until when.
String _rateLimitMessage(RateLimitException error, DateTime now) {
  final retryAt = error.retryAt;
  if (retryAt == null || isShortWait(retryAt, now)) {
    return 'Too many messages right now. Wait a moment and try again.';
  }
  return 'Too many messages right now. Try again after '
      '${formatUtcTime(retryAt)}.';
}

String _quotaExhaustedMessage(QuotaExhaustedException error) {
  final resetAt = error.resetAt;
  if (resetAt == null) return 'Free AI routes are used up. Try again later.';
  return 'Free AI routes are used up. Try again after '
      '${formatUtcTime(resetAt)}.';
}
