/// How the sidekick's replies are drawn. Changed on the Appearance screen.
///
/// Settings are immutable: to change one, use [copyWith].
class MessageFormatting {
  const MessageFormatting({
    this.formatReplies = true,
    this.showMath = true,
    this.dollarMath = false,
  });

  /// Draws Markdown: bold text, lists, headings, links, code blocks and
  /// tables. When false, replies show their raw text.
  final bool formatReplies;

  /// Draws `\( … \)` and `\[ … \]` as equations. Only used when
  /// [formatReplies] is on.
  final bool showMath;

  /// Also treats `$ … $` and `$$ … $$` as math. Off by default because
  /// prices can look like math. Only used when [showMath] is on.
  final bool dollarMath;

  /// Whether equations are drawn, which also needs [formatReplies].
  bool get rendersMath => formatReplies && showMath;

  /// Whether `$` counts as a math delimiter, which needs [rendersMath] too.
  bool get rendersDollarMath => rendersMath && dollarMath;

  MessageFormatting copyWith({
    bool? formatReplies,
    bool? showMath,
    bool? dollarMath,
  }) => MessageFormatting(
    formatReplies: formatReplies ?? this.formatReplies,
    showMath: showMath ?? this.showMath,
    dollarMath: dollarMath ?? this.dollarMath,
  );

  @override
  bool operator ==(Object other) =>
      other is MessageFormatting &&
      other.formatReplies == formatReplies &&
      other.showMath == showMath &&
      other.dollarMath == dollarMath;

  @override
  int get hashCode => Object.hash(formatReplies, showMath, dollarMath);

  @override
  String toString() =>
      'MessageFormatting(formatReplies: $formatReplies, '
      'showMath: $showMath, dollarMath: $dollarMath)';
}
