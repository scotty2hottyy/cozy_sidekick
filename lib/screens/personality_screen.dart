import 'package:flutter/material.dart';

import '../models/personality.dart';
import '../services/personality_service.dart';

/// Lets users create, edit, and choose the active AI personality.
class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({super.key, required this.personalityStore});

  final PersonalityStore personalityStore;

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  List<Personality> _personalities = <Personality>[];
  bool _isLoading = true;
  Personality? _active;

  @override
  void initState() {
    super.initState();
    _loadPersonalities();
  }

  Future<void> _loadPersonalities() async {
    final personalities = await widget.personalityStore.loadPersonalities();
    final active = await widget.personalityStore.loadActivePersonality();
    if (!mounted) return;
    setState(() {
      _active = active;
      _personalities = personalities;
      _isLoading = false;
    });
  }

  Future<void> _selectPersonality(Personality personality) async {
    try {
      await widget.personalityStore.setActivePersonality(personality.id);
      await _loadPersonalities();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not switch personality.')),
        );
      }
    }
  }

  Future<void> _setDefault(String id) async {
    final choices = <String, Personality>{
      for (final preset in Personality.presets) preset.id: preset,
      for (final saved in _personalities) saved.id: saved,
    };
    final selected = choices[id]!;
    await _savePersonalities([
      for (final personality in [
        ..._personalities,
        if (!_personalities.any((p) => p.id == id)) selected,
      ])
        Personality(
          id: personality.id,
          name: personality.name,
          systemPrompt: personality.systemPrompt,
          isDefault: personality.id == id,
        ),
    ]);
  }

  Future<void> _editPersonality({
    Personality? personality,
    Personality? preset,
  }) async {
    final result = await showDialog<_PersonalityDraft>(
      context: context,
      builder: (context) =>
          _PersonalityDialog(personality: personality, preset: preset),
    );
    if (result == null || !mounted) return;

    final updated = Personality(
      id: personality?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: preset != null && result.name == preset.name
          ? '${preset.name}Custom'
          : result.name,
      systemPrompt: result.systemPrompt,
      isDefault: result.isDefault,
    );
    final next = <Personality>[
      for (final existing in _personalities)
        if (existing.id != personality?.id)
          if (result.isDefault && existing.isDefault)
            Personality(
              id: existing.id,
              name: existing.name,
              systemPrompt: existing.systemPrompt,
            )
          else
            existing,
      updated,
    ];
    await _savePersonalities(next);
  }

  Future<void> _deletePersonality(Personality personality) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${personality.name}?'),
        content: const Text("This can't be undone."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final next = _personalities
        .where((item) => item.id != personality.id)
        .toList();
    await _savePersonalities(next);
  }

  Future<void> _savePersonalities(List<Personality> personalities) async {
    try {
      await widget.personalityStore.savePersonalities(personalities);
      await _loadPersonalities();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save personalities.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Personalities')),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: <Widget>[
                  Text(
                    'Choose how your sidekick responds',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap a preset or choose Use now. Switching applies to your next reply.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Choose a personality',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final preset in Personality.presets)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey(preset.id),
                              label: Text(preset.name),
                              selected: _active?.id == preset.id,
                              onSelected: (_) => _selectPersonality(preset),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'startup-default-${_personalities.firstWhere((p) => p.isDefault).id}',
                    ),
                    initialValue: _personalities
                        .firstWhere((p) => p.isDefault)
                        .id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Startup default',
                      helperText: 'Used when the app opens. Does not change your current personality.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final personality in <String, Personality>{
                        for (final preset in Personality.presets)
                          preset.id: preset,
                        for (final saved in _personalities) saved.id: saved,
                      }.values)
                        DropdownMenuItem(
                          value: personality.id,
                          child: Text(personality.name),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) _setDefault(id);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Active now: ${_active?.name ?? ""}'),
                  if (_active != null &&
                      Personality.presets.any((p) => p.id == _active!.id))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('customizePresetButton'),
                        onPressed: () => _editPersonality(preset: _active),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Customize preset'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  for (final personality in _personalities.where(
                    (saved) => !Personality.presets.any(
                      (preset) => preset.id == saved.id,
                    ),
                  ))
                    _PersonalityCard(
                      personality: personality,
                      isActive: _active?.id == personality.id,
                      onSelect: () => _selectPersonality(personality),
                      onEdit: () => _editPersonality(personality: personality),
                      onDelete: personality.isDefault
                          ? null
                          : () => _deletePersonality(personality),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('addPersonalityButton'),
                    onPressed: () => _editPersonality(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add personality'),
                  ),
                ],
              ),
            ),
          ),
  );
}

class _PersonalityCard extends StatelessWidget {
  const _PersonalityCard({
    required this.personality,
    required this.onEdit,
    required this.onDelete,
    required this.isActive,
    required this.onSelect,
  });

  final Personality personality;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  personality.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (personality.isDefault)
                const Chip(
                  avatar: Icon(Icons.check_circle_outline, size: 18),
                  label: Text('Startup default'),
                  visualDensity: VisualDensity.compact,
                ),
              PopupMenuButton<String>(
                key: ValueKey('personality-actions-${personality.id}'),
                tooltip: 'Personality actions',
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (onDelete != null)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            personality.systemPrompt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('use-${personality.id}'),
              onPressed: isActive ? null : onSelect,
              icon: Icon(
                isActive ? Icons.check_circle : Icons.chat_bubble_outline,
              ),
              label: Text(isActive ? 'Active now' : 'Use now'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PersonalityDraft {
  const _PersonalityDraft({
    required this.name,
    required this.systemPrompt,
    required this.isDefault,
  });

  final String name;
  final String systemPrompt;
  final bool isDefault;
}

class _PersonalityDialog extends StatefulWidget {
  const _PersonalityDialog({this.personality, this.preset});

  final Personality? preset;

  final Personality? personality;

  @override
  State<_PersonalityDialog> createState() => _PersonalityDialogState();
}

class _PersonalityDialogState extends State<_PersonalityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late bool _isDefault;

  @override
  void initState() {
    super.initState();
    final initial = widget.personality ?? widget.preset;
    _nameController = TextEditingController(text: initial?.name);
    _promptController = TextEditingController(text: initial?.systemPrompt);
    _isDefault = widget.personality?.isDefault ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    // Scrolls so the fields stay in view in landscape with the keyboard up.
    scrollable: true,
    title: Text(
      widget.personality == null ? 'Add personality' : 'Edit personality',
    ),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextFormField(
            key: const Key('personalityNameField'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Enter a name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('personalityPromptField'),
            controller: _promptController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'System instructions',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter system instructions'
                : null,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _isDefault,
            title: const Text('Use when app opens'),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: widget.personality?.isDefault == true
                ? null
                : (value) => setState(() => _isDefault = value ?? false),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.of(context).pop(
            _PersonalityDraft(
              name: _nameController.text.trim(),
              systemPrompt: _promptController.text.trim(),
              isDefault: _isDefault,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
