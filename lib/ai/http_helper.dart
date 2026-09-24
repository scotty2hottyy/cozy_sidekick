import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';

Future<Map<String, dynamic>> postJson(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final http.Response response;
  try {
    response = await client
        .post(
          url,
          headers: <String, String>{
            'Content-Type': 'application/json',
            ...headers,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
  } on TimeoutException {
    throw const ProviderTimeoutException();
  } on http.ClientException {
    throw const NetworkException();
  }

  final code = response.statusCode;
  if (code == 401 || code == 403) throw const InvalidApiKeyException();
  if (code == 429) throw const RateLimitException();
  if (code >= 500) throw const ProviderUnavailableException();
  if (code < 200 || code >= 300) {
    throw BadResponseException('HTTP $code');
  }

  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Report a provider-safe parsing error below.
  }
  throw const BadResponseException('Response was not a JSON object');
}
