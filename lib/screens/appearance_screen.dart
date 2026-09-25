import 'package:flutter/material.dart';

import '../models/message_formatting.dart';
import '../services/settings_service.dart';

/// Settings for how the chat looks. Changes are saved right away, and the
/// chat picks them up when the user goes back to it.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key, required this.settingsStore});
  final AppSettingsStore settingsStore;

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  MessageFormatting? _formatting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final formatting = await widget.settingsStore.loadMessageFormatting();
    if (mounted) setState(() => _formatting = formatting);
  }

  Future<void> _save(MessageFormatting formatting) async {
    setState(() => _formatting = formatting);
    await widget.settingsStore.saveMessageFormatting(formatting);
  }

  @override
  Widget build(BuildContext context) {
    final formatting = _formatting;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: formatting == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    Text(
                      'Message formatting',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text("Choose how your sidekick's replies look."),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('formatRepliesSwitch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Format replies'),
                      subtitle: const Text(
                        'Show bold text, lists, headings, links, code and '
                        'tables. When off, replies show their raw text.',
                      ),
                      value: formatting.formatReplies,
                      onChanged: (value) =>
                          _save(formatting.copyWith(formatReplies: value)),
                    ),
                    SwitchListTile(
                      key: const Key('showMathSwitch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show math'),
                      subtitle: const Text(
                        r'Show LaTeX written as \( … \) or \[ … \] as '
                        'equations. Needs Format replies.',
                      ),
                      value: formatting.showMath,
                      onChanged: formatting.formatReplies
                          ? (value) =>
                                _save(formatting.copyWith(showMath: value))
                          : null,
                    ),
                    SwitchListTile(
                      key: const Key('dollarMathSwitch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dollar-sign math'),
                      subtitle: const Text(
                        r'Also treat $ … $ and $$ … $$ as math. Off by '
                        'default because prices can look like math. Needs '
                        'Show math.',
                      ),
                      value: formatting.dollarMath,
                      onChanged: formatting.rendersMath
                          ? (value) =>
                                _save(formatting.copyWith(dollarMath: value))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
