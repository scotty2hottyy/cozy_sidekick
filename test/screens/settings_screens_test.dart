import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/screens/ai_settings_screen.dart';
import 'package:cozy_sidekick/screens/api_credentials_screen.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('provider selection is saved', (tester) async {
    final settings = InMemorySettingsStore();
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsScreen(settingsStore: settings)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('providerDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Server').last);
    await tester.pumpAndSettle();
    expect(settings.selectedProvider, AiProviderType.customServer);
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
}

class _OkProvider implements AiProvider {
  @override
  Future<String> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async => 'OK';
}
