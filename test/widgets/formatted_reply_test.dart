import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/widgets/formatted_reply.dart';
import 'package:cozy_sidekick/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('convertDollarMath', () {
    test('turns dollar math into LaTeX delimiters', () {
      expect(convertDollarMath(r'Area is $x^2$.'), r'Area is \(x^2\).');
      expect(convertDollarMath(r'$$\frac{a}{b}$$'), r'\[\frac{a}{b}\]');
      expect(
        convertDollarMath(_lines([r'$$', r'x^2', r'$$'])),
        _lines([r'\[', r'x^2', r'\]']),
      );
      expect(convertDollarMath(r'Both \(a\) and $b$'), r'Both \(a\) and \(b\)');
      expect(convertDollarMath(r'$a$$b$'), r'\(a\)\(b\)');
    });

    test('leaves prices and lone dollar signs alone', () {
      for (final text in <String>[
        r'It costs $5 and $10.',
        r'$5-$10',
        r'Pay $ 5 $ now',
        r'A lone $',
        r'$x',
        r'$$ $$',
        r'\$x\$',
      ]) {
        expect(convertDollarMath(text), text, reason: text);
      }
    });

    test('never changes code', () {
      for (final text in <String>[
        r'Run `echo $HOME $PATH` now.',
        r'Use ``a `$x$` b`` here',
        _lines(['```bash', r'echo "$HOME and $PATH"', '```']),
        _lines(['~~~', r'$x$', '~~~']),
        _lines(['1. Step', '   ```', r'   $x$ and $y$', '   ```']),
      ]) {
        expect(convertDollarMath(text), text, reason: text);
      }
      expect(
        convertDollarMath(_lines(['```', r'$a$', '```', r'Then $b$'])),
        _lines(['```', r'$a$', '```', r'Then \(b\)']),
      );
    });

    test('keeps existing LaTeX as written', () {
      expect(convertDollarMath(r'\[ \text{$x$ cm} \]'), r'\[ \text{$x$ cm} \]');
      expect(convertDollarMath(r'\( \$5 \)'), r'\( \$5 \)');
    });

    test('math never spans a blank line', () {
      expect(
        convertDollarMath(_lines([r'$a', '', r'b$'])),
        _lines([r'$a', '', r'b$']),
      );
      expect(
        convertDollarMath(_lines([r'$$a', '', r'b$$ and $$c$$'])),
        _lines([r'$$a', '', r'b$$ and \[c\]']),
      );
      expect(
        convertDollarMath(_lines([r'$a', r'b$'])),
        _lines([r'\(a', r'b\)']),
      );
    });
  });

  testWidgets('renders Markdown in replies', (tester) async {
    await _showReply(
      tester,
      _lines([
        '## Planets',
        '',
        '**Bold** and *italic* text, with [a link](https://example.com).',
        '',
        '- Mercury',
        '- Venus',
        '',
        '| Planet | Moons |',
        '|---|---|',
        '| Earth | 1 |',
        '',
        '```python',
        'print("hi")',
        '```',
      ]),
    );
    expect(_styleOf(tester, 'Bold')?.fontWeight, FontWeight.bold);
    expect(_styleOf(tester, 'italic')?.fontStyle, FontStyle.italic);
    final body = _styleOf(tester, ' and ')!.fontSize!;
    expect(_styleOf(tester, 'Planets')!.fontSize, greaterThan(body));
    expect(_text('a link'), findsOneWidget);
    expect(_text('Mercury'), findsOneWidget);
    expect(_text('Venus'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(_text('Earth'), findsOneWidget);
    expect(_text('print("hi")'), findsOneWidget);
    for (final syntax in <String>['**', '## ', '](', '- Mercury', '|', '```']) {
      expect(_text(syntax), findsNothing, reason: syntax);
    }
  });

  testWidgets('inline math sits within its sentence', (tester) async {
    await _showReply(tester, r'The total is \(25 + 17 = 42\).');
    final sentence = _text('The total is');
    expect(sentence, findsOneWidget);
    expect(
      find.descendant(of: sentence, matching: find.byType(Math)),
      findsWidgets,
    );
    expect(_parseErrors(tester), everyElement(isNull));
    expect(_text(r'\('), findsNothing);
  });

  testWidgets('inline math keeps the spacing of the unbroken equation', (
    tester,
  ) async {
    await _showReply(tester, r'Sum: \(a + b = c\)');
    final pieces = tester.widgetList<Math>(find.byType(Math)).toList();
    expect(pieces, hasLength(3));
    final width = pieces
        .map((piece) => tester.getSize(find.byWidget(piece)).width)
        .reduce((a, b) => a + b);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => Math.tex(
                'a + b = c',
                mathStyle: MathStyle.text,
                textStyle: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(Math)).width,
      moreOrLessEquals(width, epsilon: 0.5),
    );
  });

  testWidgets('display math gets its own line', (tester) async {
    await _showReply(
      tester,
      _lines([
        'Root two:',
        r'\[ \sqrt{2} = 1.\underbrace{41421}_{\text{5 digits}}\ldots \]',
        'Done.',
      ]),
    );
    final math = find.byType(Math);
    expect(math, findsOneWidget);
    expect(_parseErrors(tester), everyElement(isNull));
    expect(
      tester.getRect(math).top,
      greaterThanOrEqualTo(_rectOf(tester, 'Root two:').bottom),
    );
    expect(
      _rectOf(tester, 'Done.').top,
      greaterThanOrEqualTo(tester.getRect(math).bottom),
    );
  });

  testWidgets('align environments are drawn as aligned', (tester) async {
    await _showReply(
      tester,
      r'\[\begin{align*} a &= b \\ c &= d \end{align*}\]',
    );
    expect(find.byType(Math), findsOneWidget);
    expect(_parseErrors(tester), everyElement(isNull));
  });

  testWidgets('dollar signs are only math when Dollar-sign math is on', (
    tester,
  ) async {
    await _showReply(tester, r'It costs $5 and $10. Area is $x^2$.');
    expect(find.byType(Math), findsNothing);
    expect(_text(r'It costs $5 and $10. Area is $x^2$.'), findsOneWidget);

    const dollars = MessageFormatting(dollarMath: true);
    await _showReply(tester, r'Area is $x^2$.', formatting: dollars);
    expect(find.byType(Math), findsOneWidget);
    await _showReply(tester, r'$$\frac{a}{b}$$', formatting: dollars);
    expect(find.byType(Math), findsOneWidget);
    await _showReply(tester, r'It costs $5 and $10.', formatting: dollars);
    expect(find.byType(Math), findsNothing);
    expect(_text(r'It costs $5 and $10.'), findsOneWidget);
  });

  testWidgets('code is never rendered as math', (tester) async {
    // Each reply has only one kind of delimiter, because gpt_markdown's own
    // dollar handling turns itself off when a reply also contains `\(`.
    for (final (reply, code) in <(String, String)>[
      (r'Run `echo $HOME $PATH` now.', r'echo $HOME $PATH'),
      (r'Type `\(x\)` for math.', r'\(x\)'),
      (
        _lines(['```bash', r'echo "$HOME and $PATH"', '```']),
        r'echo "$HOME and $PATH"',
      ),
      (_lines(['```python', r'print(r"\(x\)")', '```']), r'print(r"\(x\)")'),
    ]) {
      await _showReply(
        tester,
        reply,
        formatting: const MessageFormatting(dollarMath: true),
      );
      expect(find.byType(Math), findsNothing, reason: reply);
      expect(_text(code), findsOneWidget, reason: reply);
    }
  });

  testWidgets('invalid LaTeX shows as plain text without an error', (
    tester,
  ) async {
    for (final reply in <String>[
      r'Oops \(\frac{1}{\) here',
      r'\[\frac{1}{\]',
    ]) {
      await _showReply(tester, reply);
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(_parseErrors(tester), everyElement(isNotNull));
      final source = find.textContaining(r'\frac{1}{');
      expect(source, findsOneWidget, reason: reply);
      final colors = Theme.of(tester.element(source)).colorScheme;
      expect(
        tester.widget<Text>(source).style?.color,
        colors.onSurfaceVariant,
        reason: 'the error color is only for debug builds',
      );
    }
  });

  for (final size in const <Size>[Size(360, 740), Size(740, 360)]) {
    testWidgets('wide content scrolls instead of overflowing at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final longSum = List<String>.generate(30, (i) => 'a_{$i}').join(' + ');
      await _showReply(
        tester,
        _lines([
          'Inline: \\($longSum\\).',
          '',
          '\\[$longSum\\]',
          '',
          '| ${List<String>.generate(12, (i) => 'Column $i').join(' | ')} |',
          '|${List<String>.filled(12, '---').join('|')}|',
          '| ${List<String>.filled(12, 'value').join(' | ')} |',
          '',
          '```',
          'x = "${'long line ' * 20}"',
          '```',
        ]),
      );
      expect(tester.takeException(), isNull);
      for (final wide in <Finder>[
        find.byType(Table),
        find.textContaining('long line'),
        find.byWidgetPredicate(
          (widget) => widget is Math && widget.mathStyle == MathStyle.display,
        ),
      ]) {
        expect(
          find.ancestor(of: wide, matching: _sidewaysScroll),
          findsWidgets,
        );
      }
      // Inline math wraps inside the bubble instead.
      final bubble = tester.getRect(find.byType(FormattedReply));
      final inline = find.byWidgetPredicate(
        (widget) => widget is Math && widget.mathStyle == MathStyle.text,
      );
      expect(inline, findsWidgets);
      for (final element in inline.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.left, greaterThanOrEqualTo(bubble.left));
        expect(rect.right, lessThanOrEqualTo(bubble.right));
      }
    });
  }

  testWidgets('Format replies off shows the raw text', (tester) async {
    const reply = r'**Bold** and \(x^2\)';
    await _showReply(
      tester,
      reply,
      formatting: const MessageFormatting(formatReplies: false),
    );
    expect(find.byType(FormattedReply), findsNothing);
    expect(find.byType(Math), findsNothing);
    expect(find.text(reply), findsOneWidget);
  });

  testWidgets('Show math off keeps Markdown but shows LaTeX source', (
    tester,
  ) async {
    await _showReply(
      tester,
      r'**Total:** \(25 + 17 = 42\)',
      formatting: const MessageFormatting(showMath: false, dollarMath: true),
    );
    expect(find.byType(Math), findsNothing);
    expect(_styleOf(tester, 'Total:')?.fontWeight, FontWeight.bold);
    expect(_text(r'\(25 + 17 = 42\)'), findsOneWidget);
  });

  testWidgets('user messages stay plain text', (tester) async {
    const text = r'**not bold** and \(x\)';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MessageBubble(message: ChatMessage.user(text))),
      ),
    );
    expect(find.byType(FormattedReply), findsNothing);
    expect(find.text(text), findsOneWidget);

    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('long-pressing a reply copies its original text', (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    const reply = r'**Total:** \(25 + 17 = 42\)';
    await _showReply(tester, reply);

    await tester.longPress(find.byType(FormattedReply));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, reply);
    expect(find.text('Copied'), findsOneWidget);
  });
}

