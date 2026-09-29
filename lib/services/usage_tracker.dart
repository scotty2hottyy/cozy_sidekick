import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/quota_route.dart';

class RouteUsage {
  const RouteUsage({this.requests = 0, this.tokens = 0, this.blockedUntil});

  final int requests;
  final int tokens;
  final DateTime? blockedUntil;

  int get used => requests;

  int usedFor(QuotaRoute route) =>
      route.unit == QuotaUnit.requests ? requests : tokens;

  @override
  bool operator ==(Object other) =>
      other is RouteUsage &&
      other.requests == requests &&
      other.tokens == tokens &&
      other.blockedUntil == blockedUntil;

  @override
  int get hashCode => Object.hash(requests, tokens, blockedUntil);
}

class UsageTracker {
  UsageTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const String _usageKey = 'ai.usage';
  final DateTime Function() _now;

  Future<RouteUsage> usageFor(QuotaRoute route) async {
    final routes = await _loadRoutes();
    final value = routes[route.id];
    if (value is! Map<String, dynamic>) return const RouteUsage();
    return _decodeUsage(value);
  }

  Future<bool> isUsedUpOrBlocked(QuotaRoute route) async {
    final usage = await usageFor(route);
    return (usage.blockedUntil?.isAfter(_now().toUtc()) ?? false) ||
        (route.dailyLimit != null && usage.usedFor(route) >= route.dailyLimit!);
  }

  Future<void> record(QuotaRoute route, {int? tokens}) async {
    final routes = await _loadRoutes();
    final previous = routes[route.id] is Map<String, dynamic>
        ? _decodeUsage(routes[route.id]! as Map<String, dynamic>)
        : const RouteUsage();
    routes[route.id] = <String, Object?>{
      'requests': previous.requests + 1,
      'tokens': previous.tokens + (tokens ?? 0),
      'blockedUntil': previous.blockedUntil?.toIso8601String(),
    };
    await _saveRoutes(routes);
  }

  Future<void> block(QuotaRoute route, {required DateTime until}) async {
    final routes = await _loadRoutes();
    final previous = routes[route.id] is Map<String, dynamic>
        ? _decodeUsage(routes[route.id]! as Map<String, dynamic>)
        : const RouteUsage();
    routes[route.id] = <String, Object?>{
      'requests': previous.requests,
      'tokens': previous.tokens,
      'blockedUntil': until.toUtc().toIso8601String(),
    };
    await _saveRoutes(routes);
  }

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

  static RouteUsage _decodeUsage(Map<String, dynamic> value) => RouteUsage(
    requests: value['requests'] as int? ?? 0,
    tokens: value['tokens'] as int? ?? 0,
    blockedUntil: value['blockedUntil'] is String
        ? DateTime.tryParse(value['blockedUntil'] as String)
        : null,
  );
}
