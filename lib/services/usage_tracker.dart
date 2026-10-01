import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_provider.dart';
import '../models/free_quota.dart';
import '../models/openai_free_tier.dart';
import '../models/quota_route.dart';

/// The last free quota a provider reported for a route today.
class QuotaReading {
  const QuotaReading({
    required this.model,
    required this.quota,
    required this.checkedAt,
    required this.requestsAtCheck,
  });

  /// The model it was read for. Groq's quota is per model, so a reading for
  /// another Groq model doesn't count.
  final String model;
  final FreeQuota quota;
  final DateTime checkedAt;

  /// This app's requests on the route today when it was read, counted like
  /// [RouteUsage.requestsFor], so requests since then can be added to it.
  final int requestsAtCheck;

  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'limit': quota.limit,
    'remaining': quota.remaining,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'requestsAtCheck': requestsAtCheck,
  };

  static QuotaReading? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final model = json['model'];
    final limit = json['limit'];
    final remaining = json['remaining'];
    final checkedAt = json['checkedAt'] is String
        ? DateTime.tryParse(json['checkedAt'] as String)
        : null;
    final requestsAtCheck = json['requestsAtCheck'];
    if (model is! String ||
        limit is! int ||
        remaining is! int ||
        checkedAt == null ||
        requestsAtCheck is! int) {
      return null;
    }
    return QuotaReading(
      model: model,
      quota: FreeQuota(limit: limit, remaining: remaining),
      checkedAt: checkedAt,
      requestsAtCheck: requestsAtCheck,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuotaReading &&
      other.model == model &&
      other.quota == quota &&
      other.checkedAt == checkedAt &&
      other.requestsAtCheck == requestsAtCheck;

  @override
  int get hashCode => Object.hash(model, quota, checkedAt, requestsAtCheck);
}

class RouteUsage {
  const RouteUsage({
    this.requests = 0,
    this.modelRequests = const <String, int>{},
    this.tokens = 0,
    this.blockedUntil,
    this.reading,
  });

  /// This app's requests and tokens on the route today.
  final int requests;
  final int tokens;
  final DateTime? blockedUntil;

  /// This app's requests today for each model of a route whose quota is per
  /// model, like Groq's.
  final Map<String, int> modelRequests;

  /// This app's requests today that count toward [route]'s quota: only its
  /// model's on Groq, since each model has its own quota, and otherwise all
  /// of them.
  int requestsFor(QuotaRoute route) =>
      route.quotaIsPerModel ? modelRequests[route.model] ?? 0 : requests;

  /// The provider's own count, when it reported one today.
  final QuotaReading? reading;

  /// [reading], when it counts for [route]: always for OpenRouter, whose
  /// quota covers the whole account, and only for the same model on Groq.
  QuotaReading? readingFor(QuotaRoute route) =>
      !route.quotaIsPerModel || reading?.model == route.model ? reading : null;

  /// The provider's free quota per day for [route], in its unit, or null
  /// when it isn't known today. OpenRouter and Groq report theirs, and
  /// OpenAI's is a fixed allowance for each model group.
  int? freeQuotaFor(QuotaRoute route) => route.provider == AiProviderType.openAi
      ? OpenAiFreeTier.of(route.model)
            ?.tokensPerDay(highUsageTier: route.highUsageTier)
      : readingFor(route)?.quota.limit;

  /// The most [route] can use today: the user's limit when it's less than
  /// the free quota, and otherwise the free quota. Null when neither is
  /// known, so only the provider's 429s stop it.
  int? limitFor(QuotaRoute route) {
    final quota = freeQuotaFor(route);
    final userLimit = route.userLimit;
    if (userLimit != null && (quota == null || userLimit < quota)) {
      return userLimit;
    }
    return quota;
  }

  /// What [route] has used today, in its unit. When the provider reported a
  /// count, it's that count plus this app's requests since, because it
  /// includes other apps using the same key.
  int usedFor(QuotaRoute route) {
    if (route.unit == QuotaUnit.tokens) return tokens;
    final requests = requestsFor(route);
    final reading = readingFor(route);
    if (reading == null) return requests;
    final used =
        reading.quota.used + max<int>(0, requests - reading.requestsAtCheck);
    // OpenRouter's count covers this app's requests today, so this app's
    // count is the least it can be. Groq's refills over the day, so it can
    // be less than this app's requests.
    return route.quotaIsPerModel ? used : max(requests, used);
  }

