import 'package:flutter/material.dart';

import 'ai/ai_provider.dart';
import 'ai/custom_server_provider.dart';
import 'ai/groq_provider.dart';
import 'ai/openai_provider.dart';
import 'ai/openrouter_provider.dart';
import 'app.dart';
import 'services/api_key_store.dart';
import 'services/chat_service.dart';
import 'services/chat_history_store.dart';
import 'services/provider_connection_service.dart';
import 'services/personality_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsStore = SettingsService();
  final personalityStore = PersonalityService();
  await personalityStore.initialize();
  final keyStore = SecureApiKeyStore();
  final providers = <AiProviderType, AiProvider>{
    AiProviderType.openRouter: OpenRouterProvider(keyStore: keyStore),
    AiProviderType.openAi: OpenAiProvider(keyStore: keyStore),
    AiProviderType.groq: GroqProvider(keyStore: keyStore),
    AiProviderType.customServer: CustomServerProvider(
      keyStore: keyStore,
      settingsStore: settingsStore,
    ),
  };
  final connectionTester = ProviderConnectionService(providers: providers);
  runApp(
    CozySidekickApp(
      chatService: ChatService(
        historyStore: FileChatHistoryStore(),
        settingsStore: settingsStore,
        personalityStore: personalityStore,
        providers: providers,
      ),
      speechService: DeviceSpeechService(),
      settingsStore: settingsStore,
      personalityStore: personalityStore,
      keyStore: keyStore,
      connectionTester: connectionTester,
    ),
  );
}
