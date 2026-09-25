import 'package:cozy_sidekick/models/personality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four distinct presets have valid names and instructions', () {
    expect(Personality.presets.map((p) => p.name), [
      'Curious',
      'Adventure',
      'Planner',
      'Captain Quip',
    ]);
    expect(Personality.presets.map((p) => p.id).toSet(), hasLength(4));
    for (final preset in Personality.presets) {
      expect(preset.name.trim(), isNotEmpty);
      expect(preset.systemPrompt.trim(), isNotEmpty);
      expect(preset.systemPrompt.length, lessThanOrEqualTo(500));
      expect(preset.isDefault, isFalse);
    }
  });
}
