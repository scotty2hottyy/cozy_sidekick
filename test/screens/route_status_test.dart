import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
import 'package:cozy_sidekick/models/quota_route.dart';
import 'package:cozy_sidekick/screens/ai_settings_screen.dart';
import 'package:cozy_sidekick/services/usage_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatAmount', () {
    test('shortens tokens to K and M, keeping whole hundreds', () {
      for (final (amount, shown) in <(int, String)>[
        (999, '999'),
        (12345, '12.3K'),
        (100000, '100K'),
        (225000, '225K'),
        (250000, '250K'),
        (900000, '900K'),
        (999999, '1M'),
        (1000000, '1M'),
        (1234567, '1.23M'),
        (2250000, '2.25M'),
        (2500000, '2.5M'),
        (9000000, '9M'),
        (10000000, '10M'),
      ]) {
        expect(
          formatAmount(amount, QuotaUnit.tokens, withUnit: false),
          shown,
          reason: '$amount',
        );
      }
    });

    test('groups requests with commas and names the unit', () {
      expect(formatAmount(1000, QuotaUnit.requests), '1,000 requests');
      expect(formatAmount(1234567, QuotaUnit.requests), '1,234,567 requests');
      expect(formatAmount(1, QuotaUnit.requests), '1 request');
      expect(formatAmount(0, QuotaUnit.requests), '0 requests');
      expect(
        formatAmount(50, QuotaUnit.requests, free: true),
        '50 free requests',
      );
      expect(formatAmount(250000, QuotaUnit.tokens), '250K tokens');
    });
  });

  group('routeStatus', () {
    final now = DateTime.utc(2026, 9, 30, 15);
    const openRouter = QuotaRoute(
      id: 'openrouter-free',
      provider: AiProviderType.openRouter,
      model: 'openrouter/free',
      unit: QuotaUnit.requests,
    );
    const openAi = QuotaRoute(
      id: 'openai-mini',
      provider: AiProviderType.openAi,
      model: 'gpt-5.6-terra',
      unit: QuotaUnit.tokens,
      userLimit: 2250000,
    );
    RouteUsage reported(int limit, int remaining, {int requests = 0}) =>
        RouteUsage(
          requests: requests,
          reading: QuotaReading(
            model: openRouter.model,
            quota: FreeQuota(limit: limit, remaining: remaining),
            checkedAt: now,
            requestsAtCheck: requests,
          ),
        );

    test('shows the free quota, or the user limit below it', () {
      expect(
        routeStatus(openRouter, reported(50, 38), now),
        '38 of 50 free requests left today',
      );
      expect(
        routeStatus(openRouter.copyWith(userLimit: 20), reported(50, 38), now),
        '8 of your 20 requests left today',
      );
      expect(
        routeStatus(openAi, const RouteUsage(tokens: 250000), now),
        '2M of your 2.25M tokens left today',
      );
      expect(
        routeStatus(
          openAi.copyWith(clearUserLimit: true),
          const RouteUsage(),
          now,
        ),
        '2.5M of 2.5M free tokens left today',
      );
    });

    test('says when the free quota is unknown', () {
      expect(
        routeStatus(openRouter, const RouteUsage(requests: 3), now),
        '3 requests today · free quota unknown',
      );
    });

    test('used up waits for midnight, even when a 429 is shorter', () {
      final minuteLater = now.add(const Duration(minutes: 1));
      expect(
        routeStatus(openRouter, reported(50, 0), now),
        'Used up · resets 12:00 AM UTC',
      );
      final both = reported(50, 0);
      expect(
        routeStatus(
          openRouter,
          RouteUsage(blockedUntil: minuteLater, reading: both.reading),
          now,
        ),
        'Used up · resets 12:00 AM UTC',
      );
    });

    test('a 429 that ends before midnight is only busy', () {
      expect(
        routeStatus(
          openRouter,
          RouteUsage(blockedUntil: now.add(const Duration(seconds: 1))),
          now,
        ),
        'Busy · try again in a moment',
      );
      expect(
        routeStatus(
          openRouter,
          RouteUsage(blockedUntil: now.add(const Duration(minutes: 5))),
          now,
        ),
        'Busy · try again after 3:05 PM UTC',
      );
      // OpenRouter's daily limit sends a 429 that lasts until midnight.
      expect(
        routeStatus(
          openRouter,
          RouteUsage(blockedUntil: DateTime.utc(2026, 10)),
          now,
        ),
        'Used up · resets 12:00 AM UTC',
      );
    });

    test('a limit of 0 is skipped', () {
      expect(
        routeStatus(openRouter.copyWith(userLimit: 0), reported(50, 38), now),
        'Skipped · daily limit is 0',
      );
    });
  });
}
