import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/api_key_store.dart';
import 'services/chat_service.dart';
import 'services/personality_service.dart';
import 'services/provider_connection_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';

class CozySidekickApp extends StatelessWidget {
  const CozySidekickApp({
    super.key,
    required this.chatService,
    required this.speechService,
    required this.settingsStore,
    required this.personalityStore,
    required this.keyStore,
    required this.connectionTester,
  });
  final ChatService chatService;
  final SpeechService speechService;
  final AppSettingsStore settingsStore;
  final PersonalityStore personalityStore;
  final ApiKeyStore keyStore;
  final ConnectionTester connectionTester;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cozy Sidekick',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6D5BBE)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF8F7FC),
      appBarTheme: const AppBarTheme(centerTitle: true),
    ),
    home: ChatScreen(
      chatService: chatService,
      speechService: speechService,
      settingsStore: settingsStore,
      personalityStore: personalityStore,
      keyStore: keyStore,
      connectionTester: connectionTester,
    ),
  );
}
