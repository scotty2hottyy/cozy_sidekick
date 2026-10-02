import 'package:cozy_sidekick/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a custom URL needs a port HTTP can use', () {
    for (final url in <String>[
      'http://localhost:1',
      'http://localhost:8080',
      'https://example.com:65535/api',
      'https://example.com',
    ]) {
      expect(SettingsService.isValidBaseUrl(url), isTrue, reason: url);
    }
    for (final url in <String>[
      'http://192.168.1.10:80800',
      'http://localhost:0',
      'http://localhost:65536',
      'http://localhost:99999999999999999999999',
    ]) {
      expect(SettingsService.isValidBaseUrl(url), isFalse, reason: url);
    }
  });

  test('a URL with a bad port is not saved', () async {
    for (final store in <AppSettingsStore>[
      SettingsService(),
      InMemorySettingsStore(),
    ]) {
      await store.saveCustomServerBaseUrl('https://example.com');
      await expectLater(
        store.saveCustomServerBaseUrl('http://192.168.1.10:80800'),
        throwsArgumentError,
      );
      expect(await store.loadCustomServerBaseUrl(), 'https://example.com');
    }
  });

  test('saving drops trailing slashes and one last /chat', () async {
    for (final (typed, saved) in <(String, String)>[
      ('https://example.com/chat', 'https://example.com'),
      ('  https://example.com/chat/  ', 'https://example.com'),
      ('https://example.com:8443/api/chat', 'https://example.com:8443/api'),
      ('https://example.com/chat/chat', 'https://example.com/chat'),
      ('https://example.com//', 'https://example.com'),
      // Only a whole last segment named chat is dropped.
      ('https://example.com/chatbot', 'https://example.com/chatbot'),
      ('https://example.com/my-chat', 'https://example.com/my-chat'),
      ('https://chat', 'https://chat'),
      ('https://example.com/chat?key=1', 'https://example.com/chat?key=1'),
    ]) {
      for (final store in <AppSettingsStore>[
        SettingsService(),
        InMemorySettingsStore(),
      ]) {
        await store.saveCustomServerBaseUrl(typed);
        expect(
          await store.loadCustomServerBaseUrl(),
          saved,
          reason: '$typed in ${store.runtimeType}',
        );
      }
    }
  });

  test('a URL that is only /chat is still rejected', () async {
    await expectLater(
      SettingsService().saveCustomServerBaseUrl('/chat'),
      throwsArgumentError,
    );
    await expectLater(
      InMemorySettingsStore().saveCustomServerBaseUrl('/chat'),
      throwsArgumentError,
    );
  });

  test('an empty URL can still be saved to clear it', () async {
    final settings = SettingsService();
    await settings.saveCustomServerBaseUrl('https://example.com');
    await settings.saveCustomServerBaseUrl('   ');
    expect(await settings.loadCustomServerBaseUrl(), isEmpty);
  });
}
