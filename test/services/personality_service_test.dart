import 'package:cozy_sidekick/models/personality.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('seeds the built-in personalities and persists the active ID', () async {
    final service = PersonalityService();
    await service.initialize();

    expect((await service.loadPersonalities()).length, 2);
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
