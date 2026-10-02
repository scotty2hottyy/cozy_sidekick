import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';

/// Posts [body] as JSON and returns the JSON object in the reply.
/// [onHeaders] gets the headers of a successful reply.
Future<Map<String, dynamic>> postJson(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
  Future<void>? abortTrigger,
  Duration timeout = const Duration(seconds: 60),
  void Function(Map<String, String> headers)? onHeaders,
}) => _requestJson(
  headers,
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

    final request =
        http.AbortableRequest('POST', url, abortTrigger: abortTrigger)
          ..headers.addAll(<String, String>{
            'Content-Type': 'application/json',
            ...headers,
          })
          ..body = jsonEncode(body);

    return client.send(request).then(http.Response.fromStream);
  },
  timeout,
  onHeaders,
);

/// Gets [url] and returns its JSON object, with the same errors as
/// [postJson].
Future<Map<String, dynamic>> getJson(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  Duration timeout = const Duration(seconds: 60),
}) => _requestJson(headers, () => client.get(url, headers: headers), timeout);

/// Checks [headers], then sends the request that [send] builds with them.
Future<Map<String, dynamic>> _requestJson(
  Map<String, String> headers,
  Future<http.Response> Function() send,
  Duration timeout, [
  void Function(Map<String, String> headers)? onHeaders,
]) async {
  _checkHeaderValues(headers);

  final http.Response response;
  try {
    response = await send().timeout(timeout);
  } on TimeoutException {
    throw const ProviderTimeoutException();
  } on http.ClientException {
    throw const NetworkException();
  } on IOException {
    // http passes on a HandshakeException, or a SocketException from a
    // connection that drops mid-reply, as it is.
    throw const NetworkException();
  }

  _checkStatus(response);
  onHeaders?.call(response.headers);

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
/// [onHeaders] gets the headers of a successful reply, before its events.
Stream<Map<String, dynamic>> postEventStream(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
  Future<void>? abortTrigger,
  Duration timeout = const Duration(seconds: 60),
  void Function(Map<String, String> headers)? onHeaders,
}) async* {
  _checkHeaderValues(headers);

  final request = http.AbortableRequest('POST', url, abortTrigger: abortTrigger)
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

    onHeaders?.call(response.headers);

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

/// Throws [InvalidApiKeyException] when a value in [headers] has a
/// character that an HTTP header can't hold.
///
/// dart:io would throw a FormatException that holds the whole value, key
/// and all. The app's own headers are plain ASCII, so only a key or token
/// pasted with something like a zero-width space fails here.
void _checkHeaderValues(Map<String, String> headers) {
  for (final value in headers.values) {
    for (final unit in value.codeUnits) {
      // Printable ASCII, or a tab.
      if ((unit < 0x20 || unit > 0x7e) && unit != 0x09) {
        throw const InvalidApiKeyException();
      }
    }
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

  if (code == 400 || code == 403 || code == 404) {
    final modelError = _modelNotAvailable(response);
    if (modelError != null) throw modelError;
  }

  if (code == 400 && _isContextTooLong(_errorObject(response))) {
    throw const RequestTooLargeException('HTTP 400 context_length_exceeded');
  }

  if (code == 401 || code == 403) {
    throw const InvalidApiKeyException();
  }

  // OpenRouter, when the account has no credit for a paid model.
  if (code == 402) {
    throw const OutOfCreditException();
  }

  if (code == 413) {
    throw const RequestTooLargeException();
  }

  if (code == 429) {
    final outOfCredit = _outOfCredit(response);
    if (outOfCredit != null) throw outOfCredit;
    throw RateLimitException(retryAt: _retryAt(response));
  }

  if (code >= 500) {
    throw const ProviderUnavailableException();
  }

  if (code < 200 || code >= 300) {
    throw BadResponseException('HTTP $code');
  }
}

/// When a 429 [response] says to try again, or null when it doesn't say or
/// the time has passed.
///
/// `Retry-After` is seconds or an HTTP date. OpenRouter sends it when the
/// provider behind a model gives a hint, and for its own limits it sends
/// `X-RateLimit-Reset`, as a header or in the error's `metadata.headers`.
DateTime? _retryAt(http.Response response) {
  final now = DateTime.now().toUtc();
  final headers = response.headers;
  DateTime? retryAt;

  final retryAfter = headers['retry-after']?.trim();
  if (retryAfter != null) {
    final seconds = double.tryParse(retryAfter);
    if (seconds != null) {
      retryAt = now.add(Duration(milliseconds: (seconds * 1000).round()));
    } else {
      try {
        retryAt = HttpDate.parse(retryAfter).toUtc();
      } on FormatException {
        // Try the reset time below.
      }
    }
  }

  retryAt ??= _resetTime(
    headers['x-ratelimit-reset'] ?? _openRouterResetInBody(response.body),
    now,
  );
  return retryAt != null && retryAt.isAfter(now) ? retryAt : null;
}

/// A rate limit's reset [value]: a time since the epoch in milliseconds or
/// seconds, or else seconds from [now]. OpenRouter doesn't say which it
/// sends, and has sent milliseconds.
DateTime? _resetTime(String? value, DateTime now) {
  final number = num.tryParse(value?.trim() ?? '');
  if (number == null || number <= 0) return null;
  if (number >= 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(number.round(), isUtc: true);
  }
  if (number >= 1000000000) {
    return DateTime.fromMillisecondsSinceEpoch(
      (number * 1000).round(),
      isUtc: true,
    );
  }
  return now.add(Duration(milliseconds: (number * 1000).round()));
}

/// The `X-RateLimit-Reset` OpenRouter can put in a 429's
/// `error.metadata.headers`, or null.
String? _openRouterResetInBody(String body) {
  try {
    final decoded = jsonDecode(body);
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
    final metadata = error is Map<String, dynamic> ? error['metadata'] : null;
    final headers = metadata is Map<String, dynamic>
        ? metadata['headers']
        : null;
    if (headers is! Map<String, dynamic>) return null;
    for (final MapEntry(:key, :value) in headers.entries) {
      if (key.toLowerCase() == 'x-ratelimit-reset') return '$value';
    }
  } on FormatException {
    // Not JSON, so there's no reset time in it.
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
ModelNotAvailableException? _modelNotAvailable(http.Response response) {
  final status = response.statusCode;
  final error = _errorObject(response);

  if (error == null) return null;

  final code = error['code'];
  final message = error['message'];

  final isModelError = switch (code) {
    'model_not_found' || 'model_decommissioned' => true,
    400 => message is String && message.contains('not a valid model ID'),
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

  return null;
}

/// The error for a 429 [response] that says the account is out of credit,
/// or null for one that only asks to slow down.
///
/// OpenAI sends `"code": "insufficient_quota"` or `credit_balance_exhausted`
/// when the account has no prepaid credit or has reached its spend limit,
/// and its `type` can be `insufficient_quota` too. Trying again won't help.
OutOfCreditException? _outOfCredit(http.Response response) {
  final error = _errorObject(response);
  final code = error?['code'];

  if (code == 'insufficient_quota' ||
      code == 'credit_balance_exhausted' ||
      error?['type'] == 'insufficient_quota') {
    return OutOfCreditException(
      'HTTP 429 ${code is String ? code : 'insufficient_quota'}',
    );
  }

  return null;
}

/// Whether a 400's [error] says the chat is longer than the model can read.
///
/// OpenAI and Groq send `"code": "context_length_exceeded"`. OpenRouter's
/// codes are numbers, so it puts that in `metadata.error_type`, or says
/// "maximum context length" in the message, like OpenAI's.
bool _isContextTooLong(Map<String, dynamic>? error) {
  if (error == null) return false;

  final code = error['code'];
  final metadata = error['metadata'];
  final errorType = metadata is Map<String, dynamic>
      ? metadata['error_type']
      : null;

  if (code is String || errorType is String) {
    return code == 'context_length_exceeded' ||
        errorType == 'context_length_exceeded';
  }

  // Without either, only the message says what went wrong.
  final message = error['message'];
  return message is String && message.contains('maximum context length');
}

/// The `error` object in [response]'s JSON body, or null when it has none.
Map<String, dynamic>? _errorObject(http.Response response) {
  try {
    final decoded = jsonDecode(response.body);
    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;

    return error is Map<String, dynamic> ? error : null;
  } on FormatException {
    // Not JSON, so it has no error object.
    return null;
  }
}
