enum ReadAloudMode { off, afterSpoken, always }

class SpeechSettings {
  const SpeechSettings({
    this.languageId,
    this.sendWhenDone = false,
    this.readAloud = ReadAloudMode.off,
    this.voiceName,
    this.voiceLocale,
    this.rate = 0.5,
  });

  final String? languageId;
  final bool sendWhenDone;
  final ReadAloudMode readAloud;
  final String? voiceName;
  final String? voiceLocale;
  final double rate;

  SpeechSettings copyWith({
    String? languageId,
    bool clearLanguageId = false,
    bool? sendWhenDone,
    ReadAloudMode? readAloud,
    String? voiceName,
    String? voiceLocale,
    bool clearVoice = false,
    double? rate,
  }) => SpeechSettings(
    languageId: clearLanguageId ? null : languageId ?? this.languageId,
    sendWhenDone: sendWhenDone ?? this.sendWhenDone,
    readAloud: readAloud ?? this.readAloud,
    voiceName: clearVoice ? null : voiceName ?? this.voiceName,
    voiceLocale: clearVoice ? null : voiceLocale ?? this.voiceLocale,
    rate: rate ?? this.rate,
  );

  @override
  bool operator ==(Object other) =>
      other is SpeechSettings &&
      other.languageId == languageId &&
      other.sendWhenDone == sendWhenDone &&
      other.readAloud == readAloud &&
      other.voiceName == voiceName &&
      other.voiceLocale == voiceLocale &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(
    languageId,
    sendWhenDone,
    readAloud,
    voiceName,
    voiceLocale,
    rate,
  );
}
