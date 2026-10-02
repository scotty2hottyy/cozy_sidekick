import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_provider.dart';
import '../models/message_formatting.dart';
import '../models/quota_route.dart';
import '../models/speech_settings.dart';

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
  Future<SpeechSettings> loadSpeechSettings();
  Future<void> saveSpeechSettings(SpeechSettings settings);
  Future<bool> loadAutoRouteEnabled();
  Future<void> saveAutoRouteEnabled(bool value);
  Future<List<QuotaRoute>> loadQuotaRoutes();
  Future<void> saveQuotaRoutes(List<QuotaRoute> routes);
}

class SettingsService implements AppSettingsStore {
  static const String _providerKey = 'ai.selected_provider';
  static const String _customUrlKey = 'ai.custom_server_base_url';
  static const String _formatRepliesKey = 'chat.format_replies';
  static const String _showMathKey = 'chat.show_math';
  static const String _dollarMathKey = 'chat.dollar_math';
  static const String _showReasoningKey = 'chat.show_reasoning';
  static const String _speechLanguageKey = 'speech.language';
  static const String _speechSendWhenDoneKey = 'speech.send_when_done';
  static const String _speechReadAloudKey = 'speech.read_aloud';
  static const String _speechVoiceNameKey = 'speech.voice_name';
  static const String _speechVoiceLocaleKey = 'speech.voice_locale';
  static const String _speechRateKey = 'speech.rate';
  static const String _autoRouteKey = 'ai.auto_route';
  static const String _quotaRoutesKey = 'ai.quota_routes';
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
      throw ArgumentError('Base URL must be a valid http:// or https:// URL');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customUrlKey, normalizeBaseUrl(trimmed));
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

  @override
  Future<SpeechSettings> loadSpeechSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = ReadAloudMode.values
        .asNameMap()[prefs.getString(_speechReadAloudKey)];
    return SpeechSettings(
      languageId: prefs.getString(_speechLanguageKey),
      sendWhenDone: prefs.getBool(_speechSendWhenDoneKey) ?? false,
      readAloud: mode ?? ReadAloudMode.off,
      voiceName: prefs.getString(_speechVoiceNameKey),
      voiceLocale: prefs.getString(_speechVoiceLocaleKey),
      rate: prefs.getDouble(_speechRateKey) ?? 0.5,
    );
  }

  @override
  Future<void> saveSpeechSettings(SpeechSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    if (settings.languageId == null) {
      await prefs.remove(_speechLanguageKey);
    } else {
      await prefs.setString(_speechLanguageKey, settings.languageId!);
    }
    await prefs.setBool(_speechSendWhenDoneKey, settings.sendWhenDone);
    await prefs.setString(_speechReadAloudKey, settings.readAloud.name);
    if (settings.voiceName == null || settings.voiceLocale == null) {
      await prefs.remove(_speechVoiceNameKey);
      await prefs.remove(_speechVoiceLocaleKey);
    } else {
      await prefs.setString(_speechVoiceNameKey, settings.voiceName!);
      await prefs.setString(_speechVoiceLocaleKey, settings.voiceLocale!);
    }
    await prefs.setDouble(_speechRateKey, settings.rate);
  }

  @override
  Future<bool> loadAutoRouteEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoRouteKey) ?? false;
  }

  @override
  Future<void> saveAutoRouteEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoRouteKey, value);
  }

  @override
  Future<List<QuotaRoute>> loadQuotaRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_quotaRoutesKey);
    if (encoded == null) return List<QuotaRoute>.of(QuotaRoute.defaults);
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return List<QuotaRoute>.of(QuotaRoute.defaults);
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(QuotaRoute.fromJson)
          .toList();
    } on Object {
      return List<QuotaRoute>.of(QuotaRoute.defaults);
    }
  }

  @override
  Future<void> saveQuotaRoutes(List<QuotaRoute> routes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _quotaRoutesKey,
      jsonEncode(routes.map((route) => route.toJson()).toList()),
    );
  }

  /// Whether [value] is an http or https URL with a host, and a port HTTP
  /// can use when it has one. dart:io throws an ArgumentError for a port
  /// like 80800.
  static bool isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        (!uri.hasPort || _isUsablePort(uri));
  }

  static bool _isUsablePort(Uri uri) {
    try {
      return uri.port >= 1 && uri.port <= 65535;
    } on FormatException {
      // Too many digits to read as a number.
      return false;
    }
  }

  /// [value] trimmed, without trailing slashes or a last `/chat` segment.
  /// The custom server provider adds `/chat` itself, so a user who types
  /// the whole endpoint still reaches it, not `/chat/chat`.
  static String normalizeBaseUrl(String value) {
    final trailingSlashes = RegExp(r'/+$');
    final base = value.trim().replaceFirst(trailingSlashes, '');
    final uri = Uri.tryParse(base);
    // Only a path segment, never a host named "chat".
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/chat') ||
        !base.endsWith('/chat')) {
      return base;
    }
    return base
        .substring(0, base.length - '/chat'.length)
        .replaceFirst(trailingSlashes, '');
  }
}

class InMemorySettingsStore implements AppSettingsStore {
  InMemorySettingsStore({
    this.selectedProvider = AiProviderType.openRouter,
    Map<AiProviderType, String>? models,
    this.customServerBaseUrl = '',
    this.messageFormatting = const MessageFormatting(),
    this.showReasoning = false,
    this.speechSettings = const SpeechSettings(),
    this.autoRouteEnabled = false,
    List<QuotaRoute>? quotaRoutes,
  }) : models = <AiProviderType, String>{...?models},
       quotaRoutes = List<QuotaRoute>.of(quotaRoutes ?? QuotaRoute.defaults);

  AiProviderType selectedProvider;

  /// The chosen model for each provider that doesn't use its default.
  final Map<AiProviderType, String> models;
  String customServerBaseUrl;
  MessageFormatting messageFormatting;
  bool showReasoning;
  SpeechSettings speechSettings;
  bool autoRouteEnabled;
  List<QuotaRoute> quotaRoutes;

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
      throw ArgumentError('Base URL must be a valid http:// or https:// URL');
    }
    customServerBaseUrl = SettingsService.normalizeBaseUrl(trimmed);
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

  @override
  Future<SpeechSettings> loadSpeechSettings() async => speechSettings;
  @override
  Future<void> saveSpeechSettings(SpeechSettings settings) async =>
      speechSettings = settings;
  @override
  Future<bool> loadAutoRouteEnabled() async => autoRouteEnabled;
  @override
  Future<void> saveAutoRouteEnabled(bool value) async =>
      autoRouteEnabled = value;
  @override
  Future<List<QuotaRoute>> loadQuotaRoutes() async =>
      List<QuotaRoute>.unmodifiable(quotaRoutes);
  @override
  Future<void> saveQuotaRoutes(List<QuotaRoute> routes) async =>
      quotaRoutes = List<QuotaRoute>.of(routes);
}
