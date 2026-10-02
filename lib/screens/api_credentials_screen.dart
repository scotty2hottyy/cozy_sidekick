import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../services/api_key_store.dart';
import '../services/provider_connection_service.dart';
import '../services/settings_service.dart';

class ApiCredentialsScreen extends StatefulWidget {
  const ApiCredentialsScreen({
    super.key,
    required this.settingsStore,
    required this.keyStore,
    required this.connectionTester,
  });
  final AppSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final ConnectionTester connectionTester;

  @override
  State<ApiCredentialsScreen> createState() => _ApiCredentialsScreenState();
}

class _ApiCredentialsScreenState extends State<ApiCredentialsScreen> {
  final TextEditingController _urlController = TextEditingController();
  String? _urlError;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _urlController.text = await widget.settingsStore.loadCustomServerBaseUrl();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveUrl() async {
    final value = _urlController.text.trim();
    if (!SettingsService.isValidBaseUrl(value)) {
      setState(() => _urlError = 'Enter a valid http:// or https:// URL.');
      return;
    }
    await widget.settingsStore.saveCustomServerBaseUrl(value);
    // Show what was saved, e.g. without a trailing "/chat" or slash.
    final saved = await widget.settingsStore.loadCustomServerBaseUrl();
    if (!mounted) return;
    _urlController.text = saved;
    setState(() => _urlError = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Custom server URL saved')));
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('API Credentials')),
    body: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              for (final provider in AiProviderType.values) ...<Widget>[
                _CredentialCard(
                  key: ValueKey<AiProviderType>(provider),
                  provider: provider,
                  keyStore: widget.keyStore,
                  connectionTester: widget.connectionTester,
                  customUrlEditor: provider == AiProviderType.customServer
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            TextField(
                              key: const Key('customServerUrl'),
                              controller: _urlController,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: 'Base URL',
                                hintText: 'https://example.com',
                                errorText: _urlError,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                key: const Key('saveCustomServerUrl'),
                                onPressed: _saveUrl,
                                child: const Text('Save URL'),
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
  );
}

class _CredentialCard extends StatefulWidget {
  const _CredentialCard({
    super.key,
    required this.provider,
    required this.keyStore,
    required this.connectionTester,
    this.customUrlEditor,
  });
  final AiProviderType provider;
  final ApiKeyStore keyStore;
  final ConnectionTester connectionTester;
  final Widget? customUrlEditor;

  @override
  State<_CredentialCard> createState() => _CredentialCardState();
}

class _CredentialCardState extends State<_CredentialCard> {
  final TextEditingController _controller = TextEditingController();
  bool _hasSecret = false;
  bool _replacing = false;
  bool _testing = false;
  String? _secretError;
  ConnectionTestResult? _result;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    bool value;
    try {
      value = await widget.keyStore.has(widget.provider);
    } on Object catch (error) {
      // Show the empty field so saving a key again can fix it.
      debugPrint('Key status check failed: ${error.runtimeType}');
      value = false;
    }
    if (mounted) setState(() => _hasSecret = value);
  }

  /// Keys and tokens only use visible ASCII. Anything else, such as an
  /// invisible character picked up in copy and paste, would break requests.
  static bool _isAllowedSecret(String value) =>
      value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7E);

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    if (!_isAllowedSecret(value)) {
      // Clear it so pasting again replaces the bad key instead of adding to it.
      _controller.clear();
      setState(
        () => _secretError =
            "This key has characters that aren't allowed. Paste it again.",
      );
      return;
    }
    try {
      await widget.keyStore.save(widget.provider, value);
    } on Object catch (error) {
      debugPrint('Key save failed: ${error.runtimeType}');
      if (mounted) _showMessage("Couldn't save the key. Please try again.");
      return;
    }
    _controller.clear();
    if (!mounted) return;
    setState(() {
      _hasSecret = true;
      _replacing = false;
      _secretError = null;
      _result = null;
    });
    _showMessage('Credential saved securely');
  }

  Future<void> _delete() async {
    try {
      await widget.keyStore.delete(widget.provider);
    } on Object catch (error) {
      debugPrint('Key delete failed: ${error.runtimeType}');
      if (mounted) _showMessage("Couldn't delete the key. Please try again.");
      return;
    }
    if (!mounted) return;
    setState(() {
      _hasSecret = false;
      _replacing = false;
      _result = null;
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await widget.connectionTester.testConnection(
      widget.provider,
    );
    if (mounted) {
      setState(() {
        _testing = false;
        _result = result;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.provider.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (widget.customUrlEditor != null) ...<Widget>[
            const SizedBox(height: 12),
            widget.customUrlEditor!,
          ],
          const SizedBox(height: 12),
          Text(
            _hasSecret ? 'Credential saved securely' : 'No credential saved',
          ),
          if (!_hasSecret || _replacing) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              key: ValueKey<String>('credential-${widget.provider.name}'),
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _secretError = null),
              decoration: InputDecoration(
                labelText: widget.provider.secretLabel,
                errorText: _secretError,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (_hasSecret && !_replacing) ...<Widget>[
                FilledButton(
                  onPressed: () => setState(() => _replacing = true),
                  child: const Text('Replace'),
                ),
                TextButton(onPressed: _delete, child: const Text('Delete')),
              ] else
                FilledButton(
                  key: ValueKey<String>('save-${widget.provider.name}'),
                  onPressed: _controller.text.trim().isEmpty ? null : _save,
                  child: const Text('Save'),
                ),
              OutlinedButton(
                key: ValueKey<String>('test-${widget.provider.name}'),
                onPressed: _testing ? null : _test,
                child: Text(_testing ? 'Testing…' : 'Test Connection'),
              ),
            ],
          ),
          if (_result != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _result!.message,
              style: TextStyle(
                color: _result!.isSuccess
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
