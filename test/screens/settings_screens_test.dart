import 'dart:async';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/models/quota_route.dart';
import 'package:cozy_sidekick/screens/ai_settings_screen.dart';
import 'package:cozy_sidekick/screens/api_credentials_screen.dart';
import 'package:cozy_sidekick/screens/appearance_screen.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/free_quota_service.dart';
import 'package:cozy_sidekick/services/model_list_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/usage_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('provider selection is saved', (tester) async {
    final settings = InMemorySettingsStore();
    await tester.pumpWidget(_aiSettings(settings));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('providerDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groq').last);
    await tester.pumpAndSettle();
    expect(settings.selectedProvider, AiProviderType.groq);
  });

  testWidgets('auto-routing reveals routes and disables provider selection', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    await tester.pumpWidget(_aiSettings(settings));
    await tester.pumpAndSettle();

    expect(settings.autoRouteEnabled, isFalse);
    expect(
      find.byKey(const ValueKey('quota-route-openrouter-free')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('autoRouteSwitch')));
    await tester.pumpAndSettle();

    expect(settings.autoRouteEnabled, isTrue);
    expect(
      tester
          .widget<DropdownButtonFormField<AiProviderType>>(
            find.byKey(const Key('providerDropdown')),
          )
          .onChanged,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('quota-route-openrouter-free')),
      findsOneWidget,
    );
    expect(find.text('Groq'), findsOneWidget);
  });

  testWidgets('a route picks a free model and a limit below the quota', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    await settings.saveAutoRouteEnabled(true);
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'router-key');
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>[
          'openrouter/free',
          'google/gemma-4:free',
        ]),
        keyStore: keys,
        quotaReader: _FakeQuotaReader(
          const FreeQuota(limit: 50, remaining: 38),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('38 of 50 free requests left today'), findsOne);

    await tester.tap(find.byKey(const ValueKey('openrouter-free')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byKey(const Key('routeModelDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('google/gemma-4:free').last);
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byKey(const Key('dailyLimitSlider'))).onChanged!(
      20,
    );
    await tester.pump();
    expect(find.text('20 requests a day'), findsOne);
    await tester.tap(find.byKey(const Key('saveRouteButton')));
    await tester.pumpAndSettle();

    expect(settings.quotaRoutes.first.model, 'google/gemma-4:free');
    expect(settings.quotaRoutes.first.userLimit, 20);
    expect(find.textContaining('8 of your 20 requests left today'), findsOne);
  });

  testWidgets('OpenAI quota route requires explicit warning confirmation', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    await settings.saveAutoRouteEnabled(true);
    await tester.pumpWidget(_aiSettings(settings));
    await tester.pumpAndSettle();
    final openAiSwitch = find.byKey(const ValueKey('quota-route-openai-mini'));

    await tester.tap(openAiSwitch);
    await tester.pumpAndSettle();
    expect(find.text('OpenAI free tokens can be billed'), findsOneWidget);
    expect(settings.quotaRoutes.last.enabled, isFalse);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(settings.quotaRoutes.last.enabled, isTrue);
  });

  testWidgets('the route editor lists only free models and has no typing', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(autoRouteEnabled: true);
    final lister = _FakeModelLister(
      <String>['openrouter/free', 'google/gemma-4:free', 'x-ai/grok-4.7'],
      <String>['openrouter/free', 'google/gemma-4:free'],
    );
    await tester.pumpWidget(_aiSettings(settings, lister: lister));
    await tester.pumpAndSettle();
    await _openRoute(tester, 'openrouter-free');

    expect(find.text('Edit OpenRouter route'), findsOneWidget);
    expect(lister.freeRequests, <AiProviderType>[AiProviderType.openRouter]);
    expect(lister.requests, isEmpty);
    expect(_inDialog(find.byType(TextField)), findsNothing);
    expect(_inDialog(find.byType(TextFormField)), findsNothing);
    expect(_routeModelMenu(tester).items!.map((item) => item.value), <String>[
      'openrouter/free',
      'google/gemma-4:free',
    ]);
    await tester.tap(find.byKey(const Key('routeModelDropdown')));
    await tester.pumpAndSettle();
    expect(find.text('google/gemma-4:free'), findsOneWidget);
    expect(find.text('x-ai/grok-4.7'), findsNothing);
  });

  testWidgets('the slider saves a limit below the quota, or the whole quota', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(
      autoRouteEnabled: true,
      quotaRoutes: _routesWith(
        _defaultRoute('openrouter-free').copyWith(userLimit: 20),
      ),
    );
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'router-key');
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>['openrouter/free']),
        keyStore: keys,
        quotaReader: _FakeQuotaReader(
          const FreeQuota(limit: 50, remaining: 38),
        ),
        usageTracker: _tracker(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _status(tester, 'openrouter-free'),
      '8 of your 20 requests left today',
    );

    await _openRoute(tester, 'openrouter-free');
    expect(_limitSlider(tester).min, 0);
    expect(_limitSlider(tester).max, 50);
    expect(_limitSlider(tester).divisions, 50);
    expect(_limitSlider(tester).value, 20);
    expect(_limitShown(tester), '20 requests a day');
    expect(find.text('The free quota is 50 requests a day.'), findsOneWidget);

    // One below the quota is still the user's own limit.
    await _slideTo(tester, 49);
    expect(_limitShown(tester), '49 requests a day');
    await _saveRoute(tester);
    expect(settings.quotaRoutes.first.userLimit, 49);
    expect(
      _status(tester, 'openrouter-free'),
      '37 of your 49 requests left today',
    );

    await _openRoute(tester, 'openrouter-free');
    expect(_limitSlider(tester).value, 49);
    await tester.drag(
      find.byKey(const Key('dailyLimitSlider')),
      const Offset(1000, 0),
    );
    await tester.pumpAndSettle();
    expect(_limitSlider(tester).value, 50);
    expect(_limitShown(tester), 'Use the whole free quota');
    await _saveRoute(tester);

    expect(settings.quotaRoutes.first.userLimit, isNull);
    expect(settings.quotaRoutes.first.model, 'openrouter/free');
    expect(
      _status(tester, 'openrouter-free'),
      '38 of 50 free requests left today',
    );
  });

  testWidgets('another OpenAI group or usage tier resets the limit to 90%', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(autoRouteEnabled: true);
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>['gpt-6-sol', 'gpt-5.6-terra']),
        usageTracker: _tracker(),
      ),
    );
    await tester.pumpAndSettle();
    await _openRoute(tester, 'openai-mini');

    expect(find.text('Edit OpenAI route'), findsOneWidget);
    expect(_routeModelMenu(tester).items!.map((item) => item.value), <String>[
      'gpt-6-sol',
      'gpt-5.6-terra',
    ]);
    expect(_limitSlider(tester).max, 2500000);
    expect(_limitSlider(tester).value, 2250000);
    expect(_limitShown(tester), '2.25M tokens a day');

    await _pickRouteModel(tester, 'gpt-6-sol');
    expect(_limitSlider(tester).max, 250000);
    expect(_limitSlider(tester).value, 225000);
    expect(_limitShown(tester), '225K tokens a day');
    await _saveRoute(tester);
    expect(
      settings.quotaRoutes.last,
      _defaultRoute('openai-mini')
          .copyWith(model: 'gpt-6-sol', userLimit: 225000),
    );

    await _openRoute(tester, 'openai-mini');
    SwitchListTile tierSwitch() => tester.widget<SwitchListTile>(
      find.byKey(const Key('highUsageTierSwitch')),
    );
    expect(tierSwitch().value, isFalse);
    await tester.tap(find.byKey(const Key('highUsageTierSwitch')));
    await tester.pumpAndSettle();
    expect(tierSwitch().value, isTrue);
    expect(_limitSlider(tester).max, 1000000);
    expect(_limitSlider(tester).value, 900000);
    await _saveRoute(tester);

    expect(
      settings.quotaRoutes.last,
      _defaultRoute('openai-mini')
          .copyWith(model: 'gpt-6-sol', userLimit: 900000, highUsageTier: true),
    );
  });

  testWidgets('OpenAI models show their free tokens a day', (tester) async {
    await tester.pumpWidget(
      _aiSettings(
        InMemorySettingsStore(autoRouteEnabled: true),
        lister: _FakeModelLister(<String>['gpt-6-sol', 'gpt-5.6-terra']),
        usageTracker: _tracker(),
      ),
    );
    await tester.pumpAndSettle();
    await _openRoute(tester, 'openai-mini');

    // The tokens a day shown under a model in the open menu.
    Finder tokensUnder(String model, String tokens) => find.descendant(
      of: find.widgetWithText(Column, model),
      matching: find.text(tokens),
    );

    // The closed menu shows only the picked model, with its tokens below.
    expect(
      find.descendant(
        of: find.byKey(const Key('routeModelDropdown')),
        matching: find.text('2.5M tokens a day'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('routeModelDropdown')));
    await tester.pumpAndSettle();
    expect(tokensUnder('gpt-6-sol', '250K tokens a day'), findsOneWidget);
    expect(tokensUnder('gpt-5.6-terra', '2.5M tokens a day'), findsWidgets);
    await tester.tap(find.text('gpt-6-sol').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('highUsageTierSwitch')));
    await tester.pumpAndSettle();
    expect(_limitShown(tester), '900K tokens a day');
    expect(find.text('1M tokens a day'), findsOneWidget);
    await tester.tap(find.byKey(const Key('routeModelDropdown')));
    await tester.pumpAndSettle();
    expect(tokensUnder('gpt-6-sol', '1M tokens a day'), findsWidgets);
    expect(tokensUnder('gpt-5.6-terra', '10M tokens a day'), findsOneWidget);
  });

  testWidgets('each route row says how much is left today', (tester) async {
    final keys = InMemoryApiKeyStore();
    for (final provider in <AiProviderType>[
      AiProviderType.openRouter,
      AiProviderType.groq,
      AiProviderType.openAi,
    ]) {
      await keys.save(provider, 'test-key');
    }
    final tracker = _tracker();
    for (var i = 0; i < 3; i++) {
      await tracker.record(_defaultRoute('groq-free'));
    }
    await tracker.record(_defaultRoute('openai-mini'), tokens: 250000);
    await tester.pumpWidget(
      _aiSettings(
        InMemorySettingsStore(autoRouteEnabled: true),
        keyStore: keys,
        quotaReader: _FakeQuotaReader(
          const FreeQuota(limit: 50, remaining: 38),
        ),
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _status(tester, 'openrouter-free'),
      '38 of 50 free requests left today',
    );
    // Groq hasn't answered today, so only this app's requests are known.
    expect(
      _status(tester, 'groq-free'),
      '3 requests today · free quota unknown',
    );
    expect(
      _status(tester, 'openai-mini'),
      '2M of your 2.25M tokens left today',
    );
  });

  testWidgets('rows say when a route is used up or skipped', (tester) async {
    final keys = InMemoryApiKeyStore();
    for (final provider in <AiProviderType>[
      AiProviderType.openRouter,
      AiProviderType.groq,
      AiProviderType.openAi,
    ]) {
      await keys.save(provider, 'test-key');
    }
    final tracker = _tracker();
    await tracker.block(
      _defaultRoute('groq-free'),
      until: DateTime.utc(2100, 1, 1, 15, 30),
    );
    await tester.pumpWidget(
      _aiSettings(
        InMemorySettingsStore(
          autoRouteEnabled: true,
          quotaRoutes: _routesWith(
            _defaultRoute('openai-mini').copyWith(userLimit: 0),
          ),
        ),
        keyStore: keys,
        quotaReader: _FakeQuotaReader(const FreeQuota(limit: 50, remaining: 0)),
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();

    expect(_status(tester, 'openrouter-free'), 'Used up · resets 12:00 AM UTC');
    // A 429 says when it resets.
    expect(_status(tester, 'groq-free'), 'Used up · resets 3:30 PM UTC');
    expect(_status(tester, 'openai-mini'), 'Skipped · daily limit is 0');
  });

  testWidgets('quotas are only read while auto-routing is on', (tester) async {
    final settings = InMemorySettingsStore();
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'router-key');
    final reader = _FakeQuotaReader(const FreeQuota(limit: 50, remaining: 38));
    await tester.pumpWidget(
      _aiSettings(
        settings,
        keyStore: keys,
        quotaReader: reader,
        usageTracker: _tracker(),
      ),
    );
    await tester.pumpAndSettle();
    expect(reader.reads, isEmpty);

    await tester.tap(find.byKey(const Key('autoRouteSwitch')));
    await tester.pumpAndSettle();
    // Only providers with a key are read.
    expect(reader.reads, <AiProviderType>[AiProviderType.openRouter]);
    expect(
      _status(tester, 'openrouter-free'),
      '38 of 50 free requests left today',
    );
    expect(_status(tester, 'groq-free'), 'No key saved');
    expect(_status(tester, 'openai-mini'), 'No key saved');

    await tester.tap(find.byKey(const Key('autoRouteSwitch')));
    await tester.pumpAndSettle();
    expect(reader.reads, hasLength(1));
  });

  testWidgets('a Groq limit can be set once a reply reports its quota', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(autoRouteEnabled: true);
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'groq-key');
    final tracker = _tracker();
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>[
          'openai/gpt-oss-20b',
          'openai/gpt-oss-120b',
        ]),
        keyStore: keys,
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _status(tester, 'groq-free'),
      '0 requests today · free quota unknown',
    );

    await _openRoute(tester, 'groq-free');
    expect(find.byKey(const Key('dailyLimitSlider')), findsNothing);
    expect(find.byKey(const Key('dailyLimitText')), findsNothing);
    expect(
      find.textContaining('Groq reports its free quota with each reply.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.quotaRoutes, QuotaRoute.defaults);

    await tracker.record(
      _defaultRoute('groq-free'),
      quota: const FreeQuota(limit: 1000, remaining: 990),
    );
    await _openRoute(tester, 'groq-free');
    expect(_limitSlider(tester).max, 1000);
    expect(_limitSlider(tester).divisions, 100);
    expect(_limitShown(tester), 'Use the whole free quota');
    await _slideTo(tester, 500);
    expect(_limitShown(tester), '500 requests a day');
    await _saveRoute(tester);

    expect(
      settings.quotaRoutes[1],
      _defaultRoute('groq-free').copyWith(userLimit: 500),
    );
    expect(_status(tester, 'groq-free'), '490 of your 500 requests left today');
  });

  testWidgets("Groq's last quota sets the slider's maximum on a new day", (
    tester,
  ) async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'groq-key');
    var now = DateTime.utc(2026, 9, 29, 23);
    final tracker = UsageTracker(now: () => now);
    await tracker.record(
      _defaultRoute('groq-free'),
      quota: const FreeQuota(limit: 1000, remaining: 400),
    );
    now = DateTime.utc(2026, 9, 30, 9);
    await tester.pumpWidget(
      _aiSettings(
        InMemorySettingsStore(autoRouteEnabled: true),
        lister: _FakeModelLister(<String>[
          'openai/gpt-oss-20b',
          'openai/gpt-oss-120b',
        ]),
        keyStore: keys,
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();
    // The row only counts today's reading.
    expect(
      _status(tester, 'groq-free'),
      '0 requests today · free quota unknown',
    );

    await _openRoute(tester, 'groq-free');
    expect(_limitSlider(tester).max, 1000);

    // Each Groq model has its own quota, and this one never reported one.
    await _pickRouteModel(tester, 'openai/gpt-oss-120b');
    expect(find.byKey(const Key('dailyLimitSlider')), findsNothing);
    expect(
      find.textContaining('Groq reports its free quota with each reply.'),
      findsOneWidget,
    );
  });

  testWidgets("switching Groq models drops the other model's limit", (
    tester,
  ) async {
    final tracker = _tracker();
    final limited = _defaultRoute('groq-free').copyWith(userLimit: 0);
    await tracker.record(
      limited,
      quota: const FreeQuota(limit: 1000, remaining: 990),
    );
    final settings = InMemorySettingsStore(
      autoRouteEnabled: true,
      quotaRoutes: _routesWith(limited),
    );
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.groq, 'groq-key');
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>[
          'openai/gpt-oss-20b',
          'openai/gpt-oss-120b',
        ]),
        keyStore: keys,
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();

    await _openRoute(tester, 'groq-free');
    expect(_limitShown(tester), '0 requests a day');
    // The new model has no quota yet, so its limit couldn't be seen or
    // changed. The old model's limit of 0 doesn't come with it.
    await _pickRouteModel(tester, 'openai/gpt-oss-120b');
    expect(find.byKey(const Key('dailyLimitSlider')), findsNothing);
    await _saveRoute(tester);

    expect(
      settings.quotaRoutes[1],
      _defaultRoute('groq-free').copyWith(model: 'openai/gpt-oss-120b'),
    );
  });

  testWidgets('a slow, older quota read never replaces newer row text', (
    tester,
  ) async {
    final tracker = _tracker();
    await tracker.report(
      _defaultRoute('openrouter-free'),
      const FreeQuota(limit: 50, remaining: 38),
    );
    final settings = InMemorySettingsStore(autoRouteEnabled: true);
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'router-key');
    final reader = _SlowQuotaReader(const FreeQuota(limit: 50, remaining: 38));
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>['openrouter/free']),
        keyStore: keys,
        quotaReader: reader,
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();

    // The first read is still waiting when the user saves a limit.
    await _openRoute(tester, 'openrouter-free');
    await _slideTo(tester, 20);
    await _saveRoute(tester);
    expect(
      _status(tester, 'openrouter-free'),
      '8 of your 20 requests left today',
    );

    reader.first.complete(const FreeQuota(limit: 50, remaining: 38));
    await tester.pumpAndSettle();
    expect(
      _status(tester, 'openrouter-free'),
      '8 of your 20 requests left today',
    );
  });

  testWidgets('without a key, the route keeps its model and still saves', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(autoRouteEnabled: true);
    final tracker = _tracker();
    // A reply reported the quota before the key was deleted.
    await tracker.record(
      _defaultRoute('groq-free'),
      quota: const FreeQuota(limit: 1000, remaining: 990),
    );
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister.failing(const MissingApiKeyException()),
        usageTracker: tracker,
      ),
    );
    await tester.pumpAndSettle();
    expect(_status(tester, 'groq-free'), 'No key saved');

    await _openRoute(tester, 'groq-free');
    expect(
      find.text('Add your Groq key in API Credentials to see its free models.'),
      findsOneWidget,
    );
    expect(_routeModelMenu(tester).onChanged, isNull);
    expect(_inDialog(find.text('openai/gpt-oss-20b')), findsOneWidget);
    expect(_saveRouteButton(tester).onPressed, isNotNull);
    await _slideTo(tester, 500);
    await _saveRoute(tester);

    expect(
      settings.quotaRoutes[1],
      _defaultRoute('groq-free').copyWith(userLimit: 500),
    );
  });

  testWidgets('screen readers hear the model menu as a button', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _aiSettings(
        InMemorySettingsStore(autoRouteEnabled: true),
        lister: _FakeModelLister(<String>['gpt-6-sol', 'gpt-5.6-terra']),
        usageTracker: _tracker(),
      ),
    );
    await tester.pumpAndSettle();
    await _openRoute(tester, 'openai-mini');

    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byKey(const Key('routeModelDropdown')),
          matching: find.text('gpt-5.6-terra'),
        ),
      ),
      isSemantics(isButton: true),
    );
    // The daily limit reads as an amount, under its heading.
    final slider = tester.getSemantics(
      find.byKey(const Key('dailyLimitSlider')),
    );
    expect(slider, isSemantics(value: '2.25M tokens a day'));
    expect(slider.label, startsWith('Daily limit'));
    semantics.dispose();
  });

  testWidgets('without a key and no quota, the editor asks for a key', (
    tester,
  ) async {
    await tester.pumpWidget(
      _aiSettings(
        InMemorySettingsStore(autoRouteEnabled: true),
        lister: _FakeModelLister(<String>['openrouter/free']),
        usageTracker: _tracker(),
      ),
    );
    await tester.pumpAndSettle();

    await _openRoute(tester, 'openrouter-free');
    expect(find.byKey(const Key('dailyLimitSlider')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('quotaUnknownText'))).data,
      'Add your OpenRouter key in API Credentials to read its free quota and '
      'set a limit.',
    );
  });

  testWidgets('a saved model that is not free must be replaced to save', (
    tester,
  ) async {
    final settings = InMemorySettingsStore(
      autoRouteEnabled: true,
      quotaRoutes: _routesWith(
        _defaultRoute('openrouter-free').copyWith(model: 'x-ai/grok-4.7'),
      ),
    );
    await tester.pumpWidget(
      _aiSettings(
        settings,
        lister: _FakeModelLister(<String>[
          'openrouter/free',
          'google/gemma-4:free',
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await _openRoute(tester, 'openrouter-free');

    expect(
      find.text("x-ai/grok-4.7 isn't one of the free models. Pick one."),
      findsOneWidget,
    );
    expect(_saveRouteButton(tester).onPressed, isNull);
    await _pickRouteModel(tester, 'google/gemma-4:free');
    expect(find.textContaining("isn't one of the free models"), findsNothing);
    expect(_saveRouteButton(tester).onPressed, isNotNull);
    await _saveRoute(tester);

    expect(settings.quotaRoutes.first.model, 'google/gemma-4:free');
  });

  testWidgets('show reasoning is off by default and is saved', (tester) async {
    final settings = InMemorySettingsStore();
    Future<void> open() async {
      await tester.pumpWidget(_aiSettings(settings));
      await tester.pumpAndSettle();
    }

    SwitchListTile tile() => tester.widget<SwitchListTile>(
      find.byKey(const Key('showReasoningSwitch')),
    );

    await open();
    expect(tile().value, isFalse);
    expect(
      find.text('When a model shares its thinking, show it above the reply.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('showReasoningSwitch')));
    await tester.pumpAndSettle();
    expect(settings.showReasoning, isTrue);

    await tester.pumpWidget(const SizedBox());
    await open();
    expect(tile().value, isTrue);
  });

  testWidgets('API providers have a model picker, the custom server not', (
    tester,
  ) async {
    await tester.pumpWidget(_aiSettings(InMemorySettingsStore()));
    await tester.pumpAndSettle();
    for (final provider in AiProviderType.values) {
      await _pickProvider(tester, provider);
      if (provider == AiProviderType.customServer) {
        expect(find.byType(DropdownMenu<String>), findsNothing);
        expect(find.byKey(const Key('allModelsButton')), findsNothing);
        expect(find.byKey(const Key('resetModelButton')), findsNothing);
        expect(
          find.text('The custom server picks its own model.'),
          findsOneWidget,
        );
      } else {
        expect(
          _modelShown(tester),
          '${provider.defaultModel} (default)',
          reason: '$provider',
        );
        expect(find.text('Larger models may cost more.'), findsOneWidget);
      }
    }
  });

  testWidgets('a picked model is saved for its provider', (tester) async {
    final settings = InMemorySettingsStore(
      selectedProvider: AiProviderType.openAi,
    );
    Future<void> open() async {
      await tester.pumpWidget(_aiSettings(settings));
      await tester.pumpAndSettle();
    }

    await open();
    await _pickModel(tester, 'gpt-6-sol');
    expect(settings.models, <AiProviderType, String>{
      AiProviderType.openAi: 'gpt-6-sol',
    });
    expect(_modelShown(tester), 'gpt-6-sol');

    await _pickProvider(tester, AiProviderType.groq);
    expect(_modelShown(tester), 'openai/gpt-oss-20b (default)');
    await _pickModel(tester, 'openai/gpt-oss-120b');

    // Each provider keeps its own model when the screen opens again.
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(_modelShown(tester), 'openai/gpt-oss-120b');
    await _pickProvider(tester, AiProviderType.openAi);
    expect(_modelShown(tester), 'gpt-6-sol');
    expect(settings.models, <AiProviderType, String>{
      AiProviderType.openAi: 'gpt-6-sol',
      AiProviderType.groq: 'openai/gpt-oss-120b',
    });

    // Picking the default saves nothing, so it follows the built-in one.
    await _pickModel(tester, 'gpt-6-luna (default)');
    expect(settings.models.keys, <AiProviderType>[AiProviderType.groq]);
  });

  testWidgets('Custom… saves any model ID, and Reset to default undoes it', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    await tester.pumpWidget(_aiSettings(settings));
    await tester.pumpAndSettle();
    TextButton reset() =>
        tester.widget<TextButton>(find.byKey(const Key('resetModelButton')));
    FilledButton save() =>
        tester.widget<FilledButton>(find.byKey(const Key('saveCustomModel')));
    final customField = find.byKey(const Key('customModelField'));

    expect(reset().onPressed, isNull);
    await _pickModel(tester, 'Custom…');
    expect(_modelShown(tester), 'Custom…');
    // The field is ready for typing.
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: customField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(save().onPressed, isNull);
    await tester.enterText(customField, '  x-ai/grok-4.7  ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveCustomModel')));
    await tester.pumpAndSettle();
    expect(settings.models, <AiProviderType, String>{
      AiProviderType.openRouter: 'x-ai/grok-4.7',
    });
    expect(find.text('Model saved'), findsOneWidget);
    expect(customField, findsNothing);
    expect(_modelShown(tester), 'x-ai/grok-4.7');

    // Custom… starts from the saved ID.
    await _pickModel(tester, 'Custom…');
    expect(
      tester.widget<TextField>(customField).controller!.text,
      'x-ai/grok-4.7',
    );

    await tester.tap(find.byKey(const Key('resetModelButton')));
    await tester.pumpAndSettle();
    expect(settings.models, isEmpty);
    expect(customField, findsNothing);
    expect(_modelShown(tester), 'openrouter/free (default)');
    expect(reset().onPressed, isNull);
  });

  testWidgets('All models searches every model and saves the one tapped', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    final lister = _FakeModelLister(<String>[
      'anthropic/claude-sonnet-5.5',
      'moonshotai/Kimi-K2-Instruct',
      'openrouter/free',
      'x-ai/grok-4.6',
      'x-ai/grok-4.7',
    ]);
    await tester.pumpWidget(_aiSettings(settings, lister: lister));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allModelsButton')));
    await tester.pumpAndSettle();

    expect(find.text('OpenRouter Models'), findsOneWidget);
    expect(lister.requests, <AiProviderType>[AiProviderType.openRouter]);
    expect(find.byType(ListTile), findsNWidgets(5));
    // The model in use is checked, and the default is marked.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'openrouter/free'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('Default'), findsOneWidget);

    // Search ignores case, in the query and in the IDs.
    await tester.enterText(find.byKey(const Key('modelSearch')), 'kimi');
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    await tester.enterText(find.byKey(const Key('modelSearch')), 'GROK');
    await tester.pump();
    expect(find.byType(ListTile), findsNWidgets(2));
    await tester.tap(find.text('x-ai/grok-4.7'));
    await tester.pumpAndSettle();

    expect(find.text('AI Settings'), findsOneWidget);
    expect(settings.models, <AiProviderType, String>{
      AiProviderType.openRouter: 'x-ai/grok-4.7',
    });
    expect(_modelShown(tester), 'x-ai/grok-4.7');
  });

  testWidgets('All models falls back to the suggested ones', (tester) async {
    for (final (error, reason) in <(AiProviderException, String)>[
      (
        const MissingApiKeyException(),
        'Add a key in API Credentials to see every model. Until then, here '
            'are the suggested ones.',
      ),
      (
        const NetworkException(),
        "Couldn't load every model, so here are the suggested ones.",
      ),
    ]) {
      await tester.pumpWidget(
        _aiSettings(
          InMemorySettingsStore(selectedProvider: AiProviderType.openAi),
          lister: _FakeModelLister.failing(error),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('allModelsButton')));
      await tester.pumpAndSettle();

      expect(find.text(reason), findsOneWidget);
      for (final model in AiProviderType.openAi.suggestedModels) {
        expect(find.widgetWithText(ListTile, model), findsOneWidget);
      }
      await tester.enterText(find.byKey(const Key('modelSearch')), 'claude');
      await tester.pump();
      expect(find.text('No models match.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('custom URL and credential can be saved and connection tested', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = InMemorySettingsStore();
    final keys = InMemoryApiKeyStore();
    final testerService = ProviderConnectionService(
      providers: <AiProviderType, AiProvider>{
        for (final type in AiProviderType.values) type: _OkProvider(),
      },
      settingsStore: settings,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ApiCredentialsScreen(
          settingsStore: settings,
          keyStore: keys,
          connectionTester: testerService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final urlField = find.byKey(const Key('customServerUrl')).first;
    await tester.enterText(urlField, 'https://example.com');
    await tester.tap(find.byKey(const Key('saveCustomServerUrl')));
    await tester.pump();
    expect(settings.customServerBaseUrl, 'https://example.com');
    await tester.enterText(
      find.byKey(const ValueKey<String>('credential-customServer')),
      ' token ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('save-customServer')));
    await tester.pumpAndSettle();
    expect(await keys.read(AiProviderType.customServer), 'token');
    await tester.tap(find.byKey(const ValueKey<String>('test-customServer')));
    await tester.pumpAndSettle();
    expect(find.text('Connection successful'), findsOneWidget);
  });

  testWidgets('Groq credential uses the existing save and test controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final keys = InMemoryApiKeyStore();
    var requests = 0;
    final settings = InMemorySettingsStore();
    final connectionTester = ProviderConnectionService(
      providers: <AiProviderType, AiProvider>{
        AiProviderType.groq: GroqProvider(
          keyStore: keys,
          client: MockClient((_) async {
            requests++;
            return http.Response(
              '{"choices":[{"message":{"content":"OK"}}]}',
              200,
            );
          }),
        ),
      },
      settingsStore: settings,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ApiCredentialsScreen(
          settingsStore: settings,
          keyStore: keys,
          connectionTester: connectionTester,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Groq'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('credential-groq')),
      '  groq-key  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('save-groq')));
    await tester.pumpAndSettle();
    expect(await keys.read(AiProviderType.groq), 'groq-key');

    await tester.tap(find.byKey(const ValueKey<String>('test-groq')));
    await tester.pumpAndSettle();
    expect(find.text('Connection successful'), findsOneWidget);
    expect(requests, 1);
  });

  testWidgets('appearance switches are saved and depend on each other', (
    tester,
  ) async {
    final settings = InMemorySettingsStore();
    await tester.pumpWidget(
      MaterialApp(home: AppearanceScreen(settingsStore: settings)),
    );
    await tester.pumpAndSettle();
    SwitchListTile tile(String key) =>
        tester.widget<SwitchListTile>(find.byKey(Key(key)));
    Future<void> toggle(String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    expect(tile('formatRepliesSwitch').value, isTrue);
    expect(tile('showMathSwitch').value, isTrue);
    expect(tile('dollarMathSwitch').value, isFalse);

    await toggle('dollarMathSwitch');
    expect(
      settings.messageFormatting,
      const MessageFormatting(dollarMath: true),
    );

    await toggle('showMathSwitch');
    expect(settings.messageFormatting.showMath, isFalse);
    expect(tile('dollarMathSwitch').onChanged, isNull);

    await toggle('formatRepliesSwitch');
    expect(settings.messageFormatting.formatReplies, isFalse);
    expect(tile('showMathSwitch').onChanged, isNull);
    expect(tile('dollarMathSwitch').onChanged, isNull);

    // Turning formatting back on keeps the other choices.
    await toggle('formatRepliesSwitch');
    expect(
      settings.messageFormatting,
      const MessageFormatting(showMath: false, dollarMath: true),
    );
    expect(tile('showMathSwitch').onChanged, isNotNull);
  });
}

MaterialApp _aiSettings(
  AppSettingsStore settings, {
  ModelLister? lister,
  ApiKeyStore? keyStore,
  FreeQuotaReader? quotaReader,
  UsageTracker? usageTracker,
}) => MaterialApp(
  home: AiSettingsScreen(
    settingsStore: settings,
    modelLister: lister ?? _FakeModelLister(),
    keyStore: keyStore ?? InMemoryApiKeyStore(),
    quotaReader: quotaReader ?? _FakeQuotaReader(null),
    usageTracker: usageTracker,
  ),
);

/// Reports [quota] for OpenRouter, like its key endpoint, and remembers which
/// providers were read.
class _FakeQuotaReader implements FreeQuotaReader {
  _FakeQuotaReader(this.quota);

  final FreeQuota? quota;
  final List<AiProviderType> reads = <AiProviderType>[];

  @override
  Future<FreeQuota?> read(AiProviderType provider) async {
    reads.add(provider);
    return provider == AiProviderType.openRouter ? quota : null;
  }
}

/// Holds OpenRouter's first read until [first] completes, like a slow
/// network, and reports [quota] right away after that.
class _SlowQuotaReader implements FreeQuotaReader {
  _SlowQuotaReader(this.quota);

  final FreeQuota quota;
  final Completer<FreeQuota?> first = Completer<FreeQuota?>();
  int _reads = 0;

  @override
  Future<FreeQuota?> read(AiProviderType provider) async {
    if (provider != AiProviderType.openRouter) return null;
    return _reads++ == 0 ? first.future : quota;
  }
}

/// A usage tracker whose day is always 2026-09-30.
UsageTracker _tracker() =>
    UsageTracker(now: () => DateTime.utc(2026, 9, 30, 12));

/// The built-in route with [id].
QuotaRoute _defaultRoute(String id) =>
    QuotaRoute.defaults.firstWhere((route) => route.id == id);

/// The built-in routes, with [changed] in place of the one with its ID.
List<QuotaRoute> _routesWith(QuotaRoute changed) => <QuotaRoute>[
  for (final route in QuotaRoute.defaults)
    route.id == changed.id ? changed : route,
];

/// The line under route [id] that says how much of it is left today.
String _status(WidgetTester tester, String id) {
  final subtitle =
      tester
              .widget<ListTile>(find.byKey(ValueKey(id), skipOffstage: false))
              .subtitle!
          as Text;
  return subtitle.data!.split('\n').last;
}

/// Scrolls to route [id] and opens its editor.
Future<void> _openRoute(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey(id));
  await tester.scrollUntilVisible(
    row,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

/// The route editor's model menu.
DropdownButton<String> _routeModelMenu(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('routeModelDropdown')),
        matching: find.byType(DropdownButton<String>),
      ),
    );

/// Opens the route editor's model menu and taps [model].
Future<void> _pickRouteModel(WidgetTester tester, String model) async {
  await tester.tap(find.byKey(const Key('routeModelDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(model).last);
  await tester.pumpAndSettle();
}

Slider _limitSlider(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const Key('dailyLimitSlider')));

/// Moves the daily limit slider to [value], as a drag would.
Future<void> _slideTo(WidgetTester tester, double value) async {
  _limitSlider(tester).onChanged!(value);
  await tester.pump();
}

/// What the route editor says the daily limit is.
String _limitShown(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('dailyLimitText'))).data!;

FilledButton _saveRouteButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('saveRouteButton')));

Future<void> _saveRoute(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('saveRouteButton')));
  await tester.pumpAndSettle();
}

Future<void> _pickProvider(WidgetTester tester, AiProviderType provider) async {
  await tester.tap(find.byKey(const Key('providerDropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(provider.displayName).last);
  await tester.pumpAndSettle();
}

Finder get _modelMenu => find.descendant(
  of: find.byType(DropdownMenu<String>),
  matching: find.byType(TextField),
);

/// What the model menu shows.
String _modelShown(WidgetTester tester) =>
    tester.widget<TextField>(_modelMenu).controller!.text;

/// Opens the model menu and taps the entry labeled [label].
Future<void> _pickModel(WidgetTester tester, String label) async {
  await tester.tap(_modelMenu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Lists [models] for every provider, and [free] as its free models (all of
/// [models] unless given), or fails with an error.
class _FakeModelLister implements ModelLister {
  _FakeModelLister([this.models = const <String>[], List<String>? free])
    : free = free ?? models,
      error = null;
  _FakeModelLister.failing(AiProviderException this.error)
    : models = const <String>[],
      free = const <String>[];

  final List<String> models;
  final List<String> free;
  final AiProviderException? error;
  final List<AiProviderType> requests = <AiProviderType>[];
  final List<AiProviderType> freeRequests = <AiProviderType>[];

  @override
  Future<List<String>> listModels(AiProviderType provider) async {
    requests.add(provider);
    if (error != null) throw error!;
    return models;
  }

  @override
  Future<List<String>> listFreeModels(AiProviderType provider) async {
    freeRequests.add(provider);
    if (error != null) throw error!;
    return free;
  }
}

class _OkProvider implements AiProvider {
  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) async => const AiReply(text: 'OK');

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    Future<void>? abortTrigger,
    String? model,
  }) => Stream<AiReply>.value(const AiReply(text: 'OK'));
}
