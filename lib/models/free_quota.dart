import 'dart:math';

/// A provider's free daily allowance of requests, as its API reported it.
class FreeQuota {
  const FreeQuota({required this.limit, required this.remaining});

  /// The free requests allowed per day.
  final int limit;

  /// The free requests left right now.
  final int remaining;

  int get used => max(0, limit - remaining);

  /// The requests-per-day limit Groq sends in the headers of every reply,
  /// or null when [headers] don't have it. Each model has its own.
  ///
  /// Groq's `x-ratelimit-*-requests` headers always count requests per day,
  /// and the `-tokens` ones count tokens per minute, so only the requests
  /// headers are read. The day refills gradually rather than at midnight, so
  /// [remaining] is what's free now.
  static FreeQuota? fromGroqHeaders(Map<String, String> headers) {
    final limit = int.tryParse(headers['x-ratelimit-limit-requests'] ?? '');
    final remaining = int.tryParse(
      headers['x-ratelimit-remaining-requests'] ?? '',
    );
    if (limit == null || remaining == null || limit < 0 || remaining < 0) {
      return null;
    }
    return FreeQuota(limit: limit, remaining: min(remaining, limit));
  }

  @override
  bool operator ==(Object other) =>
      other is FreeQuota &&
      other.limit == limit &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(limit, remaining);

  @override
  String toString() => 'FreeQuota($remaining of $limit left)';
}
