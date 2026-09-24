import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../services/settings_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key, required this.settingsStore});
  final AppSettingsStore settingsStore;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  AiProviderType? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selected = await widget.settingsStore.loadSelectedProvider();
    if (mounted) setState(() => _selected = selected);
  }

  Future<void> _select(AiProviderType? provider) async {
    if (provider == null) return;
    setState(() => _selected = provider);
    await widget.settingsStore.saveSelectedProvider(provider);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Settings')),
    body: _selected == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text(
                'Text Chat Provider',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Choose which service handles new chat messages.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<AiProviderType>(
                key: const Key('providerDropdown'),
                initialValue: _selected,
                decoration: const InputDecoration(
                  labelText: 'Provider',
                  border: OutlineInputBorder(),
                ),
                items: AiProviderType.values
                    .map(
                      (provider) => DropdownMenuItem<AiProviderType>(
                        value: provider,
                        child: Text(provider.displayName),
                      ),
                    )
                    .toList(),
                onChanged: _select,
              ),
            ],
          ),
  );
}
