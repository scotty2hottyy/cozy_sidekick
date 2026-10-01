import 'package:flutter/material.dart';

import '../ai/ai_provider.dart';
import '../ai/error_messages.dart';
import '../models/openai_free_tier.dart';
import '../models/quota_route.dart';
import '../services/api_key_store.dart';
import '../services/free_quota_service.dart';
import '../services/model_list_service.dart';
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
    FreeQuotaReader? quotaReader,
  }) : keyStore = keyStore,
       usageTracker = usageTracker ?? UsageTracker(),
       quotaReader = quotaReader ?? FreeQuotaService(keyStore: keyStore);

  final AppSettingsStore settingsStore;
  final ModelLister modelLister;
  final ApiKeyStore keyStore;
  final UsageTracker usageTracker;
  final FreeQuotaReader quotaReader;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  AiProviderType? _selected;
  bool _showReasoning = false;
  bool _autoRoute = false;
  List<QuotaRoute> _routes = <QuotaRoute>[];
  Map<String, String> _routeStatuses = <String, String>{};

  /// Counts the status refreshes, so an older one can't replace a newer one.
  int _statusRefreshes = 0;

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

  /// Reads the free quotas and shows how much of each route is left. The
  /// quotas are only read while auto-routing is on.
  Future<void> _refreshRouteStatuses() async {
    if (!_autoRoute) return;
    final refresh = ++_statusRefreshes;
    final routes = _routes;
    final hasKey = <AiProviderType, bool>{};
    for (final provider in <AiProviderType>{
      for (final route in routes) route.provider,
    }) {
      final key = await widget.keyStore.read(provider);
      hasKey[provider] = key != null && key.trim().isNotEmpty;
      if (!hasKey[provider]!) continue;
      try {
        final quota = await widget.quotaReader.read(provider);
        // A newer refresh reads its own quota for the routes as they are now.
        if (refresh != _statusRefreshes) return;
        if (quota == null) continue;
        for (final route in routes) {
          if (route.provider == provider) {
            await widget.usageTracker.report(route, quota);
          }
        }
      } on AiProviderException catch (e) {
        // The row says the quota is unknown instead.
        debugPrint('Free quota check failed: $e'); // never includes keys
      }
    }
    final statuses = <String, String>{};
    final now = DateTime.now().toUtc();
    for (final route in routes) {
      statuses[route.id] = hasKey[route.provider]!
          ? routeStatus(route, await widget.usageTracker.usageFor(route), now)
          : 'No key saved';
    }
    if (mounted && refresh == _statusRefreshes) {
      setState(() => _routeStatuses = statuses);
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

  Future<void> _setAutoRoute(bool value) async {
    setState(() => _autoRoute = value);
    await widget.settingsStore.saveAutoRouteEnabled(value);
    await _refreshRouteStatuses();
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
    final key = await widget.keyStore.read(route.provider);
    if (!mounted) return;
    final result = await showDialog<QuotaRoute>(
      context: context,
      builder: (context) => _QuotaRouteEditDialog(
        route: route,
        hasKey: key != null && key.trim().isNotEmpty,
        modelLister: widget.modelLister,
        usageTracker: widget.usageTracker,
      ),
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

/// The line under a route in AI Settings: how much of its free quota or the
/// user's limit is left today.
String routeStatus(QuotaRoute route, RouteUsage usage, DateTime now) {
  final nowUtc = now.toUtc();
  if (route.userLimit == 0) return 'Skipped · daily limit is 0';
  final reset = usage.resetFor(route, nowUtc);
  if (reset != null) {
    if (!usage.isBusy(route, nowUtc)) {
      return 'Used up · resets ${formatUtcTime(reset)}';
    }
    // A 429 without a time from the provider waits only a second.
    return reset.difference(nowUtc) < const Duration(minutes: 1)
        ? 'Busy · try again in a moment'
        : 'Busy · try again after ${formatUtcTime(reset)}';
  }
  final limit = usage.limitFor(route);
  if (limit == null) {
    return '${formatAmount(usage.usedFor(route), route.unit)} today · '
        'free quota unknown';
  }
  final left = formatAmount(usage.leftFor(route)!, route.unit, withUnit: false);
  return limit == usage.freeQuotaFor(route)
      ? '$left of ${formatAmount(limit, route.unit, free: true)} left today'
      : '$left of your ${formatAmount(limit, route.unit)} left today';
}

/// [amount] of [unit], like "1,000 requests" or "2.25M tokens". Tokens are
/// shortened to K and M. [free] puts "free" before the unit.
String formatAmount(
  int amount,
  QuotaUnit unit, {
  bool withUnit = true,
  bool free = false,
}) {
  final number = unit == QuotaUnit.tokens
      ? _shortNumber(amount)
      : _groupedNumber(amount);
  if (!withUnit) return number;
  final name = switch (unit) {
    QuotaUnit.requests => amount == 1 ? 'request' : 'requests',
    QuotaUnit.tokens => amount == 1 ? 'token' : 'tokens',
  };
  return free ? '$number free $name' : '$number $name';
}

/// [dateTime] in UTC, like "12:00 AM UTC".
String formatUtcTime(DateTime dateTime) {
  final time = dateTime.toUtc();
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'} UTC';
}

/// 1234567 as "1,234,567".
String _groupedNumber(int number) {
  final digits = number.abs().toString();
  final grouped = StringBuffer(number < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return '$grouped';
}

/// 2250000 as "2.25M" and 250000 as "250K", with up to three digits.
String _shortNumber(int number) {
  if (number.abs() < 1000) return '$number';
  var (value, suffix) = number.abs() < 1000000
      ? (number / 1000, 'K')
      : (number / 1000000, 'M');
  // 999,999 would round to "1000K", so it's "1M".
  if (suffix == 'K' && value.abs().round() >= 1000) {
    (value, suffix) = (number / 1000000, 'M');
  }
  final decimals = value.abs() >= 100
      ? 0
      : value.abs() >= 10
      ? 1
      : 2;
  var text = value.toStringAsFixed(decimals);
  // Only zeros after the decimal point go, so 250 stays 250.
  if (text.contains('.')) text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return '$text$suffix';
}

/// Edits a route's model, picked from the provider's free models, and its
/// daily limit, on a slider from 0 to the free quota.
class _QuotaRouteEditDialog extends StatefulWidget {
  const _QuotaRouteEditDialog({
    required this.route,
    required this.hasKey,
    required this.modelLister,
    required this.usageTracker,
  });

  final QuotaRoute route;
  final ModelLister modelLister;
  final UsageTracker usageTracker;

  /// Whether a key is saved for the route's provider, which reading its free
  /// quota needs.
  final bool hasKey;

  @override
  State<_QuotaRouteEditDialog> createState() => _QuotaRouteEditDialogState();
}

class _QuotaRouteEditDialogState extends State<_QuotaRouteEditDialog> {
  /// The free models, or null while they load.
  List<String>? _models;

  /// Why the models couldn't be loaded.
  String? _modelsError;

  /// The picked model, or null until one of [_models] is picked.
  String? _model;

  /// The user's limit, or null for the whole free quota.
  int? _limit;

  late bool _highUsageTier;

  /// The free quota for [_model], which is the slider's maximum. Null when
  /// it isn't known.
  int? _quota;

  /// Whether [_quota] is still loading.
  bool _quotaLoading = true;

  /// Counts the quota loads, so an older one can't replace a newer one.
  int _quotaLoads = 0;

  QuotaRoute get _route => widget.route;

  @override
  void initState() {
    super.initState();
    _limit = _route.userLimit;
    _highUsageTier = _route.highUsageTier;
    _loadModels();
    _loadQuota(_route.model);
  }

  Future<void> _loadModels() async {
    List<String> models;
    String? error;
    String? model;
    try {
      models = await widget.modelLister.listFreeModels(_route.provider);
      if (models.contains(_route.model)) model = _route.model;
    } on AiProviderException catch (e) {
      debugPrint('Free model list failed: $e'); // never includes keys
      // The route keeps its model until the list loads.
      models = <String>[_route.model];
      model = _route.model;
      error = e is MissingApiKeyException
          ? 'Add your ${_route.provider.displayName} key in API Credentials '
                'to see its free models.'
          : "Couldn't load the free models. ${friendlyMessage(e)}";
    }
    if (!mounted) return;
    setState(() {
      _models = models;
      _modelsError = error;
      _model = model;
    });
  }

  /// Loads [model]'s free quota. OpenAI's is a fixed allowance, and the
  /// others are the last ones their providers reported.
  Future<void> _loadQuota(String model) async {
    final load = ++_quotaLoads;
    if (!_quotaLoading) setState(() => _quotaLoading = true);
    final quota = await widget.usageTracker.knownFreeQuota(_draft(model));
    if (!mounted || load != _quotaLoads) return;
    setState(() {
      _quota = quota;
      _quotaLoading = false;
      // A limit at or above the quota is the whole quota.
      if (quota != null && (_limit ?? 0) >= quota) _limit = null;
    });
  }

  QuotaRoute _draft(String model) => _route.copyWith(
    model: model,
    userLimit: _limit,
    clearUserLimit: _limit == null,
    highUsageTier: _highUsageTier,
  );

  void _pickModel(String? model) {
    if (model == null || model == _model) return;
    final group = OpenAiFreeTier.of(model);
    setState(() {
      // Another OpenAI group has another allowance, so the limit starts
      // again at its suggested one.
      if (group != null && group != OpenAiFreeTier.of(_model ?? '')) {
        _limit = group.suggestedLimit(highUsageTier: _highUsageTier);
      } else if (_route.quotaIsPerModel) {
        // Each Groq model has its own quota, so another model's limit
        // doesn't carry over.
        _limit = null;
      }
      _model = model;
    });
    _loadQuota(model);
  }

  void _setHighUsageTier(bool value) {
    final group = OpenAiFreeTier.of(_model ?? _route.model);
    setState(() {
      _highUsageTier = value;
      if (group != null) {
        _limit = group.suggestedLimit(highUsageTier: value);
      }
    });
    _loadQuota(_model ?? _route.model);
  }

  void _save() => Navigator.of(context).pop(_draft(_model!));

  @override
  Widget build(BuildContext context) {
    final models = _models;
    final isOpenAi = _route.provider == AiProviderType.openAi;
    return AlertDialog(
      title: Text('Edit ${_route.provider.displayName} route'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (models == null)
              const Center(child: CircularProgressIndicator())
            else
              _modelDropdown(models),
            if (isOpenAi) ...<Widget>[
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('highUsageTierSwitch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Usage tier 3 or higher'),
                subtitle: const Text('Four times the free tokens'),
                value: _highUsageTier,
                onChanged: _setHighUsageTier,
              ),
            ],
            const SizedBox(height: 16),
            ..._limitSlider(),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('saveRouteButton'),
          onPressed: _model == null ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _modelDropdown(List<String> models) => DropdownButtonFormField<String>(
    key: const Key('routeModelDropdown'),
    initialValue: _model,
    isExpanded: true,
    menuMaxHeight: 320,
    decoration: InputDecoration(
      labelText: 'Model',
      border: const OutlineInputBorder(),
      errorText: _modelsError,
      errorMaxLines: 3,
      helperText: _model == null
          ? "${_route.model} isn't one of the free models. Pick one."
          : _allowance(_model!),
      helperMaxLines: 3,
    ),
    hint: const Text('Pick a model'),
    // Menu items can have a second line, for OpenAI's allowances.
    itemHeight: null,
    // The closed menu shows only the model, with its allowance below it.
    // Screen readers still announce it as a button, as they do the items.
    selectedItemBuilder: (context) => <Widget>[
      for (final model in models)
        Semantics(
          button: true,
          child: Text(model, overflow: TextOverflow.ellipsis),
        ),
    ],
    items: <DropdownMenuItem<String>>[
      for (final model in models)
        DropdownMenuItem<String>(value: model, child: _modelLabel(model)),
    ],
    onChanged: _modelsError == null ? _pickModel : null,
  );

  /// [model]'s ID, and under it OpenAI's free tokens a day for its group.
  Widget _modelLabel(String model) {
    final allowance = _allowance(model);
    if (allowance == null) return Text(model, overflow: TextOverflow.ellipsis);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(model, overflow: TextOverflow.ellipsis),
        Text(
          allowance,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).hintColor),
        ),
      ],
    );
  }

  /// The free tokens a day for an OpenAI [model]'s group, like "250K tokens
  /// a day". Null for the other providers.
  String? _allowance(String model) {
    final group = OpenAiFreeTier.of(model);
    if (_route.provider != AiProviderType.openAi || group == null) return null;
    final tokens = group.tokensPerDay(highUsageTier: _highUsageTier);
    return '${formatAmount(tokens, QuotaUnit.tokens)} a day';
  }

  List<Widget> _limitSlider() {
    final heading = Text(
      'Daily limit',
      style: Theme.of(context).textTheme.titleSmall,
    );
    if (_quotaLoading) return <Widget>[heading];
    final quota = _quota;
    if (quota == null || quota <= 0) {
      return <Widget>[
        heading,
        const SizedBox(height: 8),
        Text(
          !widget.hasKey
              ? 'Add your ${_route.provider.displayName} key in API Credentials '
                    'to read its free quota and set a limit.'
              : _route.provider == AiProviderType.groq
              ? 'Groq reports its free quota with each reply. Once this '
                    'model has answered, you can set a limit here.'
              : "The free quota isn't known yet, so a limit can't be set.",
          key: const Key('quotaUnknownText'),
        ),
      ];
    }
    final limit = _limit;
    String describe(int? limit) => limit == null
        ? 'Use the whole free quota'
        : '${formatAmount(limit, _route.unit)} a day';
    return <Widget>[
      // Screen readers announce the heading with the slider.
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            heading,
            Slider(
              key: const Key('dailyLimitSlider'),
              max: quota.toDouble(),
              // One step per request up to 100, and 100 steps above that.
              divisions: quota <= 100 ? quota : 100,
              value: (limit ?? quota).clamp(0, quota).toDouble(),
              label: limit == null
                  ? 'All'
                  : formatAmount(limit, _route.unit, withUnit: false),
              semanticFormatterCallback: (value) =>
                  describe(value.round() >= quota ? null : value.round()),
              onChanged: (value) {
                final picked = value.round();
                setState(() => _limit = picked >= quota ? null : picked);
              },
            ),
          ],
        ),
      ),
      Text(describe(limit), key: const Key('dailyLimitText')),
      const SizedBox(height: 4),
      Text(
        'The free quota is ${formatAmount(quota, _route.unit)} a day.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
}
