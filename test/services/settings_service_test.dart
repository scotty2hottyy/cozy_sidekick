import 'package:cozy_sidekick/ai/ai_provider.dart';
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
