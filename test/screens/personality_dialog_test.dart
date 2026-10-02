import 'package:cozy_sidekick/screens/personality_screen.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the personality dialog shows the focused field in landscape '
      'with the keyboard up', (tester) async {
    const screen = Size(915, 412);
    const keyboard = 200.0;
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = InMemoryPersonalityStore();
    await tester.pumpWidget(
      MaterialApp(home: PersonalityScreen(personalityStore: store)),
    );
    await tester.pumpAndSettle();
    final add = find.byKey(const Key('addPersonalityButton'));
    await tester.scrollUntilVisible(
      add,
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(add);
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final name = find.byKey(const Key('personalityNameField'));
    final prompt = find.byKey(const Key('personalityPromptField'));
    _expectCaretShown(tester, name, visibleBottom: screen.height - keyboard);

    await tester.enterText(name, 'Night owl');
    await tester.showKeyboard(prompt);
    await tester.pumpAndSettle();
    _expectCaretShown(tester, prompt, visibleBottom: screen.height - keyboard);

    await tester.enterText(prompt, 'Talk softly.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await store.loadPersonalities()).map((p) => p.name),
      contains('Night owl'),
    );
  });
}

/// Expects the caret in [field] to be drawn inside the dialog's scroll view
/// and above [visibleBottom], so the user can see what they type.
void _expectCaretShown(
  WidgetTester tester,
  Finder field, {
  required double visibleBottom,
}) {
  final editable = tester.state<EditableTextState>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  expect(editable.widget.focusNode.hasFocus, isTrue);
  final render = editable.renderEditable;
  final local = render.getLocalRectForCaret(
    editable.textEditingValue.selection.extent,
  );
  final caret = render.localToGlobal(local.topLeft) & local.size;
  final viewport = tester.getRect(
    find.ancestor(of: field, matching: find.byType(Scrollable)).first,
  );
  expect(caret.height, greaterThan(0));
  expect(caret.top, greaterThanOrEqualTo(viewport.top));
  expect(caret.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(caret.bottom, lessThanOrEqualTo(visibleBottom));
}
