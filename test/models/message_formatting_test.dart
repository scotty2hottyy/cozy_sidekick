import 'package:cozy_sidekick/models/message_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats replies and math by default, but not dollar math', () {
    const formatting = MessageFormatting();
    expect(formatting.formatReplies, isTrue);
    expect(formatting.showMath, isTrue);
    expect(formatting.dollarMath, isFalse);
    expect(formatting.rendersMath, isTrue);
    expect(formatting.rendersDollarMath, isFalse);
  });

  test('math needs formatting, and dollar math needs math', () {
    expect(const MessageFormatting(formatReplies: false).rendersMath, isFalse);
    expect(const MessageFormatting(showMath: false).rendersMath, isFalse);
    expect(const MessageFormatting(dollarMath: true).rendersDollarMath, isTrue);
    expect(
      const MessageFormatting(
        showMath: false,
        dollarMath: true,
      ).rendersDollarMath,
      isFalse,
    );
    expect(
      const MessageFormatting(
        formatReplies: false,
        dollarMath: true,
      ).rendersDollarMath,
      isFalse,
    );
  });

  test('copyWith changes only the switches it is given', () {
    const formatting = MessageFormatting();
    expect(
      formatting.copyWith(dollarMath: true),
      const MessageFormatting(dollarMath: true),
    );
    expect(formatting.copyWith(), formatting);
    expect(
      formatting.copyWith(formatReplies: false).hashCode,
      const MessageFormatting(formatReplies: false).hashCode,
    );
  });
}
