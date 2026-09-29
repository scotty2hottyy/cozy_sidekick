import 'package:cozy_sidekick/models/personality.dart';
import 'package:cozy_sidekick/screens/personality_screen.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'startup dropdown changes defaults independently of current selection',
    (tester) async {
      final store = InMemoryPersonalityStore();
      await tester.pumpWidget(
        MaterialApp(home: PersonalityScreen(personalityStore: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Planner').last);
      await tester.pumpAndSettle();
      expect(
        (await store.loadPersonalities()).singleWhere((p) => p.isDefault).id,
        'preset-planner',
      );
      expect((await store.loadActivePersonality()).id, 'cozy-sidekick');
      await tester.tap(find.byKey(const ValueKey('preset-curious')));
      await tester.pumpAndSettle();
      expect((await store.loadActivePersonality()).id, 'preset-curious');
      expect(
        (await store.loadPersonalities()).singleWhere((p) => p.isDefault).id,
        'preset-planner',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cozy Sidekick').last);
      await tester.pumpAndSettle();
      expect((await store.loadActivePersonality()).id, 'preset-curious');
      expect(
        (await store.loadPersonalities()).singleWhere((p) => p.isDefault).id,
        'cozy-sidekick',
      );
    },
  );

  testWidgets('Use now switches back to saved Cozy without changing default', (
    tester,
  ) async {
    final store = InMemoryPersonalityStore();
    await tester.pumpWidget(
      MaterialApp(home: PersonalityScreen(personalityStore: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-curious')));
    await tester.pumpAndSettle();
    final useCozy = find.byKey(const ValueKey('use-cozy-sidekick'));
    await tester.ensureVisible(useCozy);
    await tester.pumpAndSettle();
    await tester.tap(useCozy);
    await tester.pumpAndSettle();
    expect((await store.loadActivePersonality()).id, 'cozy-sidekick');
    expect((await store.loadPersonalities()).single.isDefault, isTrue);
  });

  testWidgets('deleting a personality requires confirmation', (tester) async {
    const captain = Personality(
      id: 'comic-companion',
      name: 'Comic Companion',
      systemPrompt: 'Keep the jokes coming.',
    );
    final store = InMemoryPersonalityStore(
      personalities: [...PersonalityService.defaultPersonalities, captain],
    );
    await tester.pumpWidget(
      MaterialApp(home: PersonalityScreen(personalityStore: store)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text(captain.name), findsOneWidget);
    final actions = find.byKey(
      const ValueKey('personality-actions-comic-companion'),
    );
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Comic Companion?'), findsOneWidget);
    expect(
      (await store.loadPersonalities()).any((item) => item.id == captain.id),
      isTrue,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      (await store.loadPersonalities()).any((item) => item.id == captain.id),
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey('personality-actions-comic-companion')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(
      (await store.loadPersonalities()).any((item) => item.id == captain.id),
      isFalse,
    );
  });

  testWidgets(
    'Cozy remains a large card and Curious appears only as a preset',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalityScreen(personalityStore: InMemoryPersonalityStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cozy Sidekick'), findsWidgets);
      expect(find.byKey(const ValueKey('preset-cozy')), findsNothing);
      expect(find.text('Curious Guide'), findsNothing);
      expect(find.byKey(const ValueKey('preset-curious')), findsOneWidget);
    },
  );

  for (final preset in Personality.presets) {
    testWidgets(
      '${preset.name} switches immediately and customization stays unsaved until Save',
      (tester) async {
        final store = InMemoryPersonalityStore();
        final original = await store.loadPersonalities();
        await tester.pumpWidget(
          MaterialApp(home: PersonalityScreen(personalityStore: store)),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(ValueKey(preset.id)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(preset.id)));
        await tester.pumpAndSettle();
        expect((await store.loadActivePersonality()).id, preset.id);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          tester.widget<ChoiceChip>(find.byKey(ValueKey(preset.id))).selected,
          isTrue,
        );
        expect((await store.loadPersonalities()).single.isDefault, isTrue);
        await tester.tap(find.byKey(const Key('customizePresetButton')));
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
        expect((await store.loadActivePersonality()).id, preset.id);
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
      await tester.pumpWidget(
        MaterialApp(home: PersonalityScreen(personalityStore: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-curious')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('customizePresetButton')));
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
      expect((await store.loadActivePersonality()).id, 'preset-curious');
      expect(Personality.presets.first.name, 'Curious');
    },
  );
}
