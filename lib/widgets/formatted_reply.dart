import 'package:flutter/material.dart';
import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../models/message_formatting.dart';

/// Draws an assistant reply as Markdown, with LaTeX math when
/// [MessageFormatting.showMath] is on.
///
/// Tables, code blocks and display equations scroll sideways when they're
/// wider than the bubble. Long inline equations wrap after operators like `+`
/// and `=`, the way LaTeX breaks them.
class FormattedReply extends StatelessWidget {
  const FormattedReply(
    this.text, {
    super.key,
    this.style,
    this.formatting = const MessageFormatting(),
  });

  /// The reply exactly as the model wrote it.
  final String text;
  final TextStyle? style;
  final MessageFormatting formatting;

  @override
  Widget build(BuildContext context) => GptMarkdown(
    formatting.rendersDollarMath ? convertDollarMath(text) : text,
    style: style,
    latexBuilder: formatting.rendersMath ? _buildMath : _buildTexSource,
    styleSheet: GptMarkdownStyleSheet(
      // Rendered equations can't wrap, so wide ones scroll instead of
      // overflowing the bubble. LaTeX shown as text wraps like other text.
      latex: LatexStyle(scrollBlockHorizontally: formatting.rendersMath),
    ),
  );
}

/// Draws [tex] as an equation. Invalid LaTeX shows its source as plain text
/// instead of an error.
Widget _buildMath(
  BuildContext context,
  String tex,
  TextStyle style,
  bool inline,
) {
  final math = Math.tex(
    _withSupportedEnvironments(tex),
    textStyle: style,
    mathStyle: inline ? MathStyle.text : MathStyle.display,
    settings: const TexParserSettings(strict: Strict.ignore),
    onErrorFallback: (_) => _buildTexSource(context, tex, style, inline),
  );
  if (!inline) return math;
  // Each piece sits on the text baseline, and a line can break between
  // pieces. A single piece that's still too wide shrinks to fit.
  final parts = math.texBreak().parts;
  return Text.rich(
    TextSpan(
      children: <InlineSpan>[
        for (var i = 0; i < parts.length; i++)
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: i == parts.length - 1
                  ? parts[i]
                  : _keepTrailingSpace(parts[i]),
            ),
          ),
      ],
    ),
  );
}

/// Every piece but the last ends with an operator like `+` or `=`. On its
/// own, that operator loses the space after it, and a `+` is even drawn like
/// a letter. An empty group after it (`{}` in LaTeX) keeps the spacing of the
/// unbroken equation.
Math _keepTrailingSpace(Math part) => Math(
  ast: SyntaxTree(
    greenRoot: EquationRowNode(
      children: [...part.ast!.greenRoot.children, EquationRowNode.empty()],
    ),
  ),
  mathStyle: part.mathStyle,
  textStyle: part.textStyle,
  options: part.options,
  textScaleFactor: part.textScaleFactor,
  logicalPpi: part.logicalPpi,
  onErrorFallback: part.onErrorFallback,
);

/// Shows [tex] as LaTeX source, between `\( \)` or `\[ \]`. Used when
/// Show math is off, and for LaTeX that can't be drawn.
Widget _buildTexSource(
  BuildContext context,
  String tex,
  TextStyle style,
  bool inline,
) => Text(inline ? '\\($tex\\)' : '\\[$tex\\]', style: style);

/// flutter_math_fork can't draw some environments that models like to use,
/// but it can draw close equivalents: `align` becomes `aligned`, `gather`
/// becomes `gathered`, and an `equation` wrapper is dropped.
String _withSupportedEnvironments(String tex) => tex
    .replaceAll(RegExp(r'\{align\*?\}'), '{aligned}')
    .replaceAll(RegExp(r'\{gather\*?\}'), '{gathered}')
    .replaceAll(RegExp(r'\\(begin|end)\{equation\*?\}'), '');

/// A line that opens or closes a fenced code block, like ```` ```python ````
/// or `~~~`. A backtick fence can't have more backticks after it.
final RegExp _fence = RegExp(r'^\s*(`{3,}(?=[^`]*$)|~{3,})');

