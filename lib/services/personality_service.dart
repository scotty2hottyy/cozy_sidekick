import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/personality.dart';

abstract interface class PersonalityStore {
  Future<void> initialize();
  Future<List<Personality>> loadPersonalities();
  Future<Personality> loadActivePersonality();
  Future<void> savePersonalities(List<Personality> personalities);
  Future<void> setActivePersonality(String id);
}

/// Persists available personalities and the active personality in preferences.
class PersonalityService implements PersonalityStore {
  static const String _personalitiesKey = 'personality.items';
  static const String _activeIdKey = 'personality.active_id';

  static const List<Personality> defaultPersonalities = <Personality>[
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

  Future<void>? _initialization;
  List<Personality> _personalities = <Personality>[];
  String? _activeId;

  @override
  Future<void> initialize() => _initialization ??= _readPreferences();

  Future<void> _readPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_personalitiesKey);
    List<Personality> loaded;
    try {
      final decoded = encoded == null ? null : jsonDecode(encoded);
      loaded = decoded is List
          ? decoded
                .map(
                  (item) => Personality.fromJson(
                    Map<String, Object?>.from(item as Map),
                  ),
                )
                .toList()
          : List<Personality>.of(defaultPersonalities);
      _validate(loaded);
    } on Object {
      loaded = List<Personality>.of(defaultPersonalities);
    }

    final savedActiveId = prefs.getString(_activeIdKey);
    final hasSavedActive = loaded.any((item) => item.id == savedActiveId);
    final flaggedDefault = loaded.where((item) => item.isDefault);
    final selectedId = hasSavedActive
        ? savedActiveId!
        : flaggedDefault.isNotEmpty
        ? flaggedDefault.first.id
        : loaded.first.id;

    _personalities = _withDefault(loaded, selectedId);
    _activeId = selectedId;
    await _writePreferences(prefs);
  }

  @override
  Future<List<Personality>> loadPersonalities() async {
    await initialize();
    return List<Personality>.unmodifiable(_personalities);
  }

  @override
  Future<Personality> loadActivePersonality() async {
    await initialize();
    return _personalities.firstWhere((item) => item.id == _activeId);
  }

  @override
  Future<void> savePersonalities(List<Personality> personalities) async {
    await initialize();
    _validate(personalities);
    final requestedDefault = personalities.where((item) => item.isDefault);
    final selectedId = requestedDefault.isNotEmpty
        ? requestedDefault.first.id
        : personalities.any((item) => item.id == _activeId)
        ? _activeId!
        : personalities.first.id;
    _personalities = _withDefault(personalities, selectedId);
    _activeId = selectedId;
    final prefs = await SharedPreferences.getInstance();
    await _writePreferences(prefs);
  }

  @override
  Future<void> setActivePersonality(String id) async {
    await initialize();
    if (!_personalities.any((item) => item.id == id)) {
      throw ArgumentError.value(id, 'id', 'No personality has this ID');
    }
    _personalities = _withDefault(_personalities, id);
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await _writePreferences(prefs);
  }

  Future<void> _writePreferences(SharedPreferences prefs) async {
    await prefs.setString(
      _personalitiesKey,
      jsonEncode(_personalities.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(_activeIdKey, _activeId!);
  }

  static List<Personality> _withDefault(
    List<Personality> personalities,
    String activeId,
  ) => personalities
      .map(
        (item) => Personality(
          id: item.id,
          name: item.name,
          systemPrompt: item.systemPrompt,
          isDefault: item.id == activeId,
        ),
      )
      .toList();

  static void _validate(List<Personality> personalities) {
    if (personalities.isEmpty) {
      throw ArgumentError('At least one personality is required');
    }
    final ids = <String>{};
    for (final personality in personalities) {
      if (personality.id.trim().isEmpty ||
          personality.name.trim().isEmpty ||
          personality.systemPrompt.trim().isEmpty) {
        throw ArgumentError('Personality fields cannot be empty');
      }
      if (!ids.add(personality.id)) {
        throw ArgumentError('Personality IDs must be unique');
      }
    }
  }
}

/// In-memory implementation used by widget tests and previews.
class InMemoryPersonalityStore implements PersonalityStore {
  InMemoryPersonalityStore({List<Personality>? personalities})
    : _personalities = List<Personality>.of(
        personalities ?? PersonalityService.defaultPersonalities,
      ) {
    final active = _personalities.where((item) => item.isDefault);
    _activeId = active.isNotEmpty ? active.first.id : _personalities.first.id;
    _personalities = PersonalityService._withDefault(_personalities, _activeId);
  }

  List<Personality> _personalities;
  late String _activeId;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Personality>> loadPersonalities() async =>
      List<Personality>.unmodifiable(_personalities);

  @override
  Future<Personality> loadActivePersonality() async =>
      _personalities.firstWhere((item) => item.id == _activeId);

  @override
  Future<void> savePersonalities(List<Personality> personalities) async {
    PersonalityService._validate(personalities);
    final requestedDefault = personalities.where((item) => item.isDefault);
    final selectedId = requestedDefault.isNotEmpty
        ? requestedDefault.first.id
        : personalities.any((item) => item.id == _activeId)
        ? _activeId
        : personalities.first.id;
    _personalities = PersonalityService._withDefault(personalities, selectedId);
    _activeId = selectedId;
  }

  @override
  Future<void> setActivePersonality(String id) async {
    if (!_personalities.any((item) => item.id == id)) {
      throw ArgumentError.value(id, 'id', 'No personality has this ID');
    }
    _activeId = id;
    _personalities = PersonalityService._withDefault(_personalities, id);
  }
}
