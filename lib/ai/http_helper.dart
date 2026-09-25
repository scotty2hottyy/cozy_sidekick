import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  _checkStatus(response);

  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Report a provider-safe parsing error below.
  }
  throw const BadResponseException('Response was not a JSON object');
}

/// Posts [body] like [postJson] to an API that streams its reply as
/// server-sent events, and returns each event's data, decoded from JSON.
///
/// The stream ends at `data: [DONE]`. Keep-alive comments like
/// `: OPENROUTER PROCESSING` and fields other than `data:` are skipped.
/// [timeout] is the longest wait for the reply to start and between two
/// lines, not for the whole reply, since long replies can take minutes.
Stream<Map<String, dynamic>> postEventStream(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
  Duration timeout = const Duration(seconds: 60),
}) async* {
  final request = http.Request('POST', url)
    ..headers.addAll(<String, String>{
      'Content-Type': 'application/json',
      ...headers,
    })
    ..body = jsonEncode(body);
  try {
    final response = await client.send(request).timeout(timeout);
    final code = response.statusCode;
    if (code < 200 || code >= 300) {
      // Errors arrive before any events, with a normal JSON body.
      _checkStatus(await http.Response.fromStream(response).timeout(timeout));
    }
    // Decoding as a stream puts back together a line or a character that
    // arrives split between two pieces.
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(timeout);
    // An event's data can span several lines, and a blank line ends it.
    final data = <String>[];
    await for (final line in lines) {
      if (line.startsWith('data:')) {
        data.add(line.substring('data:'.length));
      } else if (line.isEmpty && data.isNotEmpty) {
        final event = data.join('\n').trim();
        data.clear();
        if (event == '[DONE]') return;
        yield _decodeEvent(event);
      }
    }
  } on TimeoutException {
    throw const ProviderTimeoutException();
  } on http.ClientException {
    throw const NetworkException();
  } on IOException {
    // http passes on a SocketException from a connection that drops
    // mid-reply as it is.
    throw const NetworkException();
  } on FormatException {
    throw const BadResponseException('An event was not JSON or not UTF-8');
  }
}

Map<String, dynamic> _decodeEvent(String data) {
  final decoded = jsonDecode(data);
  if (decoded is Map<String, dynamic>) return decoded;
  throw const BadResponseException('An event was not a JSON object');
}

/// Throws the [AiProviderException] for [response]'s status code, unless
/// it's a success.
void _checkStatus(http.Response response) {
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
