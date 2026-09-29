import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../services/model_list_service.dart';
import '../services/settings_service.dart';
import 'model_list_screen.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({
    super.key,
    required this.settingsStore,
    required this.modelLister,
  });
  final AppSettingsStore settingsStore;
  final ModelLister modelLister;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  AiProviderType? _selected;
  bool _showReasoning = false;

  /// The model saved for [_selected], or null while it uses its default.
  String? _model;

  /// Whether Custom… is chosen, which shows a field for any model ID.
  bool _customizing = false;
  final TextEditingController _customModelController = TextEditingController();
  final FocusNode _customModelFocus = FocusNode();

  /// The value of the Custom… entry in the model menu. No model ID is empty.
  static const String _custom = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selected = await widget.settingsStore.loadSelectedProvider();
    final showReasoning = await widget.settingsStore.loadShowReasoning();
    final model = await widget.settingsStore.loadModel(selected);
    if (mounted) {
      setState(() {
        _selected = selected;
        _showReasoning = showReasoning;
        _model = model;
      });
    }
  }

  Future<void> _select(AiProviderType? provider) async {
    if (provider == null) return;
    await widget.settingsStore.saveSelectedProvider(provider);
    final model = await widget.settingsStore.loadModel(provider);
    if (!mounted) return;
    setState(() {
      _selected = provider;
      _model = model;
      _closeCustom();
    });
  }

  Future<void> _setShowReasoning(bool value) async {
    setState(() => _showReasoning = value);
    await widget.settingsStore.saveShowReasoning(value);
  }

  /// Saves [model] for the selected provider. The default is saved as null,
  /// so the provider keeps using the built-in default if that changes.
  Future<void> _saveModel(String? model) async {
    final provider = _selected!;
    final saved = model == provider.defaultModel ? null : model;
    setState(() {
      _model = saved;
      _closeCustom();
    });
    await widget.settingsStore.saveModel(provider, saved);
  }

  void _closeCustom() {
    _customizing = false;
    _customModelController.clear();
  }

  void _onModelSelected(String? value) {
    if (value == null) return;
    if (value == _custom) {
      setState(() {
        _customizing = true;
        _customModelController.text = _model ?? '';
      });
      // autofocus can't do this, because the menu gives the focus back to
      // itself before it calls onSelected. The field takes it when it's built.
      _customModelFocus.requestFocus();
    } else {
      _saveModel(value);
    }
  }

  Future<void> _saveCustomModel() async {
    final model = _customModelController.text.trim();
    if (model.isEmpty) return;
    await _saveModel(model);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Model saved')));
  }

  Future<void> _openModelList() async {
    final provider = _selected!;
    final model = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ModelListScreen(
          provider: provider,
          modelLister: widget.modelLister,
          selected: _model ?? provider.defaultModel!,
        ),
      ),
    );
    if (model != null && mounted && _selected == provider) {
      await _saveModel(model);
    }
  }

  @override
  void dispose() {
    _customModelController.dispose();
    _customModelFocus.dispose();
    super.dispose();
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
              const SizedBox(height: 24),
              ..._modelPicker(_selected!),
              const SizedBox(height: 16),
              SwitchListTile(
                key: const Key('showReasoningSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Show reasoning'),
                subtitle: const Text(
                  'When a model shares its thinking, show it above the reply.',
                ),
                value: _showReasoning,
                onChanged: _setShowReasoning,
              ),
            ],
          ),
  );

  List<Widget> _modelPicker(AiProviderType provider) {
    final defaultModel = provider.defaultModel;
    if (defaultModel == null) {
      return const <Widget>[Text('The custom server picks its own model.')];
    }
    final current = _model ?? defaultModel;
    final models = <String>[
      ...provider.suggestedModels,
      if (!provider.suggestedModels.contains(current)) current,
    ];
    return <Widget>[
      DropdownMenu<String>(
        // Each provider gets its own menu, which starts at its model.
        key: ValueKey<AiProviderType>(provider),
        expandedInsets: EdgeInsets.zero,
        requestFocusOnTap: false,
        label: const Text('Model'),
        helperText: 'Larger models may cost more.',
        initialSelection: _customizing ? _custom : current,
        dropdownMenuEntries: <DropdownMenuEntry<String>>[
          for (final model in models)
            DropdownMenuEntry<String>(
              value: model,
              label: model == defaultModel ? '$model (default)' : model,
            ),
          const DropdownMenuEntry<String>(value: _custom, label: 'Custom…'),
        ],
        onSelected: _onModelSelected,
      ),
      if (_customizing) ...<Widget>[
        const SizedBox(height: 16),
        TextField(
          key: const Key('customModelField'),
          controller: _customModelController,
          focusNode: _customModelFocus,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Model ID',
            hintText: 'e.g. $defaultModel',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _saveCustomModel(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('saveCustomModel'),
            onPressed: _customModelController.text.trim().isEmpty
                ? null
                : _saveCustomModel,
            child: const Text('Save model'),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          OutlinedButton.icon(
            key: const Key('allModelsButton'),
            onPressed: _openModelList,
            icon: const Icon(Icons.search_rounded),
            label: const Text('All models'),
          ),
          TextButton(
            key: const Key('resetModelButton'),
            onPressed: _model == null && !_customizing
                ? null
                : () => _saveModel(null),
            child: const Text('Reset to default'),
          ),
        ],
      ),
    ];
  }
}
