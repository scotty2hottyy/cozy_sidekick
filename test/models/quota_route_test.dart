import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/quota_route.dart';

void main() {
  /// An OpenAI route saved in the current format, for tests that change one
  /// field at a time.
  Map<String, Object?> openAiJson({
    String model = 'gpt-5.6-terra',
    int? userLimit,
    bool highUsageTier = false,
  }) => {
    'id': 'openai-mini',
    'provider': 'openAi',
    'model': model,
    'unit': 'tokens',
    'userLimit': userLimit,
    'enabled': true,
    'highUsageTier': highUsageTier,
  };

  group('QuotaRoute.fromJson with routes saved before userLimit', () {
    test('drops an OpenRouter or Groq dailyLimit and uses the free quota', () {
      final openRouter = QuotaRoute.fromJson({
        'id': 'openrouter-free',
        'provider': 'openRouter',
        'model': 'openrouter/free',
        'unit': 'requests',
        'dailyLimit': 50,
        'enabled': true,
      });
      final groq = QuotaRoute.fromJson({
        'id': 'groq-free',
        'provider': 'groq',
        'model': 'openai/gpt-oss-20b',
        'unit': 'requests',
        'dailyLimit': 1000,
        'enabled': true,
      });

      expect(openRouter.userLimit, isNull);
      expect(openRouter.model, 'openrouter/free');
      expect(groq.userLimit, isNull);
      expect(groq.model, 'openai/gpt-oss-20b');
    });

    test('moves OpenAI gpt-4o-mini to gpt-5.6-terra and keeps its limit', () {
      final route = QuotaRoute.fromJson({
        'id': 'openai-mini',
        'provider': 'openAi',
        'model': 'gpt-4o-mini',
        'unit': 'tokens',
        'dailyLimit': 2250000,
        'enabled': false,
      });

      expect(route.model, 'gpt-5.6-terra');
      expect(route.userLimit, 2250000);
      expect(route.enabled, isFalse);
      expect(route.highUsageTier, isFalse);
    });
  });

  group('QuotaRoute.fromJson for OpenAI', () {
    test('moves gpt-6-luna, which is no longer offered, to gpt-5.6-terra', () {
      final route = QuotaRoute.fromJson(
        openAiJson(model: 'gpt-6-luna', userLimit: 1000000),
      );

      expect(route.model, 'gpt-5.6-terra');
      expect(route.userLimit, 1000000);
    });

    test('keeps the models that are offered', () {
      expect(
        QuotaRoute.fromJson(openAiJson(model: 'gpt-6-sol')).model,
        'gpt-6-sol',
      );
      expect(
        QuotaRoute.fromJson(openAiJson(model: 'gpt-5.6-terra')).model,
        'gpt-5.6-terra',
      );
    });

    test('keeps a limit under the allowance', () {
      expect(
        QuotaRoute.fromJson(openAiJson(model: 'gpt-6-sol', userLimit: 100000))
            .userLimit,
        100000,
      );
      expect(
        QuotaRoute.fromJson(openAiJson(userLimit: 2499999)).userLimit,
        2499999,
      );
    });

    test('resets a limit at or over the allowance to 90% of it', () {
      expect(
        QuotaRoute.fromJson(openAiJson(model: 'gpt-6-sol', userLimit: 250000))
            .userLimit,
        225000,
      );
      expect(
        QuotaRoute.fromJson(openAiJson(userLimit: 2500000)).userLimit,
        2250000,
      );
      expect(
        QuotaRoute.fromJson(openAiJson(userLimit: 9000000)).userLimit,
        2250000,
      );
    });

    test(
      'measures the limit against usage tier 3 when highUsageTier is on',
      () {
        final kept = QuotaRoute.fromJson(
          openAiJson(userLimit: 9000000, highUsageTier: true),
        );
        final reset = QuotaRoute.fromJson(
          openAiJson(userLimit: 10000000, highUsageTier: true),
        );
        final largeReset = QuotaRoute.fromJson(
          openAiJson(
            model: 'gpt-6-sol',
            userLimit: 1000000,
            highUsageTier: true,
          ),
        );

        expect(kept.userLimit, 9000000);
        expect(kept.highUsageTier, isTrue);
        expect(reset.userLimit, 9000000);
        expect(largeReset.userLimit, 900000);
      },
    );

    test('resets a moved model\'s limit against its new group', () {
      final route = QuotaRoute.fromJson({
        'id': 'openai-mini',
        'provider': 'openAi',
        'model': 'gpt-4o-mini',
        'unit': 'tokens',
        'dailyLimit': 5000000,
      });

      expect(route.model, 'gpt-5.6-terra');
      expect(route.userLimit, 2250000);
    });
  });

  group('QuotaRoute.fromJson with userLimit', () {
    test('keeps a null userLimit as the whole free quota', () {
      final openAi = QuotaRoute.fromJson(openAiJson());
      final groq = QuotaRoute.fromJson({
        'id': 'groq-free',
        'provider': 'groq',
        'model': 'openai/gpt-oss-20b',
        'unit': 'requests',
        'userLimit': null,
      });

      expect(openAi.userLimit, isNull);
      expect(groq.userLimit, isNull);
    });

    test('ignores an old dailyLimit when userLimit is saved', () {
      final json = openAiJson()..['dailyLimit'] = 1000;

      expect(QuotaRoute.fromJson(json).userLimit, isNull);
    });

    test('keeps a Groq userLimit', () {
      final route = QuotaRoute.fromJson({
        'id': 'groq-free',
        'provider': 'groq',
        'model': 'openai/gpt-oss-20b',
        'unit': 'requests',
        'userLimit': 20,
      });

      expect(route.userLimit, 20);
    });

    test('is enabled and not on usage tier 3 when those are missing', () {
      final route = QuotaRoute.fromJson({
        'id': 'openrouter-free',
        'provider': 'openRouter',
        'model': 'openrouter/free',
        'unit': 'requests',
      });

      expect(route.enabled, isTrue);
      expect(route.highUsageTier, isFalse);
    });
  });

  group('QuotaRoute toJson and fromJson', () {
    test('survive a round trip through a real JSON string', () {
      const routes = [
        QuotaRoute(
          id: 'openai-mini',
          provider: AiProviderType.openAi,
          model: 'gpt-6-sol',
          unit: QuotaUnit.tokens,
          userLimit: 800000,
          highUsageTier: true,
        ),
        QuotaRoute(
          id: 'groq-free',
          provider: AiProviderType.groq,
          model: 'llama-3.1-8b-instant',
          unit: QuotaUnit.requests,
          userLimit: 20,
          enabled: false,
        ),
        QuotaRoute(
          id: 'openrouter-free',
          provider: AiProviderType.openRouter,
          model: 'openrouter/free',
          unit: QuotaUnit.requests,
        ),
      ];

      for (final route in routes) {
        final json =
            jsonDecode(jsonEncode(route.toJson())) as Map<String, Object?>;
        final restored = QuotaRoute.fromJson(json);

        expect(restored, route);
        expect(restored.highUsageTier, route.highUsageTier);
        expect(restored.enabled, route.enabled);
        expect(restored.userLimit, route.userLimit);
      }
    });

    test('toJson saves userLimit and highUsageTier, not dailyLimit', () {
      final json = QuotaRoute.defaults.last.toJson();

      expect(json, containsPair('userLimit', 2250000));
      expect(json, containsPair('highUsageTier', false));
      expect(json, containsPair('enabled', false));
      expect(json.containsKey('dailyLimit'), isFalse);
    });

    test('throws a FormatException for an unknown provider', () {
      expect(
        () => QuotaRoute.fromJson({
          'id': 'x',
          'provider': 'notAProvider',
          'model': 'm',
          'unit': 'requests',
        }),
        throwsFormatException,
      );
    });

    test('throws a FormatException for a missing unit', () {
      expect(
        () =>
            QuotaRoute.fromJson({'id': 'x', 'provider': 'groq', 'model': 'm'}),
        throwsFormatException,
      );
    });

    test(
      'throws a FormatException for a unit that isn\'t requests or tokens',
      () {
        expect(
          () => QuotaRoute.fromJson({
            'id': 'x',
            'provider': 'groq',
            'model': 'm',
            'unit': 'dollars',
          }),
          throwsFormatException,
        );
      },
    );
  });

  group('QuotaRoute.defaults', () {
    test('OpenRouter and Groq use the whole free quota', () {
      final openRouter = QuotaRoute.defaults.singleWhere(
        (route) => route.provider == AiProviderType.openRouter,
      );
      final groq = QuotaRoute.defaults.singleWhere(
        (route) => route.provider == AiProviderType.groq,
      );

      expect(openRouter.model, 'openrouter/free');
      expect(openRouter.unit, QuotaUnit.requests);
      expect(openRouter.userLimit, isNull);
      expect(openRouter.enabled, isTrue);
      expect(groq.unit, QuotaUnit.requests);
      expect(groq.userLimit, isNull);
      expect(groq.enabled, isTrue);
    });

    test('OpenAI is gpt-5.6-terra at 2,250,000 tokens and off', () {
      final openAi = QuotaRoute.defaults.singleWhere(
        (route) => route.provider == AiProviderType.openAi,
      );

      expect(openAi.model, 'gpt-5.6-terra');
      expect(openAi.unit, QuotaUnit.tokens);
      expect(openAi.userLimit, 2250000);
      expect(openAi.enabled, isFalse);
      expect(openAi.highUsageTier, isFalse);
    });

    test('come back unchanged from toJson and fromJson', () {
      for (final route in QuotaRoute.defaults) {
        expect(QuotaRoute.fromJson(route.toJson()), route);
      }
    });
  });

  group('QuotaRoute getters', () {
    QuotaRoute routeFor(AiProviderType provider) => QuotaRoute(
      id: provider.name,
      provider: provider,
      model: 'm',
      unit: QuotaUnit.requests,
    );

    test('only Groq has a free quota per model', () {
      expect(routeFor(AiProviderType.groq).quotaIsPerModel, isTrue);
      expect(routeFor(AiProviderType.openRouter).quotaIsPerModel, isFalse);
      expect(routeFor(AiProviderType.openAi).quotaIsPerModel, isFalse);
    });

    test('OpenRouter and Groq report their free quota, OpenAI does not', () {
      expect(routeFor(AiProviderType.openRouter).reportsFreeQuota, isTrue);
      expect(routeFor(AiProviderType.groq).reportsFreeQuota, isTrue);
      expect(routeFor(AiProviderType.openAi).reportsFreeQuota, isFalse);
    });

    test('copyWith can clear the limit to use the whole free quota', () {
      const route = QuotaRoute(
        id: 'groq-free',
        provider: AiProviderType.groq,
        model: 'openai/gpt-oss-20b',
        unit: QuotaUnit.requests,
        userLimit: 20,
      );

      expect(route.copyWith(clearUserLimit: true).userLimit, isNull);
      expect(route.copyWith(userLimit: 5).userLimit, 5);
      expect(route.copyWith(model: 'other').userLimit, 20);
    });
  });
}
