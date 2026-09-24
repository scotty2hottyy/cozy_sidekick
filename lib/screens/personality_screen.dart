import 'package:flutter/material.dart';

import '../models/personality.dart';

/// UI shell for creating, editing, and choosing AI personalities.
///
/// Changes are held in memory for this screen. Persistent storage is a later
/// step in the personality feature.
class PersonalityScreen extends StatefulWidget {
  const PersonalityScreen({super.key});

  @override
  State<PersonalityScreen> createState() => _PersonalityScreenState();
}

class _PersonalityScreenState extends State<PersonalityScreen> {
  final List<Personality> _personalities = <Personality>[
    Personality(
      id: 'cozy-sidekick',
      name: 'Cozy Sidekick',
      systemPrompt:
          'You are a helpful, warm conversational assistant. Be thoughtful, '
          'clear, and supportive.',
      isDefault: true,
    ),
    Personality(
      id: 'curious-guide',
      name: 'Curious Guide',
      systemPrompt:
          'You are a curious guide. Help explore ideas with clear explanations '
          'and useful questions.',
    ),
  ];

  Future<void> _editPersonality([Personality? personality]) async {
    final result = await showDialog<_PersonalityDraft>(
      context: context,
      builder: (context) => _PersonalityDialog(personality: personality),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (result.isDefault) {
        for (var i = 0; i < _personalities.length; i++) {
          final existing = _personalities[i];
          _personalities[i] = Personality(
            id: existing.id,
            name: existing.name,
            systemPrompt: existing.systemPrompt,
          );
        }
      }

      final updated = Personality(
        id: personality?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: result.name,
        systemPrompt: result.systemPrompt,
        isDefault: result.isDefault,
      );
      if (personality == null) {
        _personalities.add(updated);
      } else {
        final index = _personalities.indexWhere(
          (item) => item.id == personality.id,
        );
        if (index >= 0) _personalities[index] = updated;
      }
    });
  }

  void _deletePersonality(Personality personality) {
    setState(() {
      _personalities.removeWhere((item) => item.id == personality.id);
      if (_personalities.isNotEmpty &&
          !_personalities.any((item) => item.isDefault)) {
        final first = _personalities.first;
        _personalities[0] = Personality(
          id: first.id,
          name: first.name,
          systemPrompt: first.systemPrompt,
          isDefault: true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Personalities')),
    body: Center(
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
              'Each personality has its own system instructions.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            for (final personality in _personalities)
              _PersonalityCard(
                personality: personality,
                onEdit: () => _editPersonality(personality),
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
  });

  final Personality personality;
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
                  label: Text('Default'),
                  visualDensity: VisualDensity.compact,
                ),
              PopupMenuButton<String>(
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
  const _PersonalityDialog({this.personality});

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
    _nameController = TextEditingController(text: widget.personality?.name);
    _promptController = TextEditingController(
      text: widget.personality?.systemPrompt,
    );
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
    title: Text(
      widget.personality == null ? 'Add personality' : 'Edit personality',
    ),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
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
              title: const Text('Use as default'),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => _isDefault = value ?? false),
            ),
          ],
        ),
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
