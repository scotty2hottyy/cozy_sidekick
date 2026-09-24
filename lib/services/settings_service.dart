import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_provider.dart';

abstract interface class AppSettingsStore {
  Future<AiProviderType> loadSelectedProvider();
  Future<void> saveSelectedProvider(AiProviderType provider);
  Future<String> loadCustomServerBaseUrl();
  Future<void> saveCustomServerBaseUrl(String url);
}

class SettingsService implements AppSettingsStore {
  static const String _providerKey = 'ai.selected_provider';
  static const String _customUrlKey = 'ai.custom_server_base_url';

  @override
  Future<AiProviderType> loadSelectedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_providerKey);
    return AiProviderType.values.asNameMap()[name] ?? AiProviderType.openRouter;
  }

  @override
  Future<void> saveSelectedProvider(AiProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, provider.name);
  }

  @override
  Future<String> loadCustomServerBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customUrlKey) ?? '';
  }

  @override
  Future<void> saveCustomServerBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty && !isValidBaseUrl(trimmed)) {
      throw ArgumentError('Base URL must use http:// or https://');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customUrlKey, trimmed);
  }

  static bool isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

class InMemorySettingsStore implements AppSettingsStore {
  InMemorySettingsStore({
    this.selectedProvider = AiProviderType.openRouter,
    this.customServerBaseUrl = '',
  });

  AiProviderType selectedProvider;
  String customServerBaseUrl;

  @override
  Future<AiProviderType> loadSelectedProvider() async => selectedProvider;
  @override
  Future<void> saveSelectedProvider(AiProviderType provider) async =>
      selectedProvider = provider;
  @override
  Future<String> loadCustomServerBaseUrl() async => customServerBaseUrl;
  @override
  Future<void> saveCustomServerBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty && !SettingsService.isValidBaseUrl(trimmed)) {
      throw ArgumentError('Base URL must use http:// or https://');
    }
    customServerBaseUrl = trimmed;
  }
}
