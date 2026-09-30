import 'package:flutter_test/flutter_test.dart';

import 'package:cozy_sidekick/models/free_quota.dart';

void main() {
  group('FreeQuota.fromGroqHeaders', () {
    test('reads the daily request limit and what is left', () {
      final quota = FreeQuota.fromGroqHeaders({
        'x-ratelimit-limit-requests': '1000',
        'x-ratelimit-remaining-requests': '962',
        // Token headers count per minute, so they're ignored.
        'x-ratelimit-limit-tokens': '6000',
        'x-ratelimit-remaining-tokens': '5800',
      });

      expect(quota, const FreeQuota(limit: 1000, remaining: 962));
      expect(quota!.used, 38);
    });

    test('is null without the limit header', () {
      expect(
        FreeQuota.fromGroqHeaders({'x-ratelimit-remaining-requests': '962'}),
        isNull,
      );
    });

    test('is null without the remaining header', () {
      expect(
        FreeQuota.fromGroqHeaders({'x-ratelimit-limit-requests': '1000'}),
        isNull,
      );
    });

    test('is null without any headers', () {
      expect(FreeQuota.fromGroqHeaders({}), isNull);
    });

    test('is null when a header is not a whole number', () {
      expect(
        FreeQuota.fromGroqHeaders({
          'x-ratelimit-limit-requests': 'lots',
          'x-ratelimit-remaining-requests': '962',
        }),
        isNull,
      );
      expect(
        FreeQuota.fromGroqHeaders({
          'x-ratelimit-limit-requests': '1000',
          'x-ratelimit-remaining-requests': '9.5',
        }),
        isNull,
      );
    });

    test('is null when a header is negative', () {
      expect(
        FreeQuota.fromGroqHeaders({
          'x-ratelimit-limit-requests': '-1',
          'x-ratelimit-remaining-requests': '0',
        }),
        isNull,
      );
      expect(
        FreeQuota.fromGroqHeaders({
          'x-ratelimit-limit-requests': '1000',
          'x-ratelimit-remaining-requests': '-3',
        }),
        isNull,
      );
    });

    test('never leaves more than the limit', () {
      final quota = FreeQuota.fromGroqHeaders({
        'x-ratelimit-limit-requests': '1000',
        'x-ratelimit-remaining-requests': '1200',
      });

      expect(quota, const FreeQuota(limit: 1000, remaining: 1000));
      expect(quota!.used, 0);
    });

    test('reads a quota that is used up', () {
      final quota = FreeQuota.fromGroqHeaders({
        'x-ratelimit-limit-requests': '1000',
        'x-ratelimit-remaining-requests': '0',
      });

      expect(quota!.remaining, 0);
      expect(quota.used, 1000);
    });
  });

  group('FreeQuota.used', () {
    test('is the limit minus what is left', () {
      expect(const FreeQuota(limit: 50, remaining: 12).used, 38);
      expect(const FreeQuota(limit: 50, remaining: 50).used, 0);
    });

    test('is never below zero', () {
      expect(const FreeQuota(limit: 50, remaining: 60).used, 0);
    });
  });

  test('two quotas with the same numbers are equal', () {
    expect(
      const FreeQuota(limit: 50, remaining: 12),
      const FreeQuota(limit: 50, remaining: 12),
    );
    expect(
      const FreeQuota(limit: 50, remaining: 12).hashCode,
      const FreeQuota(limit: 50, remaining: 12).hashCode,
    );
    expect(
      const FreeQuota(limit: 50, remaining: 12),
      isNot(const FreeQuota(limit: 50, remaining: 11)),
    );
  });
}
