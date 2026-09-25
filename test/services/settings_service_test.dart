import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
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