  /// What's left of [route]'s limit today, or null when it has no limit.
  int? leftFor(QuotaRoute route) {
    final limit = limitFor(route);
    return limit == null ? null : max(0, limit - usedFor(route));
  }

  bool isUsedUp(QuotaRoute route) {
    final limit = limitFor(route);
    return limit != null && usedFor(route) >= limit;
  }

  bool isBlocked(DateTime now) => blockedUntil?.isAfter(now) ?? false;

  /// Whether a 429 has [route] waiting a short while, until before midnight
  /// UTC, rather than being used up for the day.
  bool isBusy(QuotaRoute route, DateTime now) {
    final nowUtc = now.toUtc();
    final midnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);
    return isBlocked(nowUtc) &&
        !isUsedUp(route) &&
        blockedUntil!.isBefore(midnight);
  }

  /// When [route] can be used again, or null when it can be used [now]. A
  /// used-up route waits for midnight UTC, even when a shorter block from
  /// a 429 also applies.
  DateTime? resetFor(QuotaRoute route, DateTime now) {
    final nowUtc = now.toUtc();
    final blocked = isBlocked(nowUtc);
    if (!isUsedUp(route)) return blocked ? blockedUntil : null;
    final midnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);
    return blocked && blockedUntil!.isAfter(midnight) ? blockedUntil : midnight;
  }

  @override
  bool operator ==(Object other) =>
      other is RouteUsage &&
      other.requests == requests &&
      mapEquals(other.modelRequests, modelRequests) &&
      other.tokens == tokens &&
      other.blockedUntil == blockedUntil &&
      other.reading == reading;

  @override
  int get hashCode => Object.hash(
    requests,
    Object.hashAllUnordered(
      modelRequests.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    tokens,
    blockedUntil,
    reading,
  );
}

class UsageTracker {
  UsageTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const String _usageKey = 'ai.usage';
  static const String _lastQuotasKey = 'ai.last_free_quotas';
  final DateTime Function() _now;

  Future<RouteUsage> usageFor(QuotaRoute route) async {
    final routes = await _loadRoutes();
    return _usageIn(routes, route);
  }

