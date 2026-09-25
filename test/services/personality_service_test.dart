import 'dart:convert';

import 'package:cozy_sidekick/models/personality.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'preset default survives restart without changing current personality',
    () async {
      final store = PersonalityService();
      final saved = await store.loadPersonalities();
      final planner = Personality.presets.singleWhere(
        (p) => p.id == 'preset-planner',
      );
      await store.savePersonalities([
        for (final p in saved)
          Personality(id: p.id, name: p.name, systemPrompt: p.systemPrompt),
        Personality(
          id: planner.id,
          name: planner.name,
          systemPrompt: planner.systemPrompt,
          isDefault: true,
        ),
      ]);
      expect((await store.loadActivePersonality()).id, 'cozy-sidekick');
      await store.setActivePersonality('preset-curious');
      expect(
        (await PersonalityService().loadActivePersonality()).id,
        planner.id,
      );
    },
  );

  test('preset switching is session-only and changing startup default does not switch now', () async {
    final store = PersonalityService();
    final original = await store.loadPersonalities();
    await store.setActivePersonality('preset-adventure');
    expect((await store.loadActivePersonality()).id, 'preset-adventure');
    expect((await store.loadPersonalities()).single.isDefault, isTrue);
    expect(
      (await PersonalityService().loadActivePersonality()).id,
      'cozy-sidekick',
    );
    const custom = Personality(
      id: 'custom',
      name: 'Custom',
      systemPrompt: 'Be concise.',
      isDefault: true,
    );
    await store.savePersonalities([
      Personality(
        id: original.first.id,
        name: original.first.name,
        systemPrompt: original.first.systemPrompt,
      ),
      custom,
    ]);
    expect((await store.loadActivePersonality()).id, 'preset-adventure');
    expect((await PersonalityService().loadActivePersonality()).id, 'custom');
  });
  test(
    'deleting the active saved personality falls back to startup default',
    () async {
      final store = PersonalityService();
      final original = await store.loadPersonalities();
      const custom = Personality(
        id: 'custom',
        name: 'Custom',
        systemPrompt: 'Be concise.',
      );
      await store.savePersonalities([...original, custom]);
      await store.setActivePersonality(custom.id);
      await store.savePersonalities(original);
      expect((await store.loadActivePersonality()).id, original.first.id);
    },
  );

  test(
    'removes legacy Curious seed and repairs active selection on reload',
    () async {
      const legacy = Personality(
        id: 'curious-guide',
        name: 'Curious Guide',
        systemPrompt: 'You are a curious guide. Help explore ideas with clear explanations and useful questions.',
        isDefault: true,
      );
      SharedPreferences.setMockInitialValues({
        'personality.items': jsonEncode(
          [
            ...PersonalityService.defaultPersonalities,
            legacy,
          ].map((p) => p.toJson()).toList(),
        ),
        'personality.active_id': 'curious-guide',
      });
      final store = PersonalityService();
      expect((await store.loadPersonalities()).map((p) => p.id), [
        'cozy-sidekick',
      ]);
      expect((await store.loadActivePersonality()).id, 'cozy-sidekick');
      expect((await PersonalityService().loadPersonalities()), hasLength(1));
    },
  );
  test('preserves a customized Curious personality', () async {
    const custom = Personality(
      id: 'curious-guide',
      name: 'Curious Guide',
      systemPrompt: 'My custom instructions.',
      isDefault: true,
    );
    SharedPreferences.setMockInitialValues({
      'personality.items': jsonEncode([custom.toJson()]),
      'personality.active_id': custom.id,
    });
    expect(
      (await PersonalityService().loadActivePersonality()).systemPrompt,
      custom.systemPrompt,
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('seeds the built-in personalities and persists the active ID', () async {
    final service = PersonalityService();
    await service.initialize();

    expect((await service.loadPersonalities()).length, 1);
    expect((await service.loadActivePersonality()).id, 'cozy-sidekick');
  });

  test(
    'persists custom personalities but starts new sessions with the default',
    () async {
      final firstSession = PersonalityService();
      final personalities = await firstSession.loadPersonalities();
      const custom = Personality(
        id: 'focused-helper',
        name: 'Focused Helper',
        systemPrompt: 'Give concise, practical answers.',
      );
      await firstSession.savePersonalities(<Personality>[
        ...personalities,
        custom,
      ]);
      await firstSession.setActivePersonality(custom.id);

      final nextSession = PersonalityService();
      final restored = await nextSession.loadPersonalities();
      final restoredCustom = restored.singleWhere(
        (item) => item.id == custom.id,
      );
      final active = await nextSession.loadActivePersonality();

      expect(restoredCustom.name, custom.name);
      expect(restoredCustom.systemPrompt, custom.systemPrompt);
      expect(restoredCustom.isDefault, isFalse);
      expect(active.id, 'cozy-sidekick');
      expect((await firstSession.loadActivePersonality()).id, custom.id);
    },
  );

  test('rejects duplicate IDs and an unknown active personality', () async {
    final service = PersonalityService();
    final defaultPersonality = (await service.loadPersonalities()).first;
    expect(
      service.savePersonalities(<Personality>[
        defaultPersonality,
        defaultPersonality,
      ]),
      throwsArgumentError,
    );
    expect(service.setActivePersonality('missing'), throwsArgumentError);
  });
}
