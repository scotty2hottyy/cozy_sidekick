/// A named set of system instructions that can shape the AI's responses.
class Personality {
  final String id;
  final String name;
  final String systemPrompt;
  final bool isDefault;

  const Personality({
    required this.id,
    required this.name,
    required this.systemPrompt,
    this.isDefault = false,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'systemPrompt': systemPrompt,
    'isDefault': isDefault,
  };

  factory Personality.fromJson(Map<String, Object?> json) => Personality(
    id: json['id'] as String,
    name: json['name'] as String,
    systemPrompt: json['systemPrompt'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
  );
}
