import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_provider.dart';
import '../models/message_formatting.dart';

abstract interface class AppSettingsStore {
  Future<AiProviderType> loadSelectedProvider();
  Future<void> saveSelectedProvider(AiProviderType provider);

  /// The model chosen for [provider], or null while it uses its default.
  Future<String?> loadModel(AiProviderType provider);

  /// Saves [model] for [provider]. Null or blank goes back to the default.
  Future<void> saveModel(AiProviderType provider, String? model);

  Future<String> loadCustomServerBaseUrl();
  Future<void> saveCustomServerBaseUrl(String url);
  Future<MessageFormatting> loadMessageFormatting();
  Future<void> saveMessageFormatting(MessageFormatting formatting);

  /// Whether replies show the model's reasoning when it shares any. Off by
  /// default, because reasoning can be long.
  Future<bool> loadShowReasoning();
  Future<void> saveShowReasoning(bool value);
}

class SettingsService implements AppSettingsStore {
  static const String _providerKey = 'ai.selected_provider';
  static const String _customUrlKey = 'ai.custom_server_base_url';
  static const String _formatRepliesKey = 'chat.format_replies';
  static const String _showMathKey = 'chat.show_math';
  static const String _dollarMathKey = 'chat.dollar_math';
  static const String _showReasoningKey = 'chat.show_reasoning';
  static String _modelKey(AiProviderType provider) =>
      'ai.model.${provider.name}';

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
  Future<String?> loadModel(AiProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelKey(provider));
  }

  @override
  Future<void> saveModel(AiProviderType provider, String? model) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = model?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_modelKey(provider));
    } else {
      await prefs.setString(_modelKey(provider), trimmed);
    }
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

  @override
  Future<MessageFormatting> loadMessageFormatting() async {
    final prefs = await SharedPreferences.getInstance();
    const defaults = MessageFormatting();
    return MessageFormatting(
      formatReplies: prefs.getBool(_formatRepliesKey) ?? defaults.formatReplies,
      showMath: prefs.getBool(_showMathKey) ?? defaults.showMath,
      dollarMath: prefs.getBool(_dollarMathKey) ?? defaults.dollarMath,
    );
  }

  @override
  Future<void> saveMessageFormatting(MessageFormatting formatting) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_formatRepliesKey, formatting.formatReplies);
    await prefs.setBool(_showMathKey, formatting.showMath);
    await prefs.setBool(_dollarMathKey, formatting.dollarMath);
  }

  @override
  Future<bool> loadShowReasoning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showReasoningKey) ?? false;
  }

  @override
  Future<void> saveShowReasoning(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showReasoningKey, value);
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
    Map<AiProviderType, String>? models,
    this.customServerBaseUrl = '',
    this.messageFormatting = const MessageFormatting(),
    this.showReasoning = false,
  }) : models = <AiProviderType, String>{...?models};

  AiProviderType selectedProvider;

  /// The chosen model for each provider that doesn't use its default.
  final Map<AiProviderType, String> models;
  String customServerBaseUrl;
  MessageFormatting messageFormatting;
  bool showReasoning;

  @override
  Future<AiProviderType> loadSelectedProvider() async => selectedProvider;
  @override
  Future<void> saveSelectedProvider(AiProviderType provider) async =>
      selectedProvider = provider;

  @override
  Future<String?> loadModel(AiProviderType provider) async => models[provider];
  @override
  Future<void> saveModel(AiProviderType provider, String? model) async {
    final trimmed = model?.trim() ?? '';
    if (trimmed.isEmpty) {
      models.remove(provider);
    } else {
      models[provider] = trimmed;
    }
  }

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

  @override
  Future<MessageFormatting> loadMessageFormatting() async => messageFormatting;
  @override
  Future<void> saveMessageFormatting(MessageFormatting formatting) async =>
      messageFormatting = formatting;

  @override
  Future<bool> loadShowReasoning() async => showReasoning;
  @override
  Future<void> saveShowReasoning(bool value) async => showReasoning = value;
}
