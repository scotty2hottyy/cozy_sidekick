import 'package:flutter/material.dart';

import 'app.dart';
import 'services/chat_service.dart';
import 'services/speech_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CozySidekickApp(
      chatService: ChatService(),
      speechService: DeviceSpeechService(),
    ),
  );
}
