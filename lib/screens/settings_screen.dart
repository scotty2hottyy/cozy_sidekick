import 'package:flutter/material.dart';

import '../services/api_key_store.dart';
import '../services/model_list_service.dart';
import '../services/provider_connection_service.dart';
import '../services/personality_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../services/text_to_speech_service.dart';
import 'ai_settings_screen.dart';
import 'api_credentials_screen.dart';
import 'appearance_screen.dart';
import 'chat_history_screen.dart';
import 'personality_screen.dart';
import 'voice_speech_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settingsStore,
    required this.personalityStore,
    required this.keyStore,
    required this.speechService,
    required this.textToSpeechService,
    required this.connectionTester,
    required this.modelLister,
    required this.onClearChat,
    this.onDeleteAllChats,
  });
  final Future<void> Function() onClearChat;
  final Future<void> Function()? onDeleteAllChats;
  final AppSettingsStore settingsStore;
  final PersonalityStore personalityStore;
  final ApiKeyStore keyStore;
  final SpeechService speechService;
  final TextToSpeechService textToSpeechService;
  final ConnectionTester connectionTester;
  final ModelLister modelLister;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            _section(context, 'AI'),
            _row(
              context,
              Icons.route_rounded,
              'AI Settings',
              'Provider, model and reasoning',
              destination: AiSettingsScreen(
                settingsStore: settingsStore,
                modelLister: modelLister,
                keyStore: keyStore,
              ),
            ),
            _row(
              context,
              Icons.key_rounded,
              'API Credentials',
              'Manage provider keys securely',
              destination: ApiCredentialsScreen(
                settingsStore: settingsStore,
                keyStore: keyStore,
                connectionTester: connectionTester,
              ),
            ),
            const SizedBox(height: 24),
            _section(context, 'Sidekick'),
            _row(
              context,
              Icons.auto_awesome_rounded,
              'Personality',
              'Customize tone and instructions',
              destination: PersonalityScreen(
                personalityStore: personalityStore,
              ),
            ),
            _row(
              context,
              Icons.record_voice_over_rounded,
              'Voice & Speech',
              'Configure speech input and output',
              destination: VoiceSpeechScreen(
                settingsStore: settingsStore,
                speechService: speechService,
                textToSpeechService: textToSpeechService,
              ),
            ),
            const SizedBox(height: 24),
            _section(context, 'App'),
            _row(
              context,
              Icons.palette_outlined,
              'Appearance',
              'Message formatting and math',
              destination: AppearanceScreen(settingsStore: settingsStore),
            ),
            _row(
              context,
              Icons.history_rounded,
              'Chat History',
              'Manage saved chat history',
              destination: ChatHistoryScreen(
                onClearChat: onClearChat,
                onDeleteAllChats: onDeleteAllChats,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );

  static Widget _row(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    required Widget destination,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => destination)),
  );
}
