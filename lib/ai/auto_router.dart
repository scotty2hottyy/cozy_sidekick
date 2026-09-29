import '../models/chat_message.dart';
import '../models/quota_route.dart';
import '../services/usage_tracker.dart';
import 'ai_provider.dart';

class AutoRouter implements AiProvider {
  AutoRouter({
    required Map<AiProviderType, AiProvider> providers,
    required Future<List<QuotaRoute>> Function() loadRoutes,
    required this.usageTracker,
    DateTime Function()? now,
  }) : _providers = providers,
       _loadRoutes = loadRoutes,
       _now = now ?? DateTime.now;

  final Map<AiProviderType, AiProvider> _providers;
  final Future<List<QuotaRoute>> Function() _loadRoutes;
  final UsageTracker usageTracker;
  final DateTime Function() _now;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) => streamChat(
    systemPrompt: systemPrompt,
    messages: messages,
    abortTrigger: abortTrigger,
  ).last;

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async* {
    var rateLimited = false;
    var missingKey = false;
    DateTime? earliestReset;
    final now = _now().toUtc();
    final midnight = DateTime.utc(now.year, now.month, now.day + 1);

    for (final route in await _loadRoutes()) {
      if (!route.enabled) continue;
      final usage = await usageTracker.usageFor(route);
      final blocked = usage.blockedUntil?.isAfter(now) ?? false;
      final usedUp =
          route.dailyLimit != null && usage.usedFor(route) >= route.dailyLimit!;
      if (blocked || usedUp) {
        final reset = blocked ? usage.blockedUntil! : midnight;
        if (earliestReset == null || reset.isBefore(earliestReset)) {
          earliestReset = reset;
        }
        continue;
      }

      final provider = _providers[route.provider];
      if (provider == null) continue;

      try {
        AiReply? finished;
        await for (final reply in provider.streamChat(
          systemPrompt: systemPrompt,
          messages: messages,
          abortTrigger: abortTrigger,
          model: route.model,
        )) {
          finished = reply;
          yield reply;
        }
        if (finished == null) {
          throw const BadResponseException('The provider sent no reply');
        }
        await usageTracker.record(route, tokens: finished.totalTokens);
        return;
      } on RateLimitException catch (error) {
        rateLimited = true;
        final retryAt =
            error.retryAt ?? _now().toUtc().add(const Duration(minutes: 1));
        await usageTracker.block(route, until: retryAt);
        if (earliestReset == null || retryAt.isBefore(earliestReset)) {
          earliestReset = retryAt;
        }
      } on MissingApiKeyException {
        missingKey = true;
      } on NetworkException {
        rethrow;
      }
    }

    if (missingKey && !rateLimited && earliestReset == null) {
      throw const MissingApiKeyException();
    }
    throw QuotaExhaustedException(resetAt: earliestReset ?? midnight);
  }
}
