import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/quota_route.dart';
import 'package:cozy_sidekick/services/usage_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        dailyLimit: 2,
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
      model: 'gpt-4o-mini',
      unit: QuotaUnit.tokens,
      dailyLimit: 100,
    );
    final tracker = UsageTracker(now: () => now);
    await tracker.record(route, tokens: 80);
    expect((await tracker.usageFor(route)).tokens, 80);
    now = DateTime.utc(2026, 9, 30);
    expect(await tracker.usageFor(route), const RouteUsage());
  });
}
