import '../ai/ai_provider.dart';
import 'openai_free_tier.dart';

enum QuotaUnit { requests, tokens }

class QuotaRoute {
  const QuotaRoute({
    required this.id,
    required this.provider,
    required this.model,
    required this.unit,
    this.userLimit,
    this.enabled = true,
    this.highUsageTier = false,
  });

  static const List<QuotaRoute> defaults = <QuotaRoute>[
    QuotaRoute(
      id: 'openrouter-free',
      provider: AiProviderType.openRouter,
      model: 'openrouter/free',
      unit: QuotaUnit.requests,
    ),
    QuotaRoute(
      id: 'groq-free',
      provider: AiProviderType.groq,
      model: 'openai/gpt-oss-20b',
      unit: QuotaUnit.requests,
    ),
    QuotaRoute(
      id: 'openai-mini',
      provider: AiProviderType.openAi,
      model: 'gpt-5.6-terra',
      unit: QuotaUnit.tokens,
      userLimit: 2250000,
      enabled: false,
    ),
  ];

  final String id;
  final AiProviderType provider;
  final String model;
  final QuotaUnit unit;

  /// The most the user wants to use each day, in [unit]s, when it's less
  /// than the free quota. Null uses the whole free quota.
  final int? userLimit;
  final bool enabled;

  /// Whether the OpenAI account is on usage tier 3 or higher, which gets
  /// four times the free tokens. Only OpenAI routes use it.
  final bool highUsageTier;

  /// Whether the provider's API reports its free quota: OpenRouter's key
  /// endpoint and the headers of Groq's replies do.
  bool get reportsFreeQuota =>
      provider == AiProviderType.openRouter || provider == AiProviderType.groq;

  /// Whether each model has its own free quota, like Groq's. OpenRouter's
  /// covers every free model on the account.
  bool get quotaIsPerModel => provider == AiProviderType.groq;

  QuotaRoute copyWith({
    String? model,
    int? userLimit,
    bool clearUserLimit = false,
    bool? enabled,
    bool? highUsageTier,
  }) => QuotaRoute(
    id: id,
    provider: provider,
    model: model ?? this.model,
    unit: unit,
    userLimit: clearUserLimit ? null : userLimit ?? this.userLimit,
    enabled: enabled ?? this.enabled,
    highUsageTier: highUsageTier ?? this.highUsageTier,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'provider': provider.name,
    'model': model,
    'unit': unit.name,
    'userLimit': userLimit,
    'enabled': enabled,
    'highUsageTier': highUsageTier,
  };

  factory QuotaRoute.fromJson(Map<String, Object?> json) {
    final provider = AiProviderType.values.asNameMap()[json['provider']];
    final unit = QuotaUnit.values.asNameMap()[json['unit']];
    if (provider == null || unit == null) {
      throw const FormatException('Invalid quota route');
    }
    var model = json['model'] as String;
    // Routes saved before the free quota came from the APIs have a
    // `dailyLimit`. For OpenRouter and Groq it only stood in for the free
    // quota, so it's dropped. OpenAI reports no quota, so its limit is kept.
    var userLimit = json.containsKey('userLimit')
        ? json['userLimit'] as int?
        : provider == AiProviderType.openAi
        ? json['dailyLimit'] as int?
        : null;
    final highUsageTier = json['highUsageTier'] as bool? ?? false;
    // OpenAI routes use the models offered with free tokens. Any other, like
    // gpt-4o-mini, moves to the small group's model, and a limit that
    // doesn't fit under its group's allowance goes back to the suggested one.
    if (provider == AiProviderType.openAi) {
      var tier = OpenAiFreeTier.of(model);
      if (tier == null) {
        tier = OpenAiFreeTier.small;
        model = tier.models.first;
      }
      if (userLimit != null &&
          userLimit >= tier.tokensPerDay(highUsageTier: highUsageTier)) {
        userLimit = tier.suggestedLimit(highUsageTier: highUsageTier);
      }
    }
    return QuotaRoute(
      id: json['id'] as String,
      provider: provider,
      model: model,
      unit: unit,
      userLimit: userLimit,
      enabled: json['enabled'] as bool? ?? true,
      highUsageTier: highUsageTier,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuotaRoute &&
      other.id == id &&
      other.provider == provider &&
      other.model == model &&
      other.unit == unit &&
      other.userLimit == userLimit &&
      other.enabled == enabled &&
      other.highUsageTier == highUsageTier;

  @override
  int get hashCode =>
      Object.hash(id, provider, model, unit, userLimit, enabled, highUsageTier);

  @override
  String toString() =>
      'QuotaRoute($id, ${provider.name}, $model, limit: $userLimit, '
      'enabled: $enabled, highUsageTier: $highUsageTier)';
}
