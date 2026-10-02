import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/free_quota.dart';
import 'package:cozy_sidekick/screens/ai_settings_screen.dart';
import 'package:cozy_sidekick/screens/model_list_screen.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/free_quota_service.dart';
import 'package:cozy_sidekick/services/model_list_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:cozy_sidekick/services/usage_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('All models falls back after any error, never spinning', (
    tester,
  ) async {
    final logs = await _logsOf(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ModelListScreen(
            provider: AiProviderType.openAi,
            modelLister: _FailingLister(StateError('Bearer FAKE-key')),
            selected: AiProviderType.openAi.defaultModel!,
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text("Couldn't load every model, so here are the suggested ones."),
      findsOneWidget,
    );
    for (final model in AiProviderType.openAi.suggestedModels) {
      expect(find.widgetWithText(ListTile, model), findsOneWidget);
    }
    expect(logs, <String>['Model list failed: StateError']);
  });

  testWidgets('the route editor stops loading after any error', (tester) async {
    final settings = InMemorySettingsStore(autoRouteEnabled: true);
    final logs = await _logsOf(() async {
      await tester.pumpWidget(
        _aiSettings(
          settings,
          lister: _FailingLister(StateError('Bearer FAKE-key')),
        ),
      );
      await tester.pumpAndSettle();
      await _openRoute(tester, 'openrouter-free');
    });

    expect(find.text("Couldn't load the free models."), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('openrouter/free'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('saveRouteButton')))
          .onPressed,
      isNotNull,
    );
    expect(logs, <String>['Free model list failed: StateError']);
  });

  testWidgets('a failed quota check logs only the error type', (tester) async {
    final keys = InMemoryApiKeyStore();
    await keys.save(AiProviderType.openRouter, 'FAKE-key');
    final logs = await _logsOf(() async {
      await tester.pumpWidget(
        _aiSettings(
          InMemorySettingsStore(autoRouteEnabled: true),
          keyStore: keys,
          quotaReader: _FailingQuotaReader(
            const ModelNotAvailableException(
              'HTTP 403 model_not_found: Project `proj_abc`',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(logs, <String>[
      'Free quota check failed: ModelNotAvailableException',
    ]);
  });
}

/// What debugPrint writes while [body] runs.
///
/// The test binding checks that debugPrint is put back before the test
/// ends, so it's restored here rather than in a tear-down.
Future<List<String>> _logsOf(Future<void> Function() body) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return logs;
}

MaterialApp _aiSettings(
  AppSettingsStore settings, {
  ModelLister? lister,
  ApiKeyStore? keyStore,
  FreeQuotaReader? quotaReader,
}) => MaterialApp(
  home: AiSettingsScreen(
    settingsStore: settings,
    modelLister: lister ?? _FailingLister(StateError('unused')),
    keyStore: keyStore ?? InMemoryApiKeyStore(),
    quotaReader: quotaReader ?? _FailingQuotaReader(null),
    usageTracker: UsageTracker(now: () => DateTime.utc(2026, 9, 30, 12)),
  ),
);

/// Scrolls to route [id] and opens its editor.
Future<void> _openRoute(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey(id));
  await tester.scrollUntilVisible(
    row,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Fails every list with [error], which isn't an [AiProviderException].
class _FailingLister implements ModelLister {
  _FailingLister(this.error);

  final Object error;

  @override
  Future<List<String>> listModels(AiProviderType provider) async => throw error;

  @override
  Future<List<String>> listFreeModels(AiProviderType provider) async =>
      throw error;
}

/// Fails with [error], or reports no quota when it's null.
class _FailingQuotaReader implements FreeQuotaReader {
  _FailingQuotaReader(this.error);

  final AiProviderException? error;

  @override
  Future<FreeQuota?> read(AiProviderType provider) async {
    if (error != null) throw error!;
    return null;
  }
}
