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
  Future<void>? abortTrigger,
  Duration timeout = const Duration(seconds: 60),
}) =>
    _requestJson(
      () {
        if (abortTrigger == null) {
          return client.post(
            url,
            headers: <String, String>{
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          );
        }

        final request = http.AbortableRequest(
          'POST',
          url,
          abortTrigger: abortTrigger,
        )
          ..headers.addAll(<String, String>{
            'Content-Type': 'application/json',
            ...headers,
          })
          ..body = jsonEncode(body);

        return client.send(request).then(http.Response.fromStream);
      },
      timeout,
    );

/// Gets [url] and returns its JSON object, with the same errors as
/// [postJson].
Future<Map<String, dynamic>> getJson(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  Duration timeout = const Duration(seconds: 60),
}) =>
    _requestJson(() => client.get(url, headers: headers), timeout);

Future<Map<String, dynamic>> _requestJson(
  Future<http.Response> Function() send,
  Duration timeout,
) async {
  final http.Response response;
  try {
    response = await send().timeout(timeout);
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
  Future<void>? abortTrigger,
  Duration timeout = const Duration(seconds: 60),
}) async* {
  final request = http.AbortableRequest(
    'POST',
    url,
    abortTrigger: abortTrigger,
  )
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
      _checkStatus(
        await http.Response.fromStream(response).timeout(timeout),
      );
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
    throw const BadResponseException(
      'An event was not JSON or not UTF-8',
    );
  }
}

Map<String, dynamic> _decodeEvent(String data) {
  final decoded = jsonDecode(data);

  if (decoded is Map<String, dynamic>) return decoded;

  throw const BadResponseException(
    'An event was not a JSON object',
  );
}

/// Throws the [AiProviderException] for [response]'s status code, unless
/// it's a success.
void _checkStatus(http.Response response) {
  final code = response.statusCode;

  if (code == 400 || code == 403 || code == 404) {
    final modelError = _modelNotAvailable(response);
    if (modelError != null) throw modelError;
  }

  if (code == 401 || code == 403) {
    throw const InvalidApiKeyException();
  }

  if (code == 429) {
    throw RateLimitException(retryAt: _retryAt(response.headers));
  }

  if (code >= 500) {
    throw const ProviderUnavailableException();
  }

  if (code < 200 || code >= 300) {
    throw BadResponseException('HTTP $code');
  }
}

DateTime? _retryAt(Map<String, String> headers) {
  final retryAfter = headers['retry-after'];
  if (retryAfter != null) {
    final seconds = int.tryParse(retryAfter.trim());
    if (seconds != null) {
      return DateTime.now().toUtc().add(Duration(seconds: seconds));
    }
    try {
      return HttpDate.parse(retryAfter).toUtc();
    } on FormatException {
      // Try the provider-specific reset header below.
    }
  }

  final resetSeconds = int.tryParse(headers['x-ratelimit-reset'] ?? '');
  if (resetSeconds != null && resetSeconds > 0) {
    return DateTime.fromMillisecondsSinceEpoch(
      resetSeconds * 1000,
      isUtc: true,
    );
  }
  return null;
}

/// The error for a response that says the model can't be used, or null for
/// any other response.
///
/// - OpenAI and Groq send `"code": "model_not_found"`. OpenAI sends it as a
///   403 when the project's model allowlist blocks the model, and both send
///   it as a 404 when the model ID is unknown. Groq sends
///   `model_decommissioned` as a 400 for a model it has retired.
/// - OpenRouter's codes are numbers. It sends a 400 saying the ID "is not a
///   valid model ID", and a 404 when the model doesn't exist or has no
///   endpoint the account can use, for example because of its privacy
///   settings.
ModelNotAvailableException? _modelNotAvailable(
  http.Response response,
) {
  final status = response.statusCode;

  try {
    final decoded = jsonDecode(response.body);
    final error =
        decoded is Map<String, dynamic> ? decoded['error'] : null;

    if (error is! Map<String, dynamic>) return null;

    final code = error['code'];
    final message = error['message'];

    final isModelError = switch (code) {
      'model_not_found' || 'model_decommissioned' => true,
      400 =>
        message is String &&
            message.contains('not a valid model ID'),
      404 => status == 404,
      _ => false,
    };

    if (isModelError) {
      // The message names the model (and OpenAI's the project), which helps
      // in logs.
      return ModelNotAvailableException(
        'HTTP $status${code is String ? ' $code' : ''}'
        '${message is String ? ': $message' : ''}',
      );
    }
  } on FormatException {
    // Not JSON, so it isn't a model error.
  }

  return null;
}