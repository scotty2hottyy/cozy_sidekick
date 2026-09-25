import 'package:cozy_sidekick/models/personality.dart';
import 'package:cozy_sidekick/screens/personality_screen.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Cozy remains a large card and Curious appears only as a preset',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalityScreen(personalityStore: InMemoryPersonalityStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cozy Sidekick'), findsOneWidget);
      expect(find.byKey(const ValueKey('preset-cozy')), findsNothing);
      expect(find.text('Curious Guide'), findsNothing);
      expect(find.byKey(const ValueKey('preset-curious')), findsOneWidget);
    },
  );

  for (final preset in Personality.presets) {
    testWidgets(
      '${preset.name} fills editable fields without saving on selection or cancel',
      (tester) async {
        final store = InMemoryPersonalityStore();
        final original = await store.loadPersonalities();
        final active = await store.loadActivePersonality();
        await tester.pumpWidget(
          MaterialApp(home: PersonalityScreen(personalityStore: store)),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(ValueKey(preset.id)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(preset.id)));
        await tester.pumpAndSettle();
        final name = find.byKey(const Key('personalityNameField'));
        final prompt = find.byKey(const Key('personalityPromptField'));
        expect(
          tester.widget<TextFormField>(name).controller!.text,
          preset.name,
        );
        expect(
          tester.widget<TextFormField>(prompt).controller!.text,
          preset.systemPrompt,
        );
        await tester.enterText(name, 'My version');
        await tester.enterText(prompt, 'My own instructions');
        expect(await store.loadPersonalities(), original);
        expect((await store.loadActivePersonality()).id, active.id);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(await store.loadPersonalities(), original);
      },
    );
  }
  testWidgets(
    'Save creates edited preset with fresh ID without changing active personality',
    (tester) async {
      final store = InMemoryPersonalityStore();
      final original = await store.loadPersonalities();
      final active = await store.loadActivePersonality();
      await tester.pumpWidget(
        MaterialApp(home: PersonalityScreen(personalityStore: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-curious')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('personalityNameField')),
        'My Curious',
      );
      await tester.enterText(
        find.byKey(const Key('personalityPromptField')),
        'Be gentle and concise.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = await store.loadPersonalities();
      expect(saved, hasLength(original.length + 1));
      expect(saved.last.name, 'My Curious');
      expect(saved.last.systemPrompt, 'Be gentle and concise.');
      expect(saved.last.id, isNot('preset-curious'));
      expect((await store.loadActivePersonality()).id, active.id);
      expect(Personality.presets.first.name, 'Curious');
    },
  );
}
