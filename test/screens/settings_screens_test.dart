import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/screens/ai_settings_screen.dart';
import 'package:cozy_sidekick/screens/api_credentials_screen.dart';
import 'package:cozy_sidekick/screens/appearance_screen.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('provider selection is saved', (tester) async {
    final settings = InMemorySettingsStore();
    await tester.pumpWidget(
      MaterialApp(home: AiSettingsScreen(settingsStore: settings)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('providerDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groq').last);
    await tester.pumpAndSettle();
    expect(settings.selectedProvider, AiProviderType.groq);
  });

  testWidgets('show reasoning is off by default and is saved', (tester) async {
    final settings = InMemorySettingsStore();
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(home: AiSettingsScreen(settingsStore: settings)),
      );
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

  testWidgets('Groq credential uses the existing save and test controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final keys = InMemoryApiKeyStore();
    var requests = 0;
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
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ApiCredentialsScreen(
          settingsStore: InMemorySettingsStore(),
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

class _OkProvider implements AiProvider {
  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) async => const AiReply(text: 'OK');

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
  }) => Stream<AiReply>.value(const AiReply(text: 'OK'));
}
