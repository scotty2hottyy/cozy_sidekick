import 'dart:async';

import 'package:flutter/material.dart';

import '../models/speech_settings.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../services/text_to_speech_service.dart';

class VoiceSpeechScreen extends StatefulWidget {
  const VoiceSpeechScreen({
    super.key,
    required this.settingsStore,
    required this.speechService,
    required this.textToSpeechService,
  });

  final AppSettingsStore settingsStore;
  final SpeechService speechService;
  final TextToSpeechService textToSpeechService;

  @override
  State<VoiceSpeechScreen> createState() => _VoiceSpeechScreenState();
}

class _VoiceSpeechScreenState extends State<VoiceSpeechScreen> {
  SpeechSettings? _settings;
  List<SpeechLanguage> _languages = const <SpeechLanguage>[];
  List<SpeechVoice> _voices = const <SpeechVoice>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.settingsStore.loadSpeechSettings();
    final languages = await widget.speechService.locales().timeout(
      const Duration(seconds: 3),
      onTimeout: () => const <SpeechLanguage>[],
    );
    List<SpeechVoice> voices;
    try {
      voices = await widget.textToSpeechService.voices().timeout(
        const Duration(seconds: 3),
      );
    } on Object {
      voices = const <SpeechVoice>[];
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _languages = languages;
      _voices = voices;
    });
  }

  Future<void> _save(SpeechSettings settings) async {
    setState(() => _settings = settings);
    await widget.settingsStore.saveSpeechSettings(settings);
  }

  List<SpeechVoice> get _matchingVoices {
    final languageId = _settings?.languageId;
    if (languageId == null)
      return List<SpeechVoice>.of(_voices)
        ..sort((a, b) => a.name.compareTo(b.name));
    final language = languageId.split('-').first.toLowerCase();
    return _voices
        .where(
          (voice) => voice.locale.toLowerCase().split('-').first == language,
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static String _voiceValue(SpeechVoice voice) =>
      '${voice.locale}::${voice.name}';

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Voice & Speech')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    Text(
                      'Voice input',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('speechLanguageDropdown'),
                      initialValue:
                          _languages.any(
                            (language) => language.id == settings.languageId,
                          )
                          ? settings.languageId!
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Language',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem(
                          value: '',
                          child: Text("Phone's language"),
                        ),
                        for (final language in _languages)
                          DropdownMenuItem(
                            value: language.id,
                            child: Text(language.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        final id = value.isEmpty ? null : value;
                        final voiceStillMatches =
                            id == null ||
                            settings.voiceLocale
                                    ?.split('-')
                                    .first
                                    .toLowerCase() ==
                                id.split('-').first.toLowerCase();
                        _save(
                          settings.copyWith(
                            languageId: id,
                            clearLanguageId: id == null,
                            clearVoice: !voiceStillMatches,
                          ),
                        );
                      },
                    ),
                    SwitchListTile(
                      key: const Key('speechAutoSendSwitch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send when I stop talking'),
                      value: settings.sendWhenDone,
                      onChanged: (value) =>
                          _save(settings.copyWith(sendWhenDone: value)),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Read replies aloud',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<ReadAloudMode>(
                      key: const Key('readAloudMode'),
                      segments: const <ButtonSegment<ReadAloudMode>>[
                        ButtonSegment(
                          value: ReadAloudMode.off,
                          label: Text('Off'),
                        ),
                        ButtonSegment(
                          value: ReadAloudMode.afterSpoken,
                          label: Text('After I talk'),
                        ),
                        ButtonSegment(
                          value: ReadAloudMode.always,
                          label: Text('Always'),
                        ),
                      ],
                      selected: <ReadAloudMode>{settings.readAloud},
                      onSelectionChanged: (selection) =>
                          _save(settings.copyWith(readAloud: selection.first)),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: const Key('speechVoiceDropdown'),
                      initialValue: _selectedVoiceValue(settings),
                      decoration: const InputDecoration(
                        labelText: 'Voice',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem(
                          value: '',
                          child: Text("Phone's default"),
                        ),
                        for (final voice in _matchingVoices)
                          DropdownMenuItem(
                            value: _voiceValue(voice),
                            child: Text('${voice.name} (${voice.locale})'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null || value.isEmpty) {
                          _save(settings.copyWith(clearVoice: true));
                          return;
                        }
                        final voice = _matchingVoices.firstWhere(
                          (item) => _voiceValue(item) == value,
                        );
                        _save(
                          settings.copyWith(
                            voiceName: voice.name,
                            voiceLocale: voice.locale,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Speed: ${settings.rate == 0.5 ? 'Normal' : settings.rate.toStringAsFixed(2)}',
                    ),
                    Slider(
                      key: const Key('speechRateSlider'),
                      min: 0.25,
                      max: 0.75,
                      divisions: 10,
                      value: settings.rate.clamp(0.25, 0.75),
                      label: settings.rate == 0.5 ? 'Normal' : null,
                      onChanged: (value) =>
                          _save(settings.copyWith(rate: value)),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const Key('playSpeechSample'),
                        onPressed: () => widget.textToSpeechService.speak(
                          'Hello. This is a sample of your chosen voice.',
                          voiceName: settings.voiceName,
                          voiceLocale: settings.voiceLocale,
                          rate: settings.rate,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play sample'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _selectedVoiceValue(SpeechSettings settings) {
    if (settings.voiceName == null || settings.voiceLocale == null) return '';
    final voice = _matchingVoices.where(
      (item) =>
          item.name == settings.voiceName &&
          item.locale == settings.voiceLocale,
    );
    return voice.isEmpty ? '' : _voiceValue(voice.first);
  }
}
