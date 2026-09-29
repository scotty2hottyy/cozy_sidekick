import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const thinking = 'Try dividing by 7.';
  final reply = ChatMessage.assistant('No.', reasoning: thinking);
  final toggle = find.byKey(const Key('reasoningToggle'));

  testWidgets('a reply with reasoning starts with a collapsed row', (
    tester,
  ) async {
    var toggles = 0;
    await _showBubble(
      tester,
      MessageBubble(
        message: reply,
        showReasoning: true,
        onReasoningToggle: () => toggles++,
      ),
    );

    expect(toggle, findsOneWidget);
    expect(
      find.descendant(of: toggle, matching: find.text('Reasoning')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.text(thinking), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(
      tester.getRect(toggle).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('No.')).top),
    );

    await tester.tap(toggle);
    expect(toggles, 1);
  });

  testWidgets('expanded reasoning sits between the row and the reply', (
    tester,
  ) async {
    await _showBubble(
      tester,
      MessageBubble(
        message: reply,
        showReasoning: true,
        reasoningExpanded: true,
        onReasoningToggle: () {},
      ),
    );

    final reasoning = find.text(thinking);
    expect(reasoning, findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    final theme = Theme.of(tester.element(reasoning));
    final style = tester.widget<Text>(reasoning).style;
    expect(style?.fontSize, theme.textTheme.bodySmall?.fontSize);
    expect(style?.color, theme.colorScheme.onSurfaceVariant);

    final divider = find.byType(Divider);
    expect(divider, findsOneWidget);
    expect(
      tester.getRect(toggle).bottom,
      lessThanOrEqualTo(tester.getRect(reasoning).top),
    );
    expect(
      tester.getRect(reasoning).bottom,
      lessThanOrEqualTo(tester.getRect(divider).top),
    );
    expect(
      tester.getRect(divider).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('No.')).top),
    );
  });

  testWidgets('screen readers find the row as its own button', (tester) async {
    final semantics = tester.ensureSemantics();
    for (final expanded in <bool>[false, true]) {
      await _showBubble(
        tester,
        MessageBubble(
          message: reply,
          showReasoning: true,
          reasoningExpanded: expanded,
          onReasoningToggle: () {},
        ),
      );
      expect(
        tester.getSemantics(toggle),
        isSemantics(
          label: 'Reasoning',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: expanded,
        ),
      );
      // The reply is read separately and keeps its long-press Copy action.
      expect(
        tester.getSemantics(find.text('No.')),
        isSemantics(isButton: false, hasLongPressAction: true),
      );
    }
    semantics.dispose();
  });

  testWidgets('long-press offers Read aloud when a callback is supplied', (
    tester,
  ) async {
    var reads = 0;
    await _showBubble(
      tester,
      MessageBubble(message: reply, onReadAloud: () => reads++),
    );

    await tester.longPress(find.text('No.'));
    await tester.pumpAndSettle();
    expect(find.text('Read aloud'), findsOneWidget);
    await tester.tap(find.text('Read aloud'));
    await tester.pumpAndSettle();
    expect(reads, 1);
  });

  testWidgets('while it thinks, the reasoning grows under an open row', (
    tester,
  ) async {
    await _showBubble(
      tester,
      MessageBubble(
        message: ChatMessage.assistant('', reasoning: thinking),
        showReasoning: true,
        onReasoningToggle: () {},
      ),
    );

    final row = find.text('Thinking…');
    expect(row, findsOneWidget);
    expect(find.text('Reasoning'), findsNothing);
    expect(find.text(thinking), findsOneWidget);
    expect(
      tester.getRect(row).bottom,
      lessThanOrEqualTo(tester.getRect(find.text(thinking)).top),
    );
    // Nothing to tap, and no divider, since the answer hasn't started.
    expect(toggle, findsNothing);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
    expect(find.byType(Divider), findsNothing);

    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(row),
      isSemantics(
        label: 'Thinking…',
        isButton: false,
        hasTapAction: false,
        hasExpandedState: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the row counts the seconds until the answer starts', (
    tester,
  ) async {
    MessageBubble bubble(String text) => MessageBubble(
      message: ChatMessage.assistant(text, reasoning: thinking),
      showReasoning: true,
      onReasoningToggle: () {},
    );
    await _showBubble(tester, bubble(''));
    expect(find.text('Thinking…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Thinking… 1s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Thinking… 12s'), findsOneWidget);

    await _showBubble(tester, bubble('No.'));
    expect(find.text('Reasoning'), findsOneWidget);
    expect(find.textContaining('Thinking'), findsNothing);
  });

  testWidgets('without the setting or reasoning, bubbles look as before', (
    tester,
  ) async {
    Future<Size> bubbleSize(MessageBubble bubble) async {
      await _showBubble(tester, bubble);
      return tester.getSize(
        find
            .descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
    }

    final plain = ChatMessage.assistant('No.');
    final before = await bubbleSize(MessageBubble(message: plain));
    for (final bubble in <MessageBubble>[
      MessageBubble(message: reply),
      MessageBubble(message: reply, reasoningExpanded: true),
      MessageBubble(message: plain, showReasoning: true),
    ]) {
      expect(await bubbleSize(bubble), before);
      expect(toggle, findsNothing);
      expect(find.text(thinking), findsNothing);
      expect(find.text('No.'), findsOneWidget);
    }
  });
}

Future<void> _showBubble(WidgetTester tester, MessageBubble bubble) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ListView(children: <Widget>[bubble])),
    ),
  );
  await tester.pumpAndSettle();
}
