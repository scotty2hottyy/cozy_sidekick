import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/chat_service.dart';
import 'services/speech_service.dart';

class CozySidekickApp extends StatelessWidget {
  const CozySidekickApp({
    super.key,
    required this.chatService,
    required this.speechService,
  });
  final ChatService chatService;
  final SpeechService speechService;

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
    home: ChatScreen(chatService: chatService, speechService: speechService),
  );
}
