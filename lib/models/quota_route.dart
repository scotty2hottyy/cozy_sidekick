import '../ai/ai_provider.dart';

enum QuotaUnit { requests, tokens }

class QuotaRoute {
  const QuotaRoute({
    required this.id,
    required this.provider,
    required this.model,
    required this.unit,
    this.dailyLimit,
    this.enabled = true,
  });

  static const List<QuotaRoute> defaults = <QuotaRoute>[
    QuotaRoute(
      id: 'openrouter-free',
      provider: AiProviderType.openRouter,
      model: 'openrouter/free',
      unit: QuotaUnit.requests,
      dailyLimit: 50,
    ),
    QuotaRoute(
      id: 'opencode-zen-free',
      provider: AiProviderType.openCodeZen,
      model: 'big-pickle',
      unit: QuotaUnit.requests,
    ),
    QuotaRoute(
      id: 'openai-mini',
      provider: AiProviderType.openAi,
      model: 'gpt-4o-mini',
      unit: QuotaUnit.tokens,
      dailyLimit: 2250000,
      enabled: false,
    ),
  ];

  final String id;
  final AiProviderType provider;
  final String model;
  final QuotaUnit unit;
  final int? dailyLimit;
  final bool enabled;

  QuotaRoute copyWith({
    String? model,
    int? dailyLimit,
    bool clearDailyLimit = false,
    bool? enabled,
  }) => QuotaRoute(
    id: id,
    provider: provider,
    model: model ?? this.model,
    unit: unit,
    dailyLimit: clearDailyLimit ? null : dailyLimit ?? this.dailyLimit,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'provider': provider.name,
    'model': model,
    'unit': unit.name,
    'dailyLimit': dailyLimit,
    'enabled': enabled,
  };

  factory QuotaRoute.fromJson(Map<String, Object?> json) {
    final provider = AiProviderType.values.asNameMap()[json['provider']];
    final unitName = json['unit'];
    if (provider == null || unitName is! String) {
      throw const FormatException('Invalid quota route');
    }
    return QuotaRoute(
      id: json['id'] as String,
      provider: provider,
      model: json['model'] as String,
      unit: QuotaUnit.values.byName(unitName),
      dailyLimit: json['dailyLimit'] as int?,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuotaRoute &&
      other.id == id &&
      other.provider == provider &&
      other.model == model &&
      other.unit == unit &&
      other.dailyLimit == dailyLimit &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, provider, model, unit, dailyLimit, enabled);
}
