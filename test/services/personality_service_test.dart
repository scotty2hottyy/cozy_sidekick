import 'dart:convert';

import 'package:cozy_sidekick/models/personality.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
    'persists custom personalities and active selection across instances',
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
      expect(restoredCustom.isDefault, isTrue);
      expect(active.id, custom.id);
      expect(active.systemPrompt, custom.systemPrompt);
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
