import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/auto_router.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
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
    dailyLimit: 2,
  );
  const second = QuotaRoute(
    id: 'second',
    provider: AiProviderType.openCodeZen,
    model: 'second-model',
    unit: QuotaUnit.requests,
    dailyLimit: 2,
  );

  test(
    'tries enabled routes in order and records the successful route',
    () async {
      final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 29));
      final providers = <AiProviderType, _FakeProvider>{
        AiProviderType.openRouter: _FakeProvider(const AiReply(text: 'first')),
        AiProviderType.openCodeZen: _FakeProvider(
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
      expect(providers[AiProviderType.openCodeZen]!.calls, 0);
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
      dailyLimit: 5,
    );
    await tracker.record(tokenRoute, tokens: 5);
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(const AiReply(text: 'ok')),
      AiProviderType.openCodeZen: _FakeProvider(
        const AiReply(text: 'fallback'),
      ),
    };
    final router = _router([first, second], providers, tracker);

    final reply = await router.sendChat(
      systemPrompt: 'system',
      messages: <ChatMessage>[ChatMessage.user('Hi')],
    );
    expect(reply.text, 'fallback');
    expect(providers[AiProviderType.openRouter]!.calls, 0);
    expect(providers[AiProviderType.openCodeZen]!.calls, 1);
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
      AiProviderType.openCodeZen: _FakeProvider(
        const AiReply(text: 'fallback'),
      ),
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
    expect(providers[AiProviderType.openCodeZen]!.calls, 1);
  });

  test('network errors stop routing', () async {
    final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 29));
    final providers = <AiProviderType, _FakeProvider>{
      AiProviderType.openRouter: _FakeProvider(
        const AiReply(text: ''),
        error: const NetworkException(),
      ),
      AiProviderType.openCodeZen: _FakeProvider(
        const AiReply(text: 'must not run'),
      ),
    };

    await expectLater(
      _router([first, second], providers, tracker).sendChat(
        systemPrompt: 'system',
        messages: <ChatMessage>[ChatMessage.user('Hi')],
      ),
      throwsA(isA<NetworkException>()),
    );
    expect(providers[AiProviderType.openCodeZen]!.calls, 0);
  });

  test('all exhausted routes produce a reset time', () async {
    final tracker = UsageTracker(now: () => DateTime.utc(2026, 9, 29, 23));
    final exhausted = [
      first.copyWith(dailyLimit: 0),
      second.copyWith(dailyLimit: 0),
    ];
    final router = _router(
      exhausted,
      <AiProviderType, _FakeProvider>{},
      tracker,
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
  now: now,
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
