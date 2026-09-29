import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../services/model_list_service.dart';

/// Every chat model a provider offers, with a search field. It closes with
/// the ID of the model the user taps.
class ModelListScreen extends StatefulWidget {
  const ModelListScreen({
    super.key,
    required this.provider,
    required this.modelLister,
    required this.selected,
  });
  final AiProviderType provider;
  final ModelLister modelLister;

  /// The model in use, which is checked.
  final String selected;

  @override
  State<ModelListScreen> createState() => _ModelListScreenState();
}

class _ModelListScreenState extends State<ModelListScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<String>? _models;

  /// Why only the suggested models are listed, when the full list couldn't
  /// be loaded.
  String? _fallbackReason;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<String> models;
    String? fallbackReason;
    try {
      models = await widget.modelLister.listModels(widget.provider);
    } on AiProviderException catch (e) {
      debugPrint('Model list failed: $e'); // never includes keys
      models = widget.provider.suggestedModels;
      fallbackReason = e is MissingApiKeyException
          ? 'Add a key in API Credentials to see every model. Until then, '
                'here are the suggested ones.'
          : "Couldn't load every model, so here are the suggested ones.";
    }
    if (mounted) {
      setState(() {
        _models = models;
        _fallbackReason = fallbackReason;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models = _models;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.provider.displayName} Models')),
      body: models == null
          ? const Center(child: CircularProgressIndicator())
          : _list(models),
    );
  }

  Widget _list(List<String> models) {
    final query = _searchController.text.trim().toLowerCase();
    final shown = models
        .where((model) => model.toLowerCase().contains(query))
        .toList();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            key: const Key('modelSearch'),
            controller: _searchController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search ${models.length} models',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_fallbackReason != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_fallbackReason!),
          ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No models match.'))
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final model = shown[index];
                    final isSelected = model == widget.selected;
                    return ListTile(
                      title: Text(model),
                      subtitle: model == widget.provider.defaultModel
                          ? const Text('Default')
                          : null,
                      selected: isSelected,
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.of(context).pop(model),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
