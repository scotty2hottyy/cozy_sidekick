import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
import 'package:cozy_sidekick/models/quota_route.dart';
import 'package:cozy_sidekick/services/usage_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const QuotaRoute openRouterRoute = QuotaRoute(
  id: 'openrouter-free',
  provider: AiProviderType.openRouter,
  model: 'openrouter/free',
  unit: QuotaUnit.requests,
);

const QuotaRoute groqRoute = QuotaRoute(
  id: 'groq-free',
  provider: AiProviderType.groq,
  model: 'openai/gpt-oss-20b',
  unit: QuotaUnit.requests,
);

const QuotaRoute openAiRoute = QuotaRoute(
  id: 'openai-mini',
  provider: AiProviderType.openAi,
  model: 'gpt-5.6-terra',
  unit: QuotaUnit.tokens,
);

QuotaReading readingOf(
  String model, {
  required int limit,
  required int remaining,
  int requestsAtCheck = 0,
}) => QuotaReading(
  model: model,
  quota: FreeQuota(limit: limit, remaining: remaining),
  checkedAt: DateTime.utc(2026, 9, 30, 12),
  requestsAtCheck: requestsAtCheck,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'tracks requests, tokens, and blocks across tracker instances',
    () async {
      var now = DateTime.utc(2026, 9, 29, 12);
      const route = QuotaRoute(
        id: 'openrouter-free',
        provider: AiProviderType.openRouter,
        model: 'openrouter/free',
        unit: QuotaUnit.requests,
        userLimit: 2,
      );
      final tracker = UsageTracker(now: () => now);
      await tracker.record(route, tokens: 40);
      await tracker.block(route, until: now.add(const Duration(minutes: 5)));

      final restarted = UsageTracker(now: () => now);
      expect(
        await restarted.usageFor(route),
        RouteUsage(
          requests: 1,
          tokens: 40,
          blockedUntil: DateTime.utc(2026, 9, 29, 12, 5),
        ),
      );
      expect(await restarted.isUsedUpOrBlocked(route), isTrue);
      now = now.add(const Duration(minutes: 6));
      expect(await restarted.isUsedUpOrBlocked(route), isFalse);
      await restarted.record(route, tokens: 2);
      expect(await restarted.isUsedUpOrBlocked(route), isTrue);
    },
  );

  test('usage resets at midnight UTC', () async {
    var now = DateTime.utc(2026, 9, 29, 23, 59);
    const route = QuotaRoute(
      id: 'openai-mini',
      provider: AiProviderType.openAi,
      model: 'gpt-5.6-terra',
      unit: QuotaUnit.tokens,
      userLimit: 100,
    );
    final tracker = UsageTracker(now: () => now);
    await tracker.record(route, tokens: 80);
    expect((await tracker.usageFor(route)).tokens, 80);
    now = DateTime.utc(2026, 9, 30);
    expect(await tracker.usageFor(route), const RouteUsage());
  });

  group('RouteUsage', () {
    final usage = RouteUsage(
      requests: 3,
      reading: readingOf(
        'openrouter/free',
        limit: 50,
        remaining: 40,
        requestsAtCheck: 3,
      ),
    );

    test('a user limit below the free quota wins', () {
      final route = openRouterRoute.copyWith(userLimit: 20);
      expect(usage.freeQuotaFor(route), 50);
      expect(usage.limitFor(route), 20);
      expect(usage.leftFor(route), 10);
    });

    test('a user limit at or above the free quota uses the quota', () {
      expect(usage.limitFor(openRouterRoute.copyWith(userLimit: 50)), 50);
      expect(usage.limitFor(openRouterRoute.copyWith(userLimit: 80)), 50);
      expect(usage.limitFor(openRouterRoute), 50);
    });

    test('with no free quota, the user limit is the limit', () {
      const unread = RouteUsage(
        requests: 3,
        modelRequests: <String, int>{'openai/gpt-oss-20b': 3},
      );
      expect(unread.limitFor(groqRoute.copyWith(userLimit: 20)), 20);
      expect(unread.leftFor(groqRoute.copyWith(userLimit: 20)), 17);
    });

    test('with no free quota and no user limit, there is no limit', () {
      const unread = RouteUsage(requests: 3);
      expect(unread.freeQuotaFor(groqRoute), isNull);
      expect(unread.limitFor(groqRoute), isNull);
      expect(unread.leftFor(groqRoute), isNull);
      expect(unread.isUsedUp(groqRoute), isFalse);
    });

    test('a user limit of 0 is used up before any request', () {
      const unused = RouteUsage();
      expect(unused.isUsedUp(groqRoute.copyWith(userLimit: 0)), isTrue);
      expect(unused.isUsedUp(openAiRoute.copyWith(userLimit: 0)), isTrue);
      expect(usage.isUsedUp(openRouterRoute.copyWith(userLimit: 0)), isTrue);
    });

    test('a route is used up once it reaches its limit', () {
      final route = openRouterRoute.copyWith(userLimit: 13);
      expect(usage.usedFor(route), 10);
      expect(usage.isUsedUp(route), isFalse);
      expect(usage.isUsedUp(openRouterRoute.copyWith(userLimit: 10)), isTrue);
    });

    test('a Groq reading for another model is ignored', () {
      final groqUsage = RouteUsage(
        requests: 2,
        modelRequests: const <String, int>{'openai/gpt-oss-20b': 2},
        reading: readingOf(
          'openai/gpt-oss-20b',
          limit: 1000,
          remaining: 900,
          requestsAtCheck: 2,
        ),
      );
      expect(groqUsage.readingFor(groqRoute), isNotNull);
      expect(groqUsage.freeQuotaFor(groqRoute), 1000);
      expect(groqUsage.usedFor(groqRoute), 100);

      final otherModel = groqRoute.copyWith(model: 'llama-3.1-8b-instant');
      expect(groqUsage.readingFor(otherModel), isNull);
      expect(groqUsage.freeQuotaFor(otherModel), isNull);
      expect(groqUsage.limitFor(otherModel), isNull);
      // The other model hasn't been asked today, and its quota is its own.
      expect(groqUsage.usedFor(otherModel), 0);
    });

    test('an OpenRouter reading counts after the model changes', () {
      final otherModel = openRouterRoute.copyWith(
        model: 'meta-llama/llama-3.3-70b-instruct:free',
      );
      expect(usage.readingFor(otherModel), usage.reading);
      expect(usage.freeQuotaFor(otherModel), 50);
      expect(usage.usedFor(otherModel), 10);
    });

    test('used counts the service count and requests since it was read', () {
      final route = openRouterRoute;
      expect(
        RouteUsage(
          requests: 5,
          reading: readingOf(
            'openrouter/free',
            limit: 50,
            remaining: 40,
            requestsAtCheck: 3,
          ),
        ).usedFor(route),
        12,
      );
      // This app's own count wins when it's higher than the service's.
      expect(
        RouteUsage(
          requests: 30,
          reading: readingOf(
            'openrouter/free',
            limit: 50,
            remaining: 45,
            requestsAtCheck: 28,
          ),
        ).usedFor(route),
        30,
      );
      expect(const RouteUsage(requests: 4).usedFor(route), 4);
    });

    test('a Groq count is the service count, even below this app\'s', () {
      // 40 requests on another model, then the new model answered once.
      final switched = groqRoute.copyWith(model: 'qwen/qwen3.8-27b');
      final afterSwitch = RouteUsage(
        requests: 41,
        reading: readingOf(
          'qwen/qwen3.8-27b',
          limit: 1000,
          remaining: 999,
          requestsAtCheck: 41,
        ),
      );
      expect(afterSwitch.usedFor(switched), 1);
      expect(afterSwitch.leftFor(switched), 999);

      // Groq refills over the day, so it can report less than was sent.
      final refilled = RouteUsage(
        requests: 200,
        reading: readingOf(
          groqRoute.model,
          limit: 1000,
          remaining: 999,
          requestsAtCheck: 200,
        ),
      );
      expect(refilled.usedFor(groqRoute), 1);
    });

    test('a Groq limit counts only the requests to its model', () async {
      final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 30, 12));
      for (var i = 0; i < 3; i++) {
        await tracker.record(groqRoute);
      }
      final switched = groqRoute.copyWith(
        model: 'openai/gpt-oss-120b',
        userLimit: 2,
      );

      expect(await tracker.isUsedUpOrBlocked(switched), isFalse);
      expect((await tracker.usageFor(switched)).usedFor(switched), 0);
      await tracker.record(switched);
      await tracker.record(switched);
      expect(await tracker.isUsedUpOrBlocked(switched), isTrue);
      // The route still counts every request.
      expect((await tracker.usageFor(switched)).requests, 5);
      expect((await tracker.usageFor(groqRoute)).usedFor(groqRoute), 3);
    });

    test(
      'requests to another Groq model don\'t count after a reading',
      () async {
        final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 30, 12));
        await tracker.record(
          groqRoute,
          quota: const FreeQuota(limit: 1000, remaining: 990),
        );
        final other = groqRoute.copyWith(model: 'openai/gpt-oss-120b');
        await tracker.record(other);
        await tracker.record(other);

        final usage = await tracker.usageFor(groqRoute);
        expect(usage.reading?.model, groqRoute.model);
        expect(usage.usedFor(groqRoute), 10);
      },
    );

    test('an OpenRouter count is never below this app\'s requests', () {
      final lagging = RouteUsage(
        requests: 5,
        reading: readingOf(
          openRouterRoute.model,
          limit: 50,
          remaining: 48,
          requestsAtCheck: 5,
        ),
      );
      expect(lagging.usedFor(openRouterRoute), 5);
    });

    test('resetFor is midnight when used up, or the end of a 429', () {
      final now = DateTime.utc(2026, 9, 30, 10);
      final midnight = DateTime.utc(2026, 10);
      final minuteLater = now.add(const Duration(minutes: 1));
      final usedUp = RouteUsage(
        requests: 1,
        reading: readingOf(openRouterRoute.model, limit: 50, remaining: 0),
      );

      expect(const RouteUsage().resetFor(openRouterRoute, now), isNull);
      expect(
        RouteUsage(blockedUntil: minuteLater).resetFor(openRouterRoute, now),
        minuteLater,
      );
      expect(usedUp.resetFor(openRouterRoute, now), midnight);
      expect(
        RouteUsage(
          requests: 1,
          blockedUntil: minuteLater,
          reading: usedUp.reading,
        ).resetFor(openRouterRoute, now),
        midnight,
      );
    });

    test('token routes count only this app\'s tokens', () {
      final tokenUsage = RouteUsage(
        requests: 7,
        tokens: 1200,
        reading: readingOf('gpt-5.6-terra', limit: 50, remaining: 0),
      );
      expect(tokenUsage.usedFor(openAiRoute), 1200);
      expect(tokenUsage.freeQuotaFor(openAiRoute), 2500000);
    });

    test('OpenAI free quota is the group allowance', () {
      const usage = RouteUsage();
      final large = openAiRoute.copyWith(model: 'gpt-6-sol');
      expect(usage.freeQuotaFor(openAiRoute), 2500000);
      expect(usage.freeQuotaFor(large), 250000);
      expect(usage.limitFor(openAiRoute), 2500000);
      expect(usage.limitFor(openAiRoute.copyWith(userLimit: 2250000)), 2250000);
    });

    test('usage tier 3 or higher gets four times the OpenAI allowance', () {
      const usage = RouteUsage();
      final small = openAiRoute.copyWith(highUsageTier: true);
      final large = small.copyWith(model: 'gpt-6-sol');
      expect(usage.freeQuotaFor(small), 10000000);
      expect(usage.freeQuotaFor(large), 1000000);
      // A limit that was above the tier 1-2 allowance fits under tier 3.
      expect(usage.limitFor(large.copyWith(userLimit: 900000)), 900000);
      expect(
        usage.limitFor(
          openAiRoute.copyWith(model: 'gpt-6-sol', userLimit: 900000),
        ),
        250000,
      );
    });

    test('an OpenAI model that is not offered has no free quota', () {
      const usage = RouteUsage();
      expect(
        usage.freeQuotaFor(openAiRoute.copyWith(model: 'gpt-4o-mini')),
        isNull,
      );
    });
  });

  group('UsageTracker', () {
    test('adds requests since a report to the service count', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(openRouterRoute);
      await tracker.report(
        openRouterRoute,
        const FreeQuota(limit: 50, remaining: 40),
      );
      expect(
        (await tracker.usageFor(openRouterRoute)).usedFor(openRouterRoute),
        10,
      );

      await tracker.record(openRouterRoute);
      await tracker.record(openRouterRoute);
      final usage = await tracker.usageFor(openRouterRoute);
      expect(usage.requests, 3);
      expect(usage.reading?.requestsAtCheck, 1);
      expect(usage.usedFor(openRouterRoute), 12);
      expect(usage.leftFor(openRouterRoute), 38);
    });

    test('a reply\'s quota already counts that reply', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(groqRoute);
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 990),
      );
      var usage = await tracker.usageFor(groqRoute);
      expect(usage.requests, 2);
      expect(usage.reading?.requestsAtCheck, 2);
      expect(usage.usedFor(groqRoute), 10);

      await tracker.record(groqRoute);
      usage = await tracker.usageFor(groqRoute);
      expect(usage.usedFor(groqRoute), 11);
      expect(usage.leftFor(groqRoute), 989);
    });

    test('a newer reply replaces the reading', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 990),
      );
      await tracker.record(groqRoute);
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 950),
      );
      final usage = await tracker.usageFor(groqRoute);
      expect(usage.reading?.requestsAtCheck, 3);
      expect(usage.usedFor(groqRoute), 50);
    });

    test('token routes count only this app\'s tokens', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(openAiRoute, tokens: 500);
      await tracker.record(openAiRoute, tokens: 700);
      await tracker.record(openAiRoute);
      final usage = await tracker.usageFor(openAiRoute);
      expect(usage.requests, 3);
      expect(usage.usedFor(openAiRoute), 1200);
      expect(usage.leftFor(openAiRoute), 2500000 - 1200);
    });

    test('a user limit of 0 skips the route', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      expect(
        await tracker.isUsedUpOrBlocked(groqRoute.copyWith(userLimit: 0)),
        isTrue,
      );
      expect(await tracker.isUsedUpOrBlocked(groqRoute), isFalse);
    });

    test(
      'a route is used up when the service count reaches the quota',
      () async {
        final now = DateTime.utc(2026, 9, 30, 12);
        final tracker = UsageTracker(now: () => now);
        await tracker.report(
          openRouterRoute,
          const FreeQuota(limit: 50, remaining: 1),
        );
        expect(await tracker.isUsedUpOrBlocked(openRouterRoute), isFalse);
        await tracker.record(openRouterRoute);
        expect(await tracker.isUsedUpOrBlocked(openRouterRoute), isTrue);
      },
    );

    test(
      'reports and reply quotas are kept across tracker instances',
      () async {
        final now = DateTime.utc(2026, 9, 30, 12);
        final tracker = UsageTracker(now: () => now);
        await tracker.report(
          openRouterRoute,
          const FreeQuota(limit: 50, remaining: 40),
        );
        await tracker.record(
          groqRoute,
          tokens: 30,
          quota: const FreeQuota(limit: 1000, remaining: 990),
        );

        final restarted = UsageTracker(now: () => now);
        expect(
          await restarted.usageFor(openRouterRoute),
          RouteUsage(
            reading: QuotaReading(
              model: 'openrouter/free',
              quota: const FreeQuota(limit: 50, remaining: 40),
              checkedAt: now,
              requestsAtCheck: 0,
            ),
          ),
        );
        expect(
          await restarted.usageFor(groqRoute),
          RouteUsage(
            requests: 1,
            modelRequests: const <String, int>{'openai/gpt-oss-20b': 1},
            tokens: 30,
            reading: QuotaReading(
              model: 'openai/gpt-oss-20b',
              quota: const FreeQuota(limit: 1000, remaining: 990),
              checkedAt: now,
              requestsAtCheck: 1,
            ),
          ),
        );
      },
    );

    test('a report keeps the requests, tokens, and block', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(openRouterRoute, tokens: 25);
      await tracker.block(
        openRouterRoute,
        until: now.add(const Duration(minutes: 1)),
      );
      await tracker.report(
        openRouterRoute,
        const FreeQuota(limit: 50, remaining: 45),
      );
      final usage = await tracker.usageFor(openRouterRoute);
      expect(usage.requests, 1);
      expect(usage.tokens, 25);
      expect(usage.blockedUntil, DateTime.utc(2026, 9, 30, 12, 1));
      expect(usage.reading?.quota, const FreeQuota(limit: 50, remaining: 45));
    });

    test('a reading is dropped at the next UTC day', () async {
      var now = DateTime.utc(2026, 9, 30, 23, 59);
      final tracker = UsageTracker(now: () => now);
      await tracker.report(
        openRouterRoute,
        const FreeQuota(limit: 50, remaining: 40),
      );
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 990),
      );
      expect((await tracker.usageFor(openRouterRoute)).reading, isNotNull);

      now = DateTime.utc(2026, 10, 1);
      final openRouterUsage = await tracker.usageFor(openRouterRoute);
      final groqUsage = await tracker.usageFor(groqRoute);
      expect(openRouterUsage, const RouteUsage());
      expect(groqUsage, const RouteUsage());
      expect(openRouterUsage.freeQuotaFor(openRouterRoute), isNull);
      expect(groqUsage.freeQuotaFor(groqRoute), isNull);
    });

    test('keeps each route separate', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(openRouterRoute);
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 999),
      );
      expect((await tracker.usageFor(openRouterRoute)).reading, isNull);
      expect((await tracker.usageFor(openRouterRoute)).requests, 1);
      expect((await tracker.usageFor(groqRoute)).requests, 1);
      expect(await tracker.usageFor(openAiRoute), const RouteUsage());
    });
  });

  group('knownFreeQuota', () {
    test('is today\'s reading', () async {
      final now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 990),
      );
      await tracker.report(
        openRouterRoute,
        const FreeQuota(limit: 50, remaining: 40),
      );
      expect(await tracker.knownFreeQuota(groqRoute), 1000);
      expect(await tracker.knownFreeQuota(openRouterRoute), 50);
    });

    test('is the allowance for OpenAI', () async {
      final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 30, 12));
      expect(await tracker.knownFreeQuota(openAiRoute), 2500000);
      expect(
        await tracker.knownFreeQuota(openAiRoute.copyWith(model: 'gpt-6-sol')),
        250000,
      );
      expect(
        await tracker.knownFreeQuota(openAiRoute.copyWith(highUsageTier: true)),
        10000000,
      );
      expect(
        await tracker.knownFreeQuota(
          openAiRoute.copyWith(model: 'gpt-6-sol', highUsageTier: true),
        ),
        1000000,
      );
    });

    test('is null when the provider never reported one', () async {
      final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 30, 12));
      expect(await tracker.knownFreeQuota(groqRoute), isNull);
      expect(await tracker.knownFreeQuota(openRouterRoute), isNull);
      await tracker.record(groqRoute);
      await tracker.record(openRouterRoute);
      expect(await tracker.knownFreeQuota(groqRoute), isNull);
      expect(await tracker.knownFreeQuota(openRouterRoute), isNull);
    });

    test(
      'falls back to the last limit Groq reported for the same model',
      () async {
        var now = DateTime.utc(2026, 9, 30, 12);
        final tracker = UsageTracker(now: () => now);
        await tracker.record(
          groqRoute,
          quota: const FreeQuota(limit: 1000, remaining: 990),
        );

        now = DateTime.utc(2026, 10, 1, 1);
        expect((await tracker.usageFor(groqRoute)).reading, isNull);
        expect(await tracker.knownFreeQuota(groqRoute), 1000);
        expect(
          await UsageTracker(now: () => now).knownFreeQuota(groqRoute),
          1000,
        );
        expect(
          await tracker.knownFreeQuota(
            groqRoute.copyWith(model: 'llama-3.1-8b-instant'),
          ),
          isNull,
        );
      },
    );

    test('keeps each Groq model\'s last limit', () async {
      var now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      final llama = groqRoute.copyWith(model: 'llama-3.1-8b-instant');
      await tracker.record(
        groqRoute,
        quota: const FreeQuota(limit: 1000, remaining: 990),
      );
      await tracker.record(
        llama,
        quota: const FreeQuota(limit: 14400, remaining: 14399),
      );

      now = DateTime.utc(2026, 10, 1, 1);
      expect(await tracker.knownFreeQuota(groqRoute), 1000);
      expect(await tracker.knownFreeQuota(llama), 14400);
    });

    test(
      'falls back to the last OpenRouter limit for any of its models',
      () async {
        var now = DateTime.utc(2026, 9, 30, 12);
        final tracker = UsageTracker(now: () => now);
        await tracker.report(
          openRouterRoute,
          const FreeQuota(limit: 50, remaining: 40),
        );

        now = DateTime.utc(2026, 10, 1, 1);
        expect(await tracker.knownFreeQuota(openRouterRoute), 50);
        expect(
          await tracker.knownFreeQuota(
            openRouterRoute.copyWith(
              model: 'meta-llama/llama-3.3-70b-instruct:free',
            ),
          ),
          50,
        );
      },
    );

    test('prefers today\'s reading over an earlier day\'s', () async {
      var now = DateTime.utc(2026, 9, 30, 12);
      final tracker = UsageTracker(now: () => now);
      await tracker.report(
        openRouterRoute,
        const FreeQuota(limit: 50, remaining: 40),
      );

      now = DateTime.utc(2026, 10, 1, 1);
      await tracker.report(
        openRouterRoute,
        const FreeQuota(limit: 1000, remaining: 1000),
      );
      expect(await tracker.knownFreeQuota(openRouterRoute), 1000);

      now = DateTime.utc(2026, 10, 2, 1);
      expect(await tracker.knownFreeQuota(openRouterRoute), 1000);
    });
  });
}
