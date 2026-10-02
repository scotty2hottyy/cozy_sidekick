import '../models/chat_message.dart';
import '../models/quota_route.dart';
import '../services/usage_tracker.dart';
import 'ai_provider.dart';

class AutoRouter implements AiProvider {
  AutoRouter({
    required this.providers,
    required this.loadRoutes,
    required this.usageTracker,
    this.now = DateTime.now,
  });

  final Map<AiProviderType, AiProvider> providers;
  final Future<List<QuotaRoute>> Function() loadRoutes;
  final UsageTracker usageTracker;
  final DateTime Function() now;

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
    // The last error from a route that waiting can't fix, like an account
    // out of credit or a chat too long for the model.
    AiProviderException? lastUnfixable;
    DateTime? earliestReset;
    // The soonest a route that's only busy, after a 429, can be tried again.
    DateTime? earliestBusy;
    void busyUntil(DateTime retryAt) {
      if (earliestBusy == null || retryAt.isBefore(earliestBusy!)) {
        earliestBusy = retryAt;
      }
    }

    final nowUtc = now().toUtc();
    final midnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);

    for (final route in await loadRoutes()) {
      // A limit of 0 turns the route off for now. It hasn't run out, so it
      // has no reset time.
      if (!route.enabled || route.userLimit == 0) continue;
      final usage = await usageTracker.usageFor(route);
      // Blocked by a 429, or at the user's limit or the free quota the
      // provider last reported.
      final reset = usage.resetFor(route, nowUtc);
      if (reset != null) {
        if (earliestReset == null || reset.isBefore(earliestReset)) {
          earliestReset = reset;
        }
        if (usage.isBusy(route, nowUtc)) busyUntil(reset);
        continue;
      }

      final provider = providers[route.provider];
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
        await usageTracker.record(
          route,
          tokens: finished.totalTokens,
          quota: finished.freeQuota,
        );
        return;
      } on RateLimitException catch (error) {
        rateLimited = true;
        // Free models are often busy for a moment, so without a time from
        // the provider the route is tried again a second later.
        final retryAt =
            error.retryAt ?? now().toUtc().add(const Duration(seconds: 1));
        await usageTracker.block(route, until: retryAt);
        if (earliestReset == null || retryAt.isBefore(earliestReset)) {
          earliestReset = retryAt;
        }
        if (retryAt.isBefore(midnight)) busyUntil(retryAt);
      } on MissingApiKeyException {
        missingKey = true;
      } on OutOfCreditException catch (error) {
        // Another route may still work. This one isn't busy, so it isn't
        // blocked.
        lastUnfixable = error;
      } on RequestTooLargeException catch (error) {
        lastUnfixable = error;
      } on NetworkException {
        rethrow;
      }
    }

    // The user has to change something before that route works again, so
    // the chat says what.
    if (lastUnfixable != null) throw lastUnfixable;
    // A busy route can be tried again soon, so the chat says to wait a
    // moment rather than that the free routes are used up.
    if (earliestBusy != null) throw RateLimitException(retryAt: earliestBusy);
    if (missingKey && !rateLimited && earliestReset == null) {
      throw const MissingApiKeyException();
    }
    throw QuotaExhaustedException(resetAt: earliestReset ?? midnight);
  }
}
