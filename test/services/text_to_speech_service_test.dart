import 'package:cozy_sidekick/services/text_to_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits long text into bounded chunks and preserves every word', () {
    final text =
        '${List<String>.filled(12, 'paragraph words').join(' ')}'
        '\n\nSecond paragraph.';
    final chunks = splitSpeechText(text, maxLength: 24);

    expect(chunks.every((chunk) => chunk.length <= 24), isTrue);
    expect(chunks.join(' '), contains('paragraph words'));
    expect(chunks.last, 'Second paragraph.');
  });

  test('omits empty paragraphs', () {
    expect(splitSpeechText('  \n\nHello.\n\n  '), <String>['Hello.']);
  });
}
