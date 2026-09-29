import '../models/message_formatting.dart';
import 'formatted_reply.dart';

String speakableText(
  String answer, {
  MessageFormatting formatting = const MessageFormatting(),
}) {
  var source = formatting.rendersDollarMath
      ? convertDollarMath(answer)
      : answer;
  source = source
      .replaceAllMapped(
        RegExp(r'\\\[(.*?)\\\]', dotAll: true),
        (_) => ' See the equation on screen. ',
      )
      .replaceAllMapped(
        RegExp(r'\\\((.*?)\\\)', dotAll: true),
        (match) => match.group(1) ?? '',
      );

  final lines = source.split('\n');
  final spoken = <String>[];
  String? fence;
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final marker = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line)?.group(1);
    if (fence != null) {
      if (marker != null &&
          marker[0] == fence[0] &&
          marker.length >= fence.length &&
          line.trim() == marker) {
        fence = null;
      }
      index++;
      continue;
    }
    if (marker != null) {
      spoken.add('See the code on screen.');
      fence = marker;
      index++;
      continue;
    }

    if (_isTableHeader(lines, index)) {
      spoken.add('See the table on screen.');
      index += 2;
      while (index < lines.length && _isPipeRow(lines[index])) {
        index++;
      }
      continue;
    }

    spoken.add(_speakableLine(line));
    index++;
  }

  return spoken.join('\n').replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
}

bool _isTableHeader(List<String> lines, int index) =>
    index + 1 < lines.length &&
    _isPipeRow(lines[index]) &&
    _isPipeRow(lines[index + 1]) &&
    RegExp(r'^\s*\|?\s*:?-{3,}').hasMatch(lines[index + 1]);

bool _isPipeRow(String line) =>
    line.trim().startsWith('|') && line.trim().endsWith('|');

String _speakableLine(String line) {
  var result = line
      .replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+'), '')
      .replaceAll(RegExp(r'^\s*>\s?'), '')
      .replaceAll(RegExp(r'^\s*(?:[-+*]|\d+[.)])\s+'), '')
      .replaceAllMapped(RegExp(r'(`+)(.*?)\1'), (match) => match.group(2) ?? '')
      .replaceAllMapped(
        RegExp(r'(\*\*|__|~~)(.*?)\1'),
        (match) => match.group(2) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'(?<!\w)[*_](.*?)[*_](?!\w)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return result;
}
