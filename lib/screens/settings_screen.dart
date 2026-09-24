import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
              'AI & Provider Settings',
              'Choose a provider and model',
            ),
            _row(
              context,
              Icons.key_rounded,
              'API Credentials',
              'Manage provider keys securely',
            ),
            const SizedBox(height: 24),
            _section(context, 'Sidekick'),
            _row(
              context,
              Icons.auto_awesome_rounded,
              'Personality',
              'Customize voice, tone, and instructions',
            ),
            _row(
              context,
              Icons.record_voice_over_rounded,
              'Voice & Speech',
              'Configure speech input and output',
            ),
            const SizedBox(height: 24),
            _section(context, 'App'),
            _row(
              context,
              Icons.palette_outlined,
              'Appearance',
              'Theme and display options',
            ),
            _row(
              context,
              Icons.history_rounded,
              'Chat History',
              'History controls are coming soon',
            ),
            _row(context, Icons.info_outline_rounded, 'About', 'Cozy Sidekick'),
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
    String subtitle,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsPlaceholderScreen(title: title),
      ),
    ),
  );
}

class _SettingsPlaceholderScreen extends StatelessWidget {
  const _SettingsPlaceholderScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.construction_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '$title will be available in a future update.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