String _lines(List<String> lines) => lines.join('\n');

Future<void> _showReply(
  WidgetTester tester,
  String text, {
  MessageFormatting formatting = const MessageFormatting(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            MessageBubble(
              message: ChatMessage.assistant(text),
              formatting: formatting,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Paragraphs whose text contains [text]. gpt_markdown draws most paragraphs
/// with its own BidiRichText widget, so this matches what's drawn rather than
/// only RichText widgets.
Finder _text(String text) => find.byElementPredicate(
  (element) =>
      element is RenderObjectElement &&
      element.renderObject is RenderParagraph &&
      (element.renderObject as RenderParagraph).text.toPlainText().contains(
        text,
      ),
  description: 'paragraph containing "$text"',
);

/// Where [part] of a paragraph's text is drawn, in global coordinates.
Rect _rectOf(WidgetTester tester, String part) {
  final paragraph = tester.renderObject<RenderParagraph>(_text(part));
  final start = paragraph.text.toPlainText().indexOf(part);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + part.length),
  );
  return boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b))
      .shift(paragraph.localToGlobal(Offset.zero));
}

final Finder _sidewaysScroll = find.byWidgetPredicate(
  (widget) =>
      widget is SingleChildScrollView &&
      widget.scrollDirection == Axis.horizontal,
);

List<Object?> _parseErrors(WidgetTester tester) => <Object?>[
  for (final math in tester.widgetList<Math>(find.byType(Math)))
    math.parseError,
];

/// The style [text] is drawn with, found by walking every paragraph.
TextStyle? _styleOf(WidgetTester tester, String text) {
  TextStyle? search(InlineSpan span, TextStyle? inherited) {
    final style = inherited?.merge(span.style) ?? span.style;
    if (span is! TextSpan) return null;
    if (span.text == text) return style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = search(child, style);
      if (found != null) return found;
    }
    return null;
  }

  for (final element in _text('').evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final found = search(paragraph.text, null);
    if (found != null) return found;
  }
  return null;
}
