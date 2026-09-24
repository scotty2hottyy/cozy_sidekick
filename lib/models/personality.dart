/// A named set of system instructions that can shape the AI's responses.
class Personality {
  final String id;
  final String name;
  final String systemPrompt;
  final bool isDefault;

  Personality({
    required this.id,
    required this.name,
    required this.systemPrompt,
    this.isDefault = false,
  });
}
