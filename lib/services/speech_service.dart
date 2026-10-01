import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechServiceState {
  idle,
  listening,
  unavailable,
  permissionDenied,
  error,
}

class SpeechLanguage {
  const SpeechLanguage({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class SpeechService {
  SpeechServiceState get state;
  Future<List<SpeechLanguage>> locales();
  Future<SpeechServiceState> startListening({
    required ValueChanged<String> onText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<SpeechServiceState> onStateChanged,
    String? localeId,
    bool sendWhenDone = false,
  });
  Future<void> stopListening();
  Future<void> dispose();
}

class DeviceSpeechService implements SpeechService {
  DeviceSpeechService({SpeechToText? speechToText})
    : _speechToText = speechToText ?? SpeechToText();
  final SpeechToText _speechToText;
  SpeechServiceState _state = SpeechServiceState.idle;
  ValueChanged<SpeechServiceState>? _onStateChanged;
  bool _initialized = false;

  @override
  SpeechServiceState get state => _state;

  @override
  Future<List<SpeechLanguage>> locales() async {
    try {
      final locales = await _speechToText.locales().timeout(
        const Duration(seconds: 3),
      );
      return locales
          .map(
            (locale) => SpeechLanguage(id: locale.localeId, name: locale.name),
          )
          .toList();
    } on Object {
      return const <SpeechLanguage>[];
    }
  }

  @override
  Future<SpeechServiceState> startListening({
    required ValueChanged<String> onText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<SpeechServiceState> onStateChanged,
    String? localeId,
    bool sendWhenDone = false,
  }) async {
    _onStateChanged = onStateChanged;
    try {
      if (!_initialized) {
        final available = await _speechToText.initialize(
          onStatus: _handleStatus,
          onError: _handleError,
        );
        if (!available) {
          _setState(
            await _speechToText.hasPermission
                ? SpeechServiceState.unavailable
                : SpeechServiceState.permissionDenied,
          );
          return _state;
        }
        _initialized = true;
      }
      await _speechToText.listen(
        onResult: (result) {
          onText(result.recognizedWords);
          if (result.finalResult) onFinalResult(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: localeId,
          pauseFor: sendWhenDone ? const Duration(seconds: 3) : null,
          autoPunctuation: true,
        ),
      );
      _setState(SpeechServiceState.listening);
    } on Exception {
      _setState(SpeechServiceState.error);
    }
    return _state;
  }

  void _handleStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      _setState(SpeechServiceState.listening);
    } else if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _setState(SpeechServiceState.idle);
    }
  }

  void _handleError(SpeechRecognitionError error) {
    final message = error.errorMsg.toLowerCase();
    _setState(
      message.contains('permission') || message.contains('denied')
          ? SpeechServiceState.permissionDenied
          : SpeechServiceState.error,
    );
  }

  void _setState(SpeechServiceState value) {
    _state = value;
    _onStateChanged?.call(value);
  }

  @override
  Future<void> stopListening() async {
    try {
      await _speechToText.stop();
      _setState(SpeechServiceState.idle);
    } on Exception {
      _setState(SpeechServiceState.error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_speechToText.isListening) await _speechToText.cancel();
    _onStateChanged = null;
  }
}
