import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:cozy_sidekick/widgets/speakable_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes markdown formatting but keeps useful text', () {
    expect(
      speakableText(
        '# Hello\n- **Bold** item\n[Open docs](https://example.com)\n'
        'Use `print(1)` now.',
      ),
      'Hello\nBold item\nOpen docs\nUse print(1) now.',
    );
  });

  test('replaces code blocks, tables, and display math with screen cues', () {
    expect(
      speakableText(
        '```python\nprint("hello")\n```\n'
        '| A | B |\n| --- | --- |\n| 1 | 2 |\n'
        r'\[x^2 + 1\]',
      ),
      'See the code on screen.\nSee the table on screen.\n'
      'See the equation on screen.',
    );
  });

  test('reads inline math and converts dollar math only when enabled', () {
    expect(speakableText(r'It is \(x+1\). $2+3$.'), r'It is x+1. $2+3$.');
    expect(
      speakableText(
        r'It is \(x+1\). $2+3$.',
        formatting: const MessageFormatting(dollarMath: true),
      ),
      'It is x+1. 2+3.',
    );
  });
}
