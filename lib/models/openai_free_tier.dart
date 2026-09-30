/// OpenAI's free daily tokens for organizations that share their prompts and
/// replies with OpenAI, from
/// https://help.openai.com/en/articles/10306912-sharing-feedback-evaluation-and-fine-tuning-data-and-api-inputs-and-outputs-with-openai
///
/// The article puts models in two groups, and the models in a group share
/// one allowance, which resets at 00:00 UTC. Each group's two newest models
/// came out the same day, and only the more capable one is offered:
/// gpt-6-sol rather than gpt-6-luna, and gpt-5.6-terra rather than
/// gpt-5.6-luna. Checked 2026-09-30, when the article was last updated
/// 2026-09-23. Update the models here when the article adds newer ones.
///
/// [dailyTokens] is the allowance for usage tiers 1–2. Tiers 3–5 get four
/// times as much, but no API reports an account's tier, so the user says
/// whether theirs is 3 or higher.
enum OpenAiFreeTier {
  large('Large models', dailyTokens: 250000, models: <String>['gpt-6-sol']),
  small(
    'Small models',
    dailyTokens: 2500000,
    models: <String>['gpt-5.6-terra'],
  );

  const OpenAiFreeTier(
    this.displayName, {
    required this.dailyTokens,
    required this.models,
  });

  final String displayName;

  /// The free tokens per day for usage tiers 1–2, shared by every model in
  /// the group.
  final int dailyTokens;

  /// The models offered from the group.
  final List<String> models;

  /// How many times [dailyTokens] usage tiers 3–5 get.
  static const int highUsageTierMultiplier = 4;

  /// The free tokens per day, for usage tier 3 or higher when
  /// [highUsageTier] is true.
  int tokensPerDay({required bool highUsageTier}) =>
      highUsageTier ? dailyTokens * highUsageTierMultiplier : dailyTokens;

  /// The limit a route starts with: 90% of [tokensPerDay], which leaves room
  /// for use the app can't see, like other apps on the same account. OpenAI
  /// bills the whole request that crosses the allowance.
  int suggestedLimit({required bool highUsageTier}) =>
      tokensPerDay(highUsageTier: highUsageTier) * 9 ~/ 10;

  /// Every model offered, in the order shown.
  static List<String> get allModels => <String>[
    for (final tier in values) ...tier.models,
  ];

  /// The group [model] is in, or null when it isn't offered.
  static OpenAiFreeTier? of(String model) {
    for (final tier in values) {
      if (tier.models.contains(model)) return tier;
    }
    return null;
  }
}
