import 'package:flutter_test/flutter_test.dart';

import 'package:cozy_sidekick/models/openai_free_tier.dart';

void main() {
  group('OpenAiFreeTier', () {
    test('offers gpt-6-sol then gpt-5.6-terra, and no luna models', () {
      expect(OpenAiFreeTier.allModels, ['gpt-6-sol', 'gpt-5.6-terra']);
      expect(OpenAiFreeTier.large.models, ['gpt-6-sol']);
      expect(OpenAiFreeTier.small.models, ['gpt-5.6-terra']);
    });

    test('of() finds the group a model is in', () {
      expect(OpenAiFreeTier.of('gpt-6-sol'), OpenAiFreeTier.large);
      expect(OpenAiFreeTier.of('gpt-5.6-terra'), OpenAiFreeTier.small);
    });

    test('of() is null for a model that isn\'t offered', () {
      expect(OpenAiFreeTier.of('gpt-6-luna'), isNull);
      expect(OpenAiFreeTier.of('gpt-5.6-luna'), isNull);
      expect(OpenAiFreeTier.of('gpt-4o-mini'), isNull);
      expect(OpenAiFreeTier.of(''), isNull);
    });

    test('gives 250K and 2.5M tokens a day below usage tier 3', () {
      expect(OpenAiFreeTier.large.tokensPerDay(highUsageTier: false), 250000);
      expect(OpenAiFreeTier.small.tokensPerDay(highUsageTier: false), 2500000);
    });

    test('gives four times as much at usage tier 3 or higher', () {
      expect(OpenAiFreeTier.large.tokensPerDay(highUsageTier: true), 1000000);
      expect(OpenAiFreeTier.small.tokensPerDay(highUsageTier: true), 10000000);
    });

    test('suggests 90% of the day\'s tokens', () {
      expect(OpenAiFreeTier.large.suggestedLimit(highUsageTier: false), 225000);
      expect(OpenAiFreeTier.large.suggestedLimit(highUsageTier: true), 900000);
      expect(
        OpenAiFreeTier.small.suggestedLimit(highUsageTier: false),
        2250000,
      );
      expect(OpenAiFreeTier.small.suggestedLimit(highUsageTier: true), 9000000);
    });

    test('has a name for each group', () {
      expect(OpenAiFreeTier.large.displayName, 'Large models');
      expect(OpenAiFreeTier.small.displayName, 'Small models');
    });
  });
}
