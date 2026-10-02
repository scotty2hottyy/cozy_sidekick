import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_provider.dart';
import 'ai/custom_server_provider.dart';
import 'ai/groq_provider.dart';
import 'ai/openai_provider.dart';
import 'ai/openrouter_provider.dart';
import 'app.dart';
import 'services/api_key_store.dart';
import 'services/chat_service.dart';
import 'services/conversation_store.dart';
import 'services/first_launch_cleanup.dart';
import 'services/model_list_service.dart';
import 'services/provider_connection_service.dart';
import 'services/personality_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';
import 'services/text_to_speech_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsStore = SettingsService();
  final personalityStore = PersonalityService();
  final keyStore = SecureApiKeyStore();
  // Must run before initialize(), which writes the first-launch marker.
  await clearKeysLeftFromPreviousInstall(
    await SharedPreferences.getInstance(),
    keyStore,
  );
  await personalityStore.initialize();
  final providers = <AiProviderType, AiProvider>{
    AiProviderType.openRouter: OpenRouterProvider(keyStore: keyStore),
    AiProviderType.openAi: OpenAiProvider(keyStore: keyStore),
    AiProviderType.groq: GroqProvider(keyStore: keyStore),
    AiProviderType.customServer: CustomServerProvider(
      keyStore: keyStore,
      settingsStore: settingsStore,
    ),
  };
  final connectionTester = ProviderConnectionService(
    providers: providers,
    settingsStore: settingsStore,
  );
  runApp(
    CozySidekickApp(
      chatService: ChatService(
        conversationStore: FileConversationStore(),
        settingsStore: settingsStore,
        personalityStore: personalityStore,
        providers: providers,
      ),
      speechService: DeviceSpeechService(),
      textToSpeechService: DeviceTextToSpeechService(),
      settingsStore: settingsStore,
      personalityStore: personalityStore,
      keyStore: keyStore,
      connectionTester: connectionTester,
      modelLister: ModelListService(providers: providers),
    ),
  );
}
