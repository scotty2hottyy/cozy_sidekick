import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

class SpeechVoice {
  const SpeechVoice({required this.name, required this.locale});

  final String name;
  final String locale;
}

abstract interface class TextToSpeechService {
  Future<List<SpeechVoice>> voices();
  Future<void> speak(
    String text, {
    String? voiceName,
    String? voiceLocale,
    double rate = 0.5,
  });
  Future<void> stop();
  Future<void> dispose();
}

class DeviceTextToSpeechService implements TextToSpeechService {
  DeviceTextToSpeechService({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts() {
    _flutterTts.setCompletionHandler(_completeCurrentChunk);
    _flutterTts.setCancelHandler(_completeCurrentChunk);
  }

  final FlutterTts _flutterTts;
  int _generation = 0;
  Completer<void>? _activeChunk;

  @override
  Future<List<SpeechVoice>> voices() async {
    final result = await _flutterTts.getVoices;
    if (result is! List) return const <SpeechVoice>[];
    return result
        .whereType<Map>()
        .map((voice) {
          final name = voice['name'];
          final locale = voice['locale'];
          if (name is! String || locale is! String) return null;
          return SpeechVoice(name: name, locale: locale);
        })
        .whereType<SpeechVoice>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> speak(
    String text, {
    String? voiceName,
    String? voiceLocale,
    double rate = 0.5,
  }) async {
    final generation = ++_generation;
    _completeCurrentChunk();
    await _flutterTts.stop();
    await _flutterTts.awaitSpeakCompletion(false);
    await _flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      <IosTextToSpeechAudioCategoryOptions>[
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
    );
    await _flutterTts.setSpeechRate(rate);
    if (voiceName != null && voiceLocale != null) {
      await _flutterTts.setVoice(<String, String>{
        'name': voiceName,
        'locale': voiceLocale,
      });
    }

    for (final chunk in splitSpeechText(text)) {
      if (generation != _generation) return;
      final completion = Completer<void>();
      _activeChunk = completion;
      try {
        await _flutterTts.speak(chunk);
        await completion.future;
      } finally {
        if (identical(_activeChunk, completion)) _activeChunk = null;
      }
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    _completeCurrentChunk();
    await _flutterTts.stop();
  }

  @override
  Future<void> dispose() => stop();

  void _completeCurrentChunk() {
    final active = _activeChunk;
    if (active != null && !active.isCompleted) active.complete();
    _activeChunk = null;
  }
}

List<String> splitSpeechText(String text, {int maxLength = 3800}) {
  if (maxLength <= 0) throw ArgumentError.value(maxLength, 'maxLength');
  final chunks = <String>[];
  for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
    var remaining = paragraph.trim();
    while (remaining.length > maxLength) {
      var splitAt = remaining.lastIndexOf(' ', maxLength);
      if (splitAt < maxLength ~/ 2) splitAt = maxLength;
      chunks.add(remaining.substring(0, splitAt).trim());
      remaining = remaining.substring(splitAt).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
  }
  return chunks;
}
