import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/screens/ai_settings_screen.dart';
import 'package:cozy_sidekick/screens/api_credentials_screen.dart';
import 'package:cozy_sidekick/screens/appearance_screen.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/model_list_service.dart';
import 'package:cozy_sidekick/services/provider_connection_service.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
    await tester.pumpWidget(_aiSettings(settings, lister));
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
          _FakeModelLister.failing(error),
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

MaterialApp _aiSettings(AppSettingsStore settings, [ModelLister? lister]) =>
    MaterialApp(
      home: AiSettingsScreen(
        settingsStore: settings,
        modelLister: lister ?? _FakeModelLister(),
      ),
    );

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

/// Lists [models] for every provider, or fails with an error.
class _FakeModelLister implements ModelLister {
  _FakeModelLister([this.models = const <String>[]]) : error = null;
  _FakeModelLister.failing(AiProviderException this.error)
    : models = const <String>[];

  final List<String> models;
  final AiProviderException? error;
  final List<AiProviderType> requests = <AiProviderType>[];

  @override
  Future<List<String>> listModels(AiProviderType provider) async {
    requests.add(provider);
    if (error != null) throw error!;
    return models;
  }
}

class _OkProvider implements AiProvider {
  @override
  Future<AiReply> sendChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? model,
  }) async => const AiReply(text: 'OK');

  @override
  Stream<AiReply> streamChat({
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? model,
  }) => Stream<AiReply>.value(const AiReply(text: 'OK'));
}