  /// [route]'s free quota per day: the one reported today, or OpenAI's
  /// allowance, or else the last one reported on an earlier day. Null when
  /// the provider has never reported one for it.
  ///
  /// Groq reports its quota only with a reply, so on days it hasn't answered
  /// yet, the last one it reported is the best guess of the maximum a user
  /// can set.
  Future<int?> knownFreeQuota(QuotaRoute route) async {
    final today = (await usageFor(route)).freeQuotaFor(route);
    if (today != null || !route.reportsFreeQuota) return today;
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_lastQuotasKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      final limit = decoded is Map<String, dynamic>
          ? decoded[_quotaScope(route)]
          : null;
      return limit is int ? limit : null;
    } on FormatException {
      return null;
    }
  }

  Future<bool> isUsedUpOrBlocked(QuotaRoute route) async {
    final usage = await usageFor(route);
    return usage.isBlocked(_now().toUtc()) || usage.isUsedUp(route);
  }

  /// Counts one request on [route], with its [tokens], and saves the free
  /// [quota] the reply reported, which already counts this request.
  Future<void> record(QuotaRoute route, {int? tokens, FreeQuota? quota}) async {
    final routes = await _loadRoutes();
    final previous = _usageIn(routes, route);
    final usage = RouteUsage(
      requests: previous.requests + 1,
      modelRequests: route.quotaIsPerModel
          ? <String, int>{
              ...previous.modelRequests,
              route.model: (previous.modelRequests[route.model] ?? 0) + 1,
            }
          : previous.modelRequests,
      tokens: previous.tokens + (tokens ?? 0),
      blockedUntil: previous.blockedUntil,
      reading: previous.reading,
    );
    routes[route.id] = _encodeUsage(
      quota == null
          ? usage
          : _withReading(
              usage,
              _reading(route, quota, requestsAtCheck: usage.requestsFor(route)),
            ),
    );
    await _saveRoutes(routes);
    if (quota != null) await _saveLastQuota(route, quota);
  }

  /// Saves the free [quota] the provider reported for [route] outside a
  /// reply, like OpenRouter's key endpoint.
  Future<void> report(QuotaRoute route, FreeQuota quota) async {
    final routes = await _loadRoutes();
    final previous = _usageIn(routes, route);
    routes[route.id] = _encodeUsage(
      _withReading(
        previous,
        _reading(route, quota, requestsAtCheck: previous.requestsFor(route)),
      ),
    );
    await _saveRoutes(routes);
    await _saveLastQuota(route, quota);
  }

  Future<void> block(QuotaRoute route, {required DateTime until}) async {
    final routes = await _loadRoutes();
    final previous = _usageIn(routes, route);
    routes[route.id] = _encodeUsage(
      RouteUsage(
        requests: previous.requests,
        modelRequests: previous.modelRequests,
        tokens: previous.tokens,
        blockedUntil: until.toUtc(),
        reading: previous.reading,
      ),
    );
    await _saveRoutes(routes);
  }

  static RouteUsage _withReading(RouteUsage usage, QuotaReading reading) =>
      RouteUsage(
        requests: usage.requests,
        modelRequests: usage.modelRequests,
        tokens: usage.tokens,
        blockedUntil: usage.blockedUntil,
        reading: reading,
      );

  /// Remembers [quota]'s limit past today, for [knownFreeQuota].
  Future<void> _saveLastQuota(QuotaRoute route, FreeQuota quota) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_lastQuotasKey);
    var limits = <String, Object?>{};
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) limits = decoded;
      } on FormatException {
        // A damaged value is replaced.
      }
    }
    limits[_quotaScope(route)] = quota.limit;
    await prefs.setString(_lastQuotasKey, jsonEncode(limits));
  }

  /// Where [route]'s quota is kept: per model for Groq, and per provider for
  /// OpenRouter, whose quota covers every free model.
  static String _quotaScope(QuotaRoute route) => route.quotaIsPerModel
      ? '${route.provider.name}/${route.model}'
      : route.provider.name;

  QuotaReading _reading(
    QuotaRoute route,
    FreeQuota quota, {
    required int requestsAtCheck,
  }) => QuotaReading(
    model: route.model,
    quota: quota,
    checkedAt: _now().toUtc(),
    requestsAtCheck: requestsAtCheck,
  );

  Future<Map<String, Object?>> _loadRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_usageKey);
    if (encoded == null) return <String, Object?>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['day'] != _today ||
          decoded['routes'] is! Map<String, dynamic>) {
        return <String, Object?>{};
      }
      return Map<String, Object?>.of(decoded['routes'] as Map<String, dynamic>);
    } on Object {
      return <String, Object?>{};
    }
  }

  Future<void> _saveRoutes(Map<String, Object?> routes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usageKey,
      jsonEncode(<String, Object?>{'day': _today, 'routes': routes}),
    );
  }

  String get _today => _now().toUtc().toIso8601String().substring(0, 10);

  static RouteUsage _usageIn(Map<String, Object?> routes, QuotaRoute route) {
    final value = routes[route.id];
    return value is Map<String, dynamic>
        ? _decodeUsage(value)
        : const RouteUsage();
  }

  static Map<String, Object?> _encodeUsage(RouteUsage usage) =>
      <String, Object?>{
        'requests': usage.requests,
        'modelRequests': usage.modelRequests,
        'tokens': usage.tokens,
        'blockedUntil': usage.blockedUntil?.toIso8601String(),
        'reading': usage.reading?.toJson(),
      };

  static RouteUsage _decodeUsage(Map<String, dynamic> value) => RouteUsage(
    requests: value['requests'] as int? ?? 0,
    modelRequests: <String, int>{
      if (value['modelRequests'] case final Map<String, dynamic> counts)
        for (final MapEntry(:key, :value) in counts.entries)
          if (value is int) key: value,
    },
    tokens: value['tokens'] as int? ?? 0,
    blockedUntil: value['blockedUntil'] is String
        ? DateTime.tryParse(value['blockedUntil'] as String)
        : null,
    reading: QuotaReading.fromJson(value['reading']),
  );
}
