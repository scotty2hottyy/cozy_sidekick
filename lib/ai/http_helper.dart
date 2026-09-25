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
  if (code == 403 || code == 404) {
    final modelError = _modelNotAvailable(response);
    if (modelError != null) throw modelError;
  }
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

/// OpenAI sends `model_not_found` as a 403 when the project's model allowlist
/// blocks the model, and as a 404 when the model ID is unknown. Other
/// providers send other bodies, or none, so anything else returns null.
ModelNotAvailableException? _modelNotAvailable(http.Response response) {
  try {
    final decoded = jsonDecode(response.body);
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
    if (error is Map<String, dynamic> && error['code'] == 'model_not_found') {
      // OpenAI's message names the model and project, which helps in logs.
      final message = error['message'];
      return ModelNotAvailableException(
        'HTTP ${response.statusCode} model_not_found'
        '${message is String ? ': $message' : ''}',
      );
    }
  } on FormatException {
    // Not JSON, so it isn't a model error.
  }
  return null;
}