/// Rewrites `$…$` as `\(…\)` and `$$…$$` as `\[…\]`, the delimiters
/// [GptMarkdown] draws as math.
///
/// Code is never changed, so `` `echo "$HOME $PATH"` `` stays as written.
/// Fenced code blocks, inline code, math that's already in `\( \)` or `\[ \]`,
/// and escapes like `\$` are all copied as they are.
///
/// Like Pandoc, a `$` only starts math when the next character isn't a
/// space. The closing `$` must follow a non-space character and must not be
/// followed by a digit. So "It costs $5 and $10." stays text. Math can't span
/// a blank line.
String convertDollarMath(String markdown) {
  final out = <String>[];
  final prose = <String>[];
  String? fence;
  void flushProse() {
    if (prose.isEmpty) return;
    out.add(_convertProse(prose.join('\n')));
    prose.clear();
  }

  for (final line in markdown.split('\n')) {
    final marker = _fence.firstMatch(line)?.group(1);
    final openFence = fence;
    if (openFence == null) {
      if (marker == null) {
        prose.add(line);
        continue;
      }
      flushProse();
      fence = marker;
    } else if (marker != null &&
        marker[0] == openFence[0] &&
        marker.length >= openFence.length &&
        line.trim() == marker) {
      fence = null;
    }
    out.add(line);
  }
  flushProse();
  return out.join('\n');
}

/// Converts dollar math in text that has no fenced code blocks.
String _convertProse(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final char = text[i];
    var next = i + 1;
    if (char == r'\' && next < text.length) {
      // `\(…\)` and `\[…\]` are already math. Anything else is an escape.
      final close = switch (text[next]) {
        '(' => r'\)',
        '[' => r'\]',
        _ => null,
      };
      final end = close == null ? -1 : text.indexOf(close, next + 1);
      next = end == -1 ? next + 1 : end + 2;
      out.write(text.substring(i, next));
    } else if (char == '`') {
      // Inline code ends at the next run of the same number of backticks.
      final length = _backticks(text, i);
      final end = _closingBackticks(text, i + length, length);
      next = end == -1 ? i + length : end + length;
      out.write(text.substring(i, next));
    } else if (text.startsWith(r'$$', i)) {
      final end = text.indexOf(r'$$', i + 2);
      final tex = end == -1 ? '' : text.substring(i + 2, end);
      if (tex.trim().isEmpty) {
        next = i + 2;
        out.write(r'$$');
      } else if (_blankLine.hasMatch(tex)) {
        // Left as written, so the closing `$$` can't start another pair.
        next = end + 2;
        out.write(text.substring(i, next));
      } else {
        next = end + 2;
        out.write('\\[$tex\\]');
      }
    } else if (char == r'$') {
      final end = _closingDollar(text, i);
      if (end == -1) {
        out.write(char);
      } else {
        next = end + 1;
        out.write('\\(${text.substring(i + 1, end)}\\)');
      }
    } else {
      out.write(char);
    }
    i = next;
  }
  return out.toString();
}

/// The number of backticks in the run that starts at [start].
int _backticks(String text, int start) {
  var end = start;
  while (end < text.length && text[end] == '`') {
    end++;
  }
  return end - start;
}

/// Where the next run of exactly [length] backticks starts, or -1.
int _closingBackticks(String text, int from, int length) {
  var i = from;
  while (i < text.length) {
    if (text[i] != '`') {
      i++;
      continue;
    }
    final run = _backticks(text, i);
    if (run == length) return i;
    i += run;
  }
  return -1;
}

/// Where the `$` that closes inline math opened at [start] is, or -1.
int _closingDollar(String text, int start) {
  final first = start + 1;
  if (first >= text.length || _isSpace(text[first])) return -1;
  var i = first;
  while (i < text.length) {
    final char = text[i];
    if (char == r'\') {
      i += 2;
      continue;
    }
    if (_blankLine.matchAsPrefix(text, i) != null) return -1;
    if (char == r'$') {
      final afterIsDigit =
          i + 1 < text.length && '0123456789'.contains(text[i + 1]);
      return _isSpace(text[i - 1]) || afterIsDigit ? -1 : i;
    }
    i++;
  }
  return -1;
}

bool _isSpace(String char) => char.trim().isEmpty;

/// A blank line, which ends a paragraph.
final RegExp _blankLine = RegExp(r'\n[ \t]*\n');
