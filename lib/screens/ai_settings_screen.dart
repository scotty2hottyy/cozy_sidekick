import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../models/quota_route.dart';
import '../services/api_key_store.dart';
import '../services/model_list_service.dart';
import '../services/openrouter_quota_service.dart';
import '../services/settings_service.dart';
import '../services/usage_tracker.dart';
import 'model_list_screen.dart';

class AiSettingsScreen extends StatefulWidget {
  AiSettingsScreen({
    super.key,
    required this.settingsStore,
    required this.modelLister,
    required ApiKeyStore keyStore,
    UsageTracker? usageTracker,
    OpenRouterQuotaReader? quotaReader,
  }) : keyStore = keyStore,
       usageTracker = usageTracker ?? UsageTracker(),
       quotaReader = quotaReader ?? OpenRouterQuotaService(keyStore: keyStore);

  final AppSettingsStore settingsStore;
  final ModelLister modelLister;
  final ApiKeyStore keyStore;
  final UsageTracker usageTracker;
  final OpenRouterQuotaReader quotaReader;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  AiProviderType? _selected;
  bool _showReasoning = false;
  bool _autoRoute = false;
  List<QuotaRoute> _routes = <QuotaRoute>[];
  Map<String, String> _routeStatuses = <String, String>{};

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
    final autoRoute = await widget.settingsStore.loadAutoRouteEnabled();
    final routes = await widget.settingsStore.loadQuotaRoutes();
    if (mounted) {
      setState(() {
        _selected = selected;
        _showReasoning = showReasoning;
        _model = model;
        _autoRoute = autoRoute;
        _routes = routes;
      });
      await _refreshRouteStatuses();
    }
  }

  Future<void> _refreshRouteStatuses() async {
    int? remoteRemaining;
    try {
      remoteRemaining = await widget.quotaReader.freeRequestsRemaining();
    } on AiProviderException {
      remoteRemaining = null;
    }
    final statuses = <String, String>{};
    final now = DateTime.now().toUtc();
    final midnight = DateTime.utc(now.year, now.month, now.day + 1);
    for (final route in _routes) {
      final key = await widget.keyStore.read(route.provider);
      if (key == null || key.trim().isEmpty) {
        statuses[route.id] = 'No key saved';
        continue;
      }
      if (route.provider == AiProviderType.openRouter &&
          remoteRemaining != null) {
        statuses[route.id] = '$remoteRemaining free requests remaining today';
        continue;
      }
      final usage = await widget.usageTracker.usageFor(route);
      if (usage.blockedUntil?.isAfter(now) ?? false) {
        statuses[route.id] =
            'Used up · resets ${_formatTime(usage.blockedUntil!)}';
      } else if (route.dailyLimit != null &&
          usage.usedFor(route) >= route.dailyLimit!) {
        statuses[route.id] = 'Used up · resets ${_formatTime(midnight)}';
      } else if (route.dailyLimit == null) {
        statuses[route.id] = '${usage.requests} requests today';
      } else {
        statuses[route.id] =
            '${_formatCount(usage.usedFor(route))} / '
            '${_formatCount(route.dailyLimit!)} '
            '${route.unit.name} today';
      }
    }
    if (mounted) setState(() => _routeStatuses = statuses);
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }

  static String _formatTime(DateTime dateTime) {
    final time = dateTime.toUtc();
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'} UTC';
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

  Future<void> _setAutoRoute(bool value) async {
    setState(() => _autoRoute = value);
    await widget.settingsStore.saveAutoRouteEnabled(value);
  }

  Future<void> _reorderRoutes(int oldIndex, int newIndex) async {
    final routes = List<QuotaRoute>.of(_routes);
    final moved = routes.removeAt(oldIndex);
    routes.insert(newIndex, moved);
    setState(() => _routes = routes);
    await widget.settingsStore.saveQuotaRoutes(routes);
  }

  Future<void> _toggleRoute(QuotaRoute route, bool enabled) async {
    if (enabled && route.provider == AiProviderType.openAi) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OpenAI free tokens can be billed'),
          content: const SingleChildScrollView(
            child: Text(
              'Free tokens only apply when your organization shares prompts '
              'and replies with OpenAI and its dashboard shows the offer. '
              'OpenAI does not report the remaining allowance, and usage '
              'past it is billed without an error. This app stops at its own '
              'token count, but cannot see use by other apps on the account. '
              'Keep a low monthly budget in the OpenAI dashboard as a backstop.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Turn on'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _saveRoute(route.copyWith(enabled: enabled));
  }

  Future<void> _editRoute(QuotaRoute route) async {
    final result = await showDialog<QuotaRoute>(
      context: context,
      builder: (context) => _QuotaRouteEditDialog(route: route),
    );
    if (result != null && mounted) await _saveRoute(result);
  }

  Future<void> _saveRoute(QuotaRoute updated) async {
    final routes = <QuotaRoute>[
      for (final route in _routes) route.id == updated.id ? updated : route,
    ];
    setState(() => _routes = routes);
    await widget.settingsStore.saveQuotaRoutes(routes);
    await _refreshRouteStatuses();
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
                onChanged: _autoRoute ? null : _select,
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                key: const Key('autoRouteSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-route to free quota'),
                subtitle: const Text(
                  'Use free allowances first, and switch when one runs out.',
                ),
                value: _autoRoute,
                onChanged: _setAutoRoute,
              ),
              if (_autoRoute) ...<Widget>[
                const SizedBox(height: 8),
                Text('Routes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorderRoutes,
                  children: <Widget>[
                    for (var index = 0; index < _routes.length; index++)
                      ListTile(
                        key: ValueKey(_routes[index].id),
                        onTap: () => _editRoute(_routes[index]),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(_routes[index].provider.displayName),
                        subtitle: Text(
                          '${_routes[index].model}\n'
                          '${_routeStatuses[_routes[index].id] ?? 'Loading usage…'}',
                        ),
                        isThreeLine: true,
                        trailing: Switch(
                          key: ValueKey('quota-route-${_routes[index].id}'),
                          value: _routes[index].enabled,
                          onChanged: (value) =>
                              _toggleRoute(_routes[index], value),
                        ),
                      ),
                  ],
                ),
              ] else ...<Widget>[..._modelPicker(_selected!)],
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

class _QuotaRouteEditDialog extends StatefulWidget {
  const _QuotaRouteEditDialog({required this.route});

  final QuotaRoute route;

  @override
  State<_QuotaRouteEditDialog> createState() => _QuotaRouteEditDialogState();
}

class _QuotaRouteEditDialogState extends State<_QuotaRouteEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _modelController;
  late final TextEditingController _limitController;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(text: widget.route.model);
    _limitController = TextEditingController(
      text: widget.route.dailyLimit?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _modelController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.route.provider.displayName} route'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextFormField(
            controller: _modelController,
            decoration: const InputDecoration(labelText: 'Model ID'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a model ID'
                : null,
          ),
          TextFormField(
            controller: _limitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daily limit',
              hintText: 'Leave blank if unknown',
            ),
            validator: (value) {
              final limit = int.tryParse(value?.trim() ?? '');
              return value != null &&
                      value.trim().isNotEmpty &&
                      (limit == null || limit <= 0)
                  ? 'Enter a positive whole number'
                  : null;
            },
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
          final limit = int.tryParse(_limitController.text.trim());
          Navigator.of(context).pop(
            widget.route.copyWith(
              model: _modelController.text.trim(),
              dailyLimit: limit,
              clearDailyLimit: limit == null,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
