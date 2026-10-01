import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/models/quota_route.dart';
import 'package:cozy_sidekick/models/speech_settings.dart';
import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults to OpenRouter and persists provider and custom URL', () async {
    final first = SettingsService();
    expect(await first.loadSelectedProvider(), AiProviderType.openRouter);
    await first.saveSelectedProvider(AiProviderType.customServer);
    await first.saveCustomServerBaseUrl('  https://example.com/api/  ');
    final afterRestart = SettingsService();
    expect(
      await afterRestart.loadSelectedProvider(),
      AiProviderType.customServer,
    );
    expect(
      await afterRestart.loadCustomServerBaseUrl(),
      'https://example.com/api/',
    );
  });

  test('a model is saved per provider and survives a restart', () async {
    final first = SettingsService();
    for (final provider in AiProviderType.values) {
      expect(await first.loadModel(provider), isNull, reason: '$provider');
    }
    await first.saveModel(AiProviderType.openAi, '  gpt-6-sol  ');
    await first.saveModel(AiProviderType.groq, 'openai/gpt-oss-120b');

    final afterRestart = SettingsService();
    expect(await afterRestart.loadModel(AiProviderType.openAi), 'gpt-6-sol');
    expect(
      await afterRestart.loadModel(AiProviderType.groq),
      'openai/gpt-oss-120b',
    );
    expect(await afterRestart.loadModel(AiProviderType.openRouter), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai.model.openAi'), 'gpt-6-sol');
  });

  test('saving no model goes back to the default', () async {
    final settings = SettingsService();
    for (final model in <String?>[null, '', '   ']) {
      await settings.saveModel(AiProviderType.openAi, 'gpt-6-sol');
      await settings.saveModel(AiProviderType.openAi, model);
      expect(
        await settings.loadModel(AiProviderType.openAi),
        isNull,
        reason: '"$model"',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('ai.model.openAi'), isFalse);
    }
  });

  test('message formatting has defaults and survives a restart', () async {
    final first = SettingsService();
    expect(await first.loadMessageFormatting(), const MessageFormatting());
    const changed = MessageFormatting(
      formatReplies: false,
      showMath: false,
      dollarMath: true,
    );
    await first.saveMessageFormatting(changed);
    expect(await SettingsService().loadMessageFormatting(), changed);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('chat.format_replies'), isFalse);
    expect(prefs.getBool('chat.show_math'), isFalse);
    expect(prefs.getBool('chat.dollar_math'), isTrue);
  });

  test('show reasoning is off by default and survives a restart', () async {
    final first = SettingsService();
    expect(await first.loadShowReasoning(), isFalse);
    await first.saveShowReasoning(true);
    expect(await SettingsService().loadShowReasoning(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('chat.show_reasoning'), isTrue);
  });

  test('speech settings have defaults and survive a restart', () async {
    final first = SettingsService();
    expect(await first.loadSpeechSettings(), const SpeechSettings());
    const changed = SpeechSettings(
      languageId: 'fr-FR',
      sendWhenDone: true,
      readAloud: ReadAloudMode.afterSpoken,
      voiceName: 'French Voice',
      voiceLocale: 'fr-FR',
      rate: 0.65,
    );
    await first.saveSpeechSettings(changed);

    expect(await SettingsService().loadSpeechSettings(), changed);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('speech.language'), 'fr-FR');
    expect(prefs.getBool('speech.send_when_done'), isTrue);
    expect(prefs.getString('speech.read_aloud'), 'afterSpoken');
    expect(prefs.getString('speech.voice_name'), 'French Voice');
    expect(prefs.getString('speech.voice_locale'), 'fr-FR');
    expect(prefs.getDouble('speech.rate'), 0.65);
  });
  test(
    'auto-routing and ordered routes persist while routing defaults off',
    () async {
      final first = SettingsService();
      expect(await first.loadAutoRouteEnabled(), isFalse);
      expect(await first.loadQuotaRoutes(), QuotaRoute.defaults);
      final reordered = [
        QuotaRoute.defaults[1],
        QuotaRoute.defaults[0].copyWith(
          model: 'openrouter/custom',
          userLimit: 7,
        ),
        QuotaRoute.defaults[2],
      ];
      await first.saveAutoRouteEnabled(true);
      await first.saveQuotaRoutes(reordered);

      final afterRestart = SettingsService();
      expect(await afterRestart.loadAutoRouteEnabled(), isTrue);
      expect(await afterRestart.loadQuotaRoutes(), reordered);
    },
  );

  test('accepts http/https and rejects invalid custom URLs', () {
    expect(SettingsService.isValidBaseUrl('https://example.com'), isTrue);
    expect(SettingsService.isValidBaseUrl('http://localhost:8080'), isTrue);
    expect(SettingsService.isValidBaseUrl('example.com'), isFalse);
    expect(
      SettingsService().saveCustomServerBaseUrl('ftp://example.com'),
      throwsArgumentError,
    );
  });
}
