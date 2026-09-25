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

/// Persists personalities and their startup default; active selection is session-only.
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

    // Remove the old seeded duplicate, retaining any user-customized version.
    loaded = loaded
        .where(
          (item) =>
              !(item.id == 'curious-guide' &&
                  item.name == 'Curious Guide' &&
                  item.systemPrompt ==
                      'You are a curious guide. Help explore ideas with clear explanations '
                          'and useful questions.'),
        )
        .toList();
    if (loaded.isEmpty) loaded = List<Personality>.of(defaultPersonalities);

    final savedActiveId = prefs.getString(_activeIdKey);
    final flaggedDefault = loaded.where((item) => item.isDefault);
    final selectedId = flaggedDefault.isNotEmpty
        ? flaggedDefault.first.id
        : loaded.any((item) => item.id == savedActiveId)
        ? savedActiveId!
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
    return _resolve(_personalities, _activeId!);
  }

  @override
  Future<void> savePersonalities(List<Personality> personalities) async {
    await initialize();
    _validate(personalities);
    final requestedDefault = personalities.where((item) => item.isDefault);
    final selectedId = requestedDefault.isNotEmpty
        ? requestedDefault.first.id
        : personalities.first.id;
    _personalities = _withDefault(personalities, selectedId);
    if (!_contains(_personalities, _activeId!)) _activeId = selectedId;
    final prefs = await SharedPreferences.getInstance();
    await _writePreferences(prefs);
  }

  @override
  Future<void> setActivePersonality(String id) async {
    await initialize();
    _resolve(_personalities, id);
    _activeId = id;
  }

  Future<void> _writePreferences(SharedPreferences prefs) async {
    await prefs.setString(
      _personalitiesKey,
      jsonEncode(_personalities.map((item) => item.toJson()).toList()),
    );
    await prefs.remove(_activeIdKey);
  }

  static bool _contains(List<Personality> saved, String id) =>
      [...saved, ...Personality.presets].any((item) => item.id == id);

  static Personality _resolve(List<Personality> saved, String id) =>
      [...saved, ...Personality.presets].firstWhere(
        (item) => item.id == id,
        orElse: () =>
            throw ArgumentError.value(id, 'id', 'No personality has this ID'),
      );

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
      PersonalityService._resolve(_personalities, _activeId);

  @override
  Future<void> savePersonalities(List<Personality> personalities) async {
    PersonalityService._validate(personalities);
    final requestedDefault = personalities.where((item) => item.isDefault);
    final selectedId = requestedDefault.isNotEmpty
        ? requestedDefault.first.id
        : personalities.first.id;
    _personalities = PersonalityService._withDefault(personalities, selectedId);
    if (!PersonalityService._contains(_personalities, _activeId)) {
      _activeId = selectedId;
    }
  }

  @override
  Future<void> setActivePersonality(String id) async {
    PersonalityService._resolve(_personalities, id);
    _activeId = id;
  }
}
