import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/auto_router.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
import 'package:cozy_sidekick/models/quota_route.dart';
import 'package:cozy_sidekick/services/usage_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const first = QuotaRoute(
    id: 'first',
    provider: AiProviderType.openRouter,
    model: 'first-model',
    unit: QuotaUnit.requests,
    userLimit: 2,
  );
  const second = QuotaRoute(
    id: 'second',
    provider: AiProviderType.groq,
    model: 'second-model',
    unit: QuotaUnit.requests,
    userLimit: 2,
  );

  test('the second default free route uses Groq and its whole quota', () {
    expect(
      QuotaRoute.defaults[1],
      const QuotaRoute(
        id: 'groq-free',
        provider: AiProviderType.groq,
        model: 'openai/gpt-oss-20b',
        unit: QuotaUnit.requests,
      ),
    );
  });

  test(
    'tries enabled routes in order and records the successful route',
    () async {
      final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 29));
      final providers = <AiProviderType, _FakeProvider>{
        AiProviderType.openRouter: _FakeProvider(const AiReply(text: 'first')),
        AiProviderType.groq: _FakeProvider(
          const AiReply(text: 'second', totalTokens: 10),
        ),
      };
      final router = _router([first, second], providers, tracker);

      final reply = await router.sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      );

      expect(reply, const AiReply(text: 'first'));
      expect(providers[AiProviderType.openRouter]!.lastModel, 'first-model');
      expect(providers[AiProviderType.openRouter]!.calls, 1);
      expect(providers[AiProviderType.groq]!.calls, 0);
      expect((await tracker.usageFor(first)).requests, 1);
      expect((await tracker.usageFor(first)).tokens, 0);
    },
  );

  test('skips an exhausted request or token route', () async {
    final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 29));
    await tracker.record(first);
    await tracker.record(first);
    const tokenRoute = QuotaRoute(
      id: 'token-route',
      provider: AiProviderType.openRouter,
      model: 'token-model',
      unit: QuotaUnit.tokens,
      userLimit: 5,
    );
    await tracker.record(tokenRoute, tokens: 5);
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(const AiReply(text: 'ok')),
      AiProviderType.groq: _FakeProvider(const AiReply(text: 'fallback')),
    };
    final router = _router([first, second], providers, tracker);

    final reply = await router.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Hi')],
    );
    expect(reply.text, 'fallback');
    expect(providers[AiProviderType.openRouter]!.calls, 0);
    expect(providers[AiProviderType.groq]!.calls, 1);
    expect(await tracker.isUsedUpOrBlocked(tokenRoute), isTrue);
  });

  test('429 blocks the route and falls back', () async {
    final now = DateTime.utc(2026, 9, 29, 12);
    final tracker = UsageTracker(now: () => now);
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(
        const AiReply(text: ''),
        error: RateLimitException(retryAt: now.add(const Duration(minutes: 4))),
      ),
      AiProviderType.groq: _FakeProvider(const AiReply(text: 'fallback')),
    };
    final router = _router([first, second], providers, tracker, now: () => now);

    expect(
      await router.sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      ),
      const AiReply(text: 'fallback'),
    );
    expect(
      (await tracker.usageFor(first)).blockedUntil,
      now.add(const Duration(minutes: 4)),
    );
    expect(providers[AiProviderType.groq]!.calls, 1);
  });

  test('a 429 without a retry time waits one second', () async {
    var now = DateTime.utc(2026, 9, 30, 16, 26);
    final tracker = UsageTracker(now: () => now);
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(
        const AiReply(text: 'from OpenRouter'),
        error: const RateLimitException(),
      ),
      AiProviderType.groq: _FakeProvider(const AiReply(text: 'fallback')),
    };
    final router = _router([first, second], providers, tracker, now: () => now);
    Future<String> send() async => (await router.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Hi')],
    )).text;

    expect(await send(), 'fallback');
    expect(
      (await tracker.usageFor(first)).blockedUntil,
      now.add(const Duration(seconds: 1)),
    );

    now = now.add(const Duration(seconds: 1));
    providers[AiProviderType.openRouter] = _FakeProvider(
      const AiReply(text: 'from OpenRouter'),
    );
    expect(await send(), 'from OpenRouter');
  });

  test('when every route is busy, the chat says to try again soon', () async {
    final now = DateTime.utc(2026, 9, 30, 16, 26);
    final tracker = UsageTracker(now: () => now);
    final retryAt = now.add(const Duration(seconds: 30));
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(
        const AiReply(text: ''),
        error: RateLimitException(retryAt: retryAt),
      ),
      AiProviderType.groq: _FakeProvider(
        const AiReply(text: ''),
        error: const RateLimitException(),
      ),
    };

    await expectLater(
      _router([first, second], providers, tracker, now: () => now).sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      ),
      throwsA(
        isA<RateLimitException>().having(
          (error) => error.retryAt,
          'retryAt',
          now.add(const Duration(seconds: 1)),
        ),
      ),
    );
  });

  test('network errors stop routing', () async {
    final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 29));
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(
        const AiReply(text: ''),
        error: const NetworkException(),
      ),
      AiProviderType.groq: _FakeProvider(const AiReply(text: 'must not run')),
    };

    await expectLater(
      _router([first, second], providers, tracker).sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      ),
      throwsA(isA<NetworkException>()),
    );
    expect(providers[AiProviderType.groq]!.calls, 0);
  });

  for (final error in <AiProviderException>[
    const OutOfCreditException(),
    const RequestTooLargeException(),
  ]) {
    test('after ${error.runtimeType}, the next route answers and the route is '
        'not blocked', () async {
      final now = DateTime.utc(2026, 9, 30, 16, 26);
      final tracker = UsageTracker(now: () => now);
      final providers = <AiProviderType, _FakeProvider>{
        AiProviderType.openRouter: _FakeProvider(
          const AiReply(text: ''),
          error: error,
        ),
        AiProviderType.groq: _FakeProvider(const AiReply(text: 'fallback')),
      };

      expect(
        await _router(
          [first, second],
          providers,
          tracker,
          now: () => now,
        ).sendChat(
          systemPrompt: 'system',
          messages: <ChatMessage>[ChatMessage.user('Hi')],
        ),
        const AiReply(text: 'fallback'),
      );
      expect(providers[AiProviderType.groq]!.calls, 1);
      expect((await tracker.usageFor(first)).blockedUntil, isNull);
      expect(await tracker.isUsedUpOrBlocked(first), isFalse);
      expect((await tracker.usageFor(first)).requests, 0);
    });
  }

  test(
    'when every route fails that way, the chat gets the last error',
    () async {
      final now = DateTime.utc(2026, 9, 30, 16, 26);
      final tracker = UsageTracker(now: () => now);
      const tooLarge = RequestTooLargeException();
      final providers = <AiProviderType, _FakeProvider>{
        AiProviderType.openRouter: _FakeProvider(
          const AiReply(text: ''),
          error: const OutOfCreditException(),
        ),
        AiProviderType.groq: _FakeProvider(
          const AiReply(text: ''),
          error: tooLarge,
        ),
      };

      await expectLater(
        _router([first, second], providers, tracker, now: () => now).sendChat(
          systemPrompt: 'system',
          messages: <ChatMessage>[ChatMessage.user('Hi')],
        ),
        throwsA(same(tooLarge)),
      );
      expect(providers[AiProviderType.openRouter]!.calls, 1);
      expect(providers[AiProviderType.groq]!.calls, 1);
    },
  );

  test('all exhausted routes produce a reset time', () async {
    final now = DateTime.utc(2026, 9, 29, 23);
    final tracker = UsageTracker(now: () => now);
    for (final route in [first, second]) {
      await tracker.record(route);
      await tracker.record(route);
    }
    final router = _router(
      [first, second],
      <AiProviderType, _FakeProvider>{},
      tracker,
      now: () => now,
    );

    await expectLater(
      router.sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      ),
      throwsA(
        isA<QuotaExhaustedException>().having(
          (error) => error.resetAt,
          'resetAt',
          DateTime.utc(2026, 9, 30),
        ),
      ),
    );
  });

  group('free quota', () {
    final now = DateTime.utc(2026, 9, 30, 15);
    // Routes that use the whole free quota the provider reports.
    const openRouter = QuotaRoute(
      id: 'openrouter-free',
      provider: AiProviderType.openRouter,
      model: 'openrouter/free',
      unit: QuotaUnit.requests,
    );
    const groq = QuotaRoute(
      id: 'groq-free',
      provider: AiProviderType.groq,
      model: 'openai/gpt-oss-20b',
      unit: QuotaUnit.requests,
    );

    late UsageTracker tracker;
    late Map<AiProviderType, _FakeProvider> providers;

    setUp(() {
      tracker = UsageTracker(now: () => now);
      providers = <AiProviderType, _FakeProvider>{
        AiProviderType.openRouter: _FakeProvider(
          const AiReply(text: 'from OpenRouter'),
        ),
        AiProviderType.groq: _FakeProvider(const AiReply(text: 'from Groq')),
      };
    });

    Future<String> send(List<QuotaRoute> routes) async =>
        (await _router(routes, providers, tracker, now: () => now).sendChat(
          systemPrompt: 'system',
          messages: <ChatMessage>[ChatMessage.user('Hi')],
        )).text;

    test('skips a route whose reported quota is used up', () async {
      await tracker.report(
        openRouter,
        const FreeQuota(limit: 50, remaining: 1),
      );
      expect(await send([openRouter, groq]), 'from OpenRouter');

      await tracker.report(
        openRouter,
        const FreeQuota(limit: 50, remaining: 0),
      );
      expect(await send([openRouter, groq]), 'from Groq');
      expect(providers[AiProviderType.openRouter]!.calls, 1);
    });

    test('a limit below the reported quota stops the route there', () async {
      final limited = openRouter.copyWith(userLimit: 2);
      await tracker.report(limited, const FreeQuota(limit: 50, remaining: 50));

      expect(await send([limited, groq]), 'from OpenRouter');
      expect(await send([limited, groq]), 'from OpenRouter');
      expect(await send([limited, groq]), 'from Groq');
      expect(providers[AiProviderType.openRouter]!.calls, 2);
      expect((await tracker.usageFor(limited)).leftFor(limited), 0);
    });

    test('requests from other apps on the key count too', () async {
      final limited = openRouter.copyWith(userLimit: 10);
      // Another app has used 9 of the day's free requests.
      await tracker.report(limited, const FreeQuota(limit: 50, remaining: 41));

      expect(await send([limited, groq]), 'from OpenRouter');
      expect(await send([limited, groq]), 'from Groq');
    });

    test('saves the quota from a Groq reply', () async {
      const quota = FreeQuota(limit: 1000, remaining: 990);
      providers[AiProviderType.groq] = _FakeProvider(
        const AiReply(text: 'from Groq', freeQuota: quota),
      );

      expect(await send([groq]), 'from Groq');

      final usage = await tracker.usageFor(groq);
      expect(usage.requests, 1);
      expect(usage.reading?.quota, quota);
      expect(usage.reading?.model, groq.model);
      expect(usage.reading?.checkedAt, now);
      expect(usage.reading?.requestsAtCheck, usage.requests);
      expect(usage.freeQuotaFor(groq), 1000);
      expect(usage.leftFor(groq), 990);
    });

    test('a Groq reply with no requests left stops the route', () async {
      providers[AiProviderType.groq] = _FakeProvider(
        const AiReply(
          text: 'from Groq',
          freeQuota: FreeQuota(limit: 1000, remaining: 0),
        ),
      );

      expect(await send([groq, openRouter]), 'from Groq');
      expect(await send([groq, openRouter]), 'from OpenRouter');
      expect(providers[AiProviderType.groq]!.calls, 1);
    });

    test("a Groq quota counts only for the model it's for", () async {
      await tracker.report(groq, const FreeQuota(limit: 1000, remaining: 0));
      expect(await send([groq, openRouter]), 'from OpenRouter');

      // Groq's quota is per model, so another model is still free.
      final otherModel = groq.copyWith(model: 'openai/gpt-oss-120b');
      expect(await send([otherModel, openRouter]), 'from Groq');
      expect(providers[AiProviderType.groq]!.lastModel, otherModel.model);
    });

    test("OpenRouter's quota covers all its free models", () async {
      await tracker.report(
        openRouter,
        const FreeQuota(limit: 50, remaining: 0),
      );
      final otherModel = openRouter.copyWith(model: 'z-ai/glm-5:free');
      expect(await send([otherModel, groq]), 'from Groq');
      expect(providers[AiProviderType.openRouter]!.calls, 0);
    });

    test(
      'a used-up route waits for midnight, even when a 429 is shorter',
      () async {
        await tracker.report(
          openRouter,
          const FreeQuota(limit: 50, remaining: 0),
        );
        await tracker.block(
          openRouter,
          until: now.add(const Duration(minutes: 1)),
        );

        await expectLater(
          send([openRouter]),
          throwsA(
            isA<QuotaExhaustedException>().having(
              (error) => error.resetAt,
              'resetAt',
              DateTime.utc(2026, 10),
            ),
          ),
        );
      },
    );

    test(
      'a limit of 0 has no reset time, so a missing key still shows',
      () async {
        providers[AiProviderType.groq] = _FakeProvider(
          const AiReply(text: ''),
          error: const MissingApiKeyException(),
        );

        await expectLater(
          send([openRouter.copyWith(userLimit: 0), groq]),
          throwsA(isA<MissingApiKeyException>()),
        );
        expect(providers[AiProviderType.openRouter]!.calls, 0);
      },
    );

    test('a route with a limit of 0 is skipped', () async {
      await tracker.report(
        openRouter,
        const FreeQuota(limit: 50, remaining: 50),
      );
      expect(
        await send([openRouter.copyWith(userLimit: 0), groq]),
        'from Groq',
      );
      expect(providers[AiProviderType.openRouter]!.calls, 0);
      // Even when the provider hasn't reported its quota today.
      expect(
        await send([groq.copyWith(userLimit: 0), openRouter]),
        'from OpenRouter',
      );
      expect(providers[AiProviderType.groq]!.calls, 1);
    });
  });
}

AutoRouter _router(
  List<QuotaRoute> routes,
  Map<AiProviderType, _FakeProvider> providers,
  UsageTracker tracker, {
  DateTime Function()? now,
}) => AutoRouter(
  providers: providers,
  loadRoutes: () async => routes,
  usageTracker: tracker,
  now: now ?? DateTime.now,
);

class _FakeProvider implements AiProvider {
  _FakeProvider(this.reply, {this.error});

  final AiReply reply;
  final Object? error;
  int calls = 0;
  String? lastModel;

  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async => reply;

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async* {
    calls++;
    lastModel = model;
    if (error != null) throw error!;
    yield reply;
  }
}
