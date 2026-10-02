import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/screens/api_credentials_screen.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _badCharacters =
    "This key has characters that aren't allowed. Paste it again.";
const _keyField = ValueKey<String>('credential-openRouter');
const _saveButton = ValueKey<String>('save-openRouter');

void main() {
  Future<void> pumpScreen(WidgetTester tester, ApiKeyStore keys) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ApiCredentialsScreen(
          settingsStore: InMemorySettingsStore(),
          keyStore: keys,
          connectionTester: _NoopConnectionTester(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a key with an invisible character is not saved', (tester) async {
    final keys = InMemoryApiKeyStore();
    await pumpScreen(tester, keys);

    await tester.enterText(find.byKey(_keyField), 'sk-or-​abc');
    await tester.pump();
    await tester.tap(find.byKey(_saveButton));
    await tester.pumpAndSettle();

    expect(find.text(_badCharacters), findsOneWidget);
    expect(await keys.read(AiProviderType.openRouter), isNull);
    final field = tester.widget<TextField>(find.byKey(_keyField));
    expect(field.controller!.text, isEmpty);

    await tester.enterText(find.byKey(_keyField), ' sk-or-abc ');
    await tester.pump();
    expect(find.text(_badCharacters), findsNothing);
    await tester.tap(find.byKey(_saveButton));
    await tester.pumpAndSettle();

    expect(await keys.read(AiProviderType.openRouter), 'sk-or-abc');
    expect(find.byKey(_keyField), findsNothing);
  });

  testWidgets('a failed save shows a message and keeps the key field', (
    tester,
  ) async {
    await pumpScreen(tester, _FailingKeyStore(failSave: true));

    await tester.enterText(find.byKey(_keyField), 'sk-or-abc');
    await tester.pump();
    await tester.tap(find.byKey(_saveButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text("Couldn't save the key. Please try again."),
      findsOneWidget,
    );
    expect(find.byKey(_keyField), findsOneWidget);
  });

  testWidgets('a failed status check still lets the user save a key', (
    tester,
  ) async {
    await pumpScreen(tester, _FailingKeyStore(failHas: true));

    expect(tester.takeException(), isNull);
    expect(find.byKey(_keyField), findsOneWidget);
    expect(find.text('No credential saved'), findsNWidgets(4));
  });

  testWidgets('a failed delete shows a message and keeps the key', (
    tester,
  ) async {
    final keys = _FailingKeyStore(failDelete: true);
    await keys.save(AiProviderType.openRouter, 'sk-or-abc');
    await pumpScreen(tester, keys);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text("Couldn't delete the key. Please try again."),
      findsOneWidget,
    );
    expect(find.text('Credential saved securely'), findsOneWidget);
    expect(await keys.read(AiProviderType.openRouter), 'sk-or-abc');
  });
}

class _FailingKeyStore extends InMemoryApiKeyStore {
  _FailingKeyStore({
    this.failSave = false,
    this.failHas = false,
    this.failDelete = false,
  });

  final bool failSave;
  final bool failHas;
  final bool failDelete;

  @override
  Future<void> save(AiProviderType provider, String secret) async {
    if (failSave) throw PlatformException(code: 'Exception encountered');
    await super.save(provider, secret);
  }

  @override
  Future<bool> has(AiProviderType provider) async {
    if (failHas) throw PlatformException(code: 'Exception encountered');
    return super.has(provider);
  }

  @override
  Future<void> delete(AiProviderType provider) async {
    if (failDelete) throw PlatformException(code: 'Exception encountered');
    await super.delete(provider);
  }
}

class _NoopConnectionTester implements ConnectionTester {
  @override
  Future<ConnectionTestResult> testConnection(AiProviderType provider) async =>
      const ConnectionTestResult(ConnectionTestStatus.success);
}
