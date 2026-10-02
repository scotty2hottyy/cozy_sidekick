import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/http_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('stream request carries an abort signal and cancellation ends a waiting stream', () async {
    final abort = Completer<void>();
    final started = Completer<void>();
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((request, _) async {
      expect(request, isA<http.AbortableRequest>());
      final trigger = (request as http.AbortableRequest).abortTrigger;
      expect(trigger, same(abort.future));
      trigger!.then((_) {
        body.addError(http.RequestAbortedException());
        body.close();
      });
      started.complete();
      return http.StreamedResponse(body.stream, 200);
    });
    final stream = postEventStream(
      client,
      Uri.parse('https://example.com'),
      headers: {},
      body: {},
      abortTrigger: abort.future,
    );
    final done = expectLater(stream, emitsError(isA<NetworkException>()));
    await started.future;
    abort.complete();
    await done;
    client.close();
  });

  test('returns a decoded JSON object', () async {
    final result = await postJson(
      MockClient((_) async => http.Response('{"ok":true}', 200)),
      Uri.parse('https://example.com'),
      headers: <String, String>{},
      body: <String, Object?>{},
    );
    expect(result['ok'], isTrue);
  });

  for (final entry in <int, Type>{
    401: InvalidApiKeyException,
    403: InvalidApiKeyException,
    429: RateLimitException,
    503: ProviderUnavailableException,
    400: BadResponseException,
  }.entries) {
    test('${entry.key} maps to ${entry.value}', () {
      final future = postJson(
        MockClient((_) async => http.Response('{}', entry.key)),
        Uri.parse('https://example.com'),
        headers: <String, String>{},
        body: <String, Object?>{},
      );
      expect(
        future,
        throwsA(
          isA<AiProviderException>().having(
            (e) => e.runtimeType,
            'type',
            entry.value,
          ),
        ),
      );
    });
  }

  group('a 429 retry time', () {
    /// The retryAt of the RateLimitException for a 429 with [headers] and
    /// [body].
    Future<DateTime?> retryAtFor({
      Map<String, String> headers = const <String, String>{},
      String body = '{}',
    }) async {
      try {
        await postJson(
          MockClient((_) async => http.Response(body, 429, headers: headers)),
          Uri.parse('https://example.com'),
          headers: <String, String>{},
          body: <String, Object?>{},
        );
      } on RateLimitException catch (error) {
        return error.retryAt;
      }
      fail('No RateLimitException');
    }

    Matcher secondsFromNow(double seconds) => predicate<DateTime?>((retryAt) {
      if (retryAt == null) return false;
      final ms = retryAt.difference(DateTime.now().toUtc()).inMilliseconds;
      return (ms - seconds * 1000).abs() < 2000;
    }, '$seconds seconds from now');

    test('reads Retry-After in whole or part seconds', () async {
      expect(
        await retryAtFor(headers: <String, String>{'retry-after': '1.5'}),
        secondsFromNow(1.5),
      );
    });

    test('reads X-RateLimit-Reset in milliseconds or seconds', () async {
      final reset = DateTime.now().toUtc().add(const Duration(minutes: 2));
      final millis = reset.millisecondsSinceEpoch;
      expect(
        await retryAtFor(
          headers: <String, String>{'x-ratelimit-reset': '$millis'},
        ),
        secondsFromNow(120),
      );
      expect(
        await retryAtFor(
          headers: <String, String>{'x-ratelimit-reset': '${millis ~/ 1000}'},
        ),
        secondsFromNow(120),
      );
    });

    test("reads the reset time in OpenRouter's error metadata", () async {
      final reset = DateTime.now().toUtc().add(const Duration(minutes: 2));
      expect(
        await retryAtFor(
          body: jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 429,
              'message': 'Rate limit exceeded: free-models-per-min.',
              'metadata': <String, Object?>{
                'headers': <String, String>{
                  'X-RateLimit-Limit': '20',
                  'X-RateLimit-Remaining': '0',
                  'X-RateLimit-Reset': '${reset.millisecondsSinceEpoch}',
                },
              },
            },
          }),
        ),
        secondsFromNow(120),
      );
    });

    test('is null without a time, or with one that has passed', () async {
      // What OpenRouter sends when a free model is busy upstream.
      expect(
        await retryAtFor(
          body: jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 429,
              'message': 'Provider returned error',
              'metadata': <String, Object?>{
                'raw':
                    'qwen/qwen3.8-27b:free is temporarily rate-limited '
                    'upstream. Please retry shortly.',
                'provider_name': 'Chutes',
              },
            },
          }),
        ),
        isNull,
      );
      expect(
        await retryAtFor(
          headers: <String, String>{
            'x-ratelimit-reset': '${DateTime.utc(2026).millisecondsSinceEpoch}',
          },
        ),
        isNull,
      );
    });
  });

  test('429 Retry-After sets retryAt', () async {
    final startedAt = DateTime.now().toUtc();
    final request = postJson(
      MockClient(
        (_) async => http.Response(
          '{}',
          429,
          headers: <String, String>{'retry-after': '60'},
        ),
      ),
      Uri.parse('https://example.com'),
      headers: <String, String>{},
      body: <String, Object?>{},
    );

    await expectLater(
      request,
      throwsA(
        isA<RateLimitException>().having(
          (error) => error.retryAt,
          'retryAt',
          allOf(
            isNotNull,
            predicate<DateTime>(
              (retryAt) => retryAt.difference(startedAt).inSeconds >= 59,
            ),
          ),
        ),
      ),
    );
  });

  // What OpenAI sends when a project's model allowlist blocks the model.
  const modelNotFound =
      '{"error":{"message":"Project `proj_abc` does not have access to model '
      '`gpt-6-luna`","type":"invalid_request_error","param":null,'
      '"code":"model_not_found"}}';

  for (final code in <int>[403, 404]) {
    test('$code model_not_found maps to ModelNotAvailableException', () {
      expect(
        _post(code, modelNotFound),
        throwsA(
          isA<ModelNotAvailableException>().having(
            (e) => e.debugMessage,
            'debugMessage',
            'HTTP $code model_not_found: Project `proj_abc` does not have '
                'access to model `gpt-6-luna`',
          ),
        ),
      );
    });
  }

  test('model_not_found without a message still maps', () {
    expect(
      _post(404, '{"error":{"code":"model_not_found"}}'),
      throwsA(
        isA<ModelNotAvailableException>().having(
          (e) => e.debugMessage,
          'debugMessage',
          'HTTP 404 model_not_found',
        ),
      ),
    );
  });

  test('other 403 and 404 bodies keep their usual errors', () async {
    for (final body in <String>[
      '',
      '<html>Forbidden</html>',
      '[]',
      'null',
      '{"error":"model_not_found"}',
      '{"error":{"code":403,"message":"Forbidden"}}',
      '{"error":{"code":"invalid_api_key","message":"Incorrect API key"}}',
      '{"code":"model_not_found"}',
    ]) {
      await expectLater(
        _post(403, body),
        throwsA(isA<InvalidApiKeyException>()),
        reason: body,
      );
      await expectLater(
        _post(404, body),
        throwsA(
          isA<BadResponseException>().having(
            (e) => e.debugMessage,
            'debugMessage',
            'HTTP 404',
          ),
        ),
        reason: body,
      );
    }
  });

  test('a 401 is a key problem even with a model_not_found body', () {
    expect(_post(401, modelNotFound), throwsA(isA<InvalidApiKeyException>()));
  });

  test('OpenRouter and Groq model errors map to ModelNotAvailable', () async {
    for (final (code, body) in <(int, String)>[
      // OpenRouter, for an ID it doesn't know.
      (
        400,
        '{"error":{"message":"openai/gpt-9 is not a valid model ID",'
            '"code":400},"user_id":"user_123"}',
      ),
      // OpenRouter, for a model without an endpoint the account can use.
      (
        404,
        '{"error":{"message":"No endpoints found matching your data policy",'
            '"code":404}}',
      ),
      (
        404,
        '{"error":{"code":404,"message":"The requested resource does not '
            'exist","metadata":{"error_type":"not_found"}}}',
      ),
      // Groq, for a model it has retired.
      (
        400,
        '{"error":{"message":"The model `llama3-70b-8192` has been '
            'decommissioned and is no longer supported.",'
            '"type":"invalid_request_error","code":"model_decommissioned"}}',
      ),
    ]) {
      await expectLater(
        _post(code, body),
        throwsA(isA<ModelNotAvailableException>()),
        reason: body,
      );
    }
    await expectLater(
      _post(
        400,
        '{"error":{"message":"x is not a valid model ID","code":400}}',
      ),
      throwsA(
        isA<ModelNotAvailableException>().having(
          (e) => e.debugMessage,
          'debugMessage',
          'HTTP 400: x is not a valid model ID',
        ),
      ),
    );
  });

  test('other 400 bodies are still bad responses', () async {
    for (final body in <String>[
      '',
      '{}',
      '{"error":{"message":"Invalid messages","code":400}}',
      '{"error":{"message":"Not found","code":404}}',
      '{"error":{"message":"Bad","type":"invalid_request_error","code":null}}',
    ]) {
      await expectLater(
        _post(400, body),
        throwsA(
          isA<BadResponseException>().having(
            (e) => e.debugMessage,
            'debugMessage',
            'HTTP 400',
          ),
        ),
        reason: body,
      );
    }
  });

  test('getJson gets a JSON object, with the same errors', () async {
    late http.Request sent;
    final url = Uri.parse('https://example.com/v1/models');
    final json = await getJson(
      MockClient((request) async {
        sent = request;
        return http.Response('{"data":[]}', 200);
      }),
      url,
      headers: <String, String>{'Authorization': 'Bearer key'},
    );
    expect(json, <String, Object?>{'data': <Object?>[]});
    expect(sent.method, 'GET');
    expect(sent.url, url);
    expect(sent.headers['authorization'], 'Bearer key');

    for (final (client, matcher) in <(http.Client, Matcher)>[
      (
        MockClient((_) async => http.Response('{}', 401)),
        isA<InvalidApiKeyException>(),
      ),
      (
        MockClient((_) async => http.Response('nope', 200)),
        isA<BadResponseException>(),
      ),
      (
        MockClient((_) async => throw http.ClientException('offline')),
        isA<NetworkException>(),
      ),
    ]) {
      await expectLater(
        getJson(client, url, headers: <String, String>{}),
        throwsA(matcher),
      );
    }
  });

  test('rejects non-JSON and maps client failures', () async {
    expect(
      postJson(
        MockClient((_) async => http.Response('nope', 200)),
        Uri.parse('https://example.com'),
        headers: <String, String>{},
        body: <String, Object?>{},
      ),
      throwsA(isA<BadResponseException>()),
    );
    expect(
      postJson(
        MockClient((_) async => throw http.ClientException('offline')),
        Uri.parse('https://example.com'),
        headers: <String, String>{},
        body: <String, Object?>{},
      ),
      throwsA(isA<NetworkException>()),
    );
  });

  test('onHeaders gets the headers of a successful reply', () async {
    // Without an abort trigger the request is a plain post, and with one
    // it's sent as a stream.
    for (final abortTrigger in <Future<void>?>[
      null,
      Completer<void>().future,
    ]) {
      Map<String, String>? received;
      await postJson(
        MockClient(
          (_) async => http.Response('{}', 200, headers: _quotaHeaders),
        ),
        Uri.parse('https://example.com'),
        headers: <String, String>{},
        body: <String, Object?>{},
        abortTrigger: abortTrigger,
        onHeaders: (headers) => received = headers,
      );
      expect(received, _quotaHeaders, reason: 'abortTrigger: $abortTrigger');
    }
  });

  test('onHeaders is not called for an error reply', () async {
    for (final code in <int>[400, 401, 429, 500, 503]) {
      var called = false;
      await expectLater(
        postJson(
          MockClient(
            (_) async => http.Response('{}', code, headers: _quotaHeaders),
          ),
          Uri.parse('https://example.com'),
          headers: <String, String>{},
          body: <String, Object?>{},
          onHeaders: (_) => called = true,
        ),
        throwsA(isA<AiProviderException>()),
        reason: '$code',
      );
      expect(called, isFalse, reason: '$code');
    }
  });

  group('postEventStream', () {
    test('onHeaders gets the headers before the first event', () async {
      Map<String, String>? received;
      final headersAtEachEvent = <Map<String, String>?>[];
      await postEventStream(
        MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            _bytes('data: {"n":1}\n\ndata: {"n":2}\n\ndata: [DONE]\n\n'),
            200,
            headers: _quotaHeaders,
          ),
        ),
        Uri.parse('https://example.com'),
        headers: <String, String>{},
        body: <String, Object?>{},
        onHeaders: (headers) => received = headers,
      ).forEach((_) => headersAtEachEvent.add(received));
      expect(headersAtEachEvent, <Map<String, String>>[
        _quotaHeaders,
        _quotaHeaders,
      ]);
    });

    test('onHeaders is not called for an error reply', () async {
      for (final code in <int>[400, 401, 429, 500, 503]) {
        var called = false;
        await expectLater(
          postEventStream(
            MockClient.streaming(
              (_, _) async => http.StreamedResponse(
                _bytes('{}'),
                code,
                headers: _quotaHeaders,
              ),
            ),
            Uri.parse('https://example.com'),
            headers: <String, String>{},
            body: <String, Object?>{},
            onHeaders: (_) => called = true,
          ),
          emitsError(isA<AiProviderException>()),
          reason: '$code',
        );
        expect(called, isFalse, reason: '$code');
      }
    });

    test('sends JSON and reads each event until [DONE]', () async {
      late http.BaseRequest sent;
      late String sentBody;
      final events = postEventStream(
        MockClient.streaming((request, bodyStream) async {
          sent = request;
          sentBody = await bodyStream.bytesToString();
          return http.StreamedResponse(
            _bytes(
              ': OPENROUTER PROCESSING\n\n'
              'event: message\nid: 1\ndata: {"n":1}\n\n'
              // One event's data can span several lines.
              'data: {"n":\ndata: 2}\n\n'
              'retry: 1000\n\n'
              'data: [DONE]\n\n'
              'data: {"n":3}\n\n',
            ),
            200,
          );
        }),
        Uri.parse('https://example.com'),
        headers: <String, String>{'Authorization': 'Bearer key'},
        body: <String, Object?>{'stream': true},
      );
      expect(await events.toList(), <Map<String, Object?>>[
        <String, Object?>{'n': 1},
        <String, Object?>{'n': 2},
      ]);
      expect(sent.method, 'POST');
      expect(sent.headers['Authorization'], 'Bearer key');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sentBody), <String, Object?>{'stream': true});
    });

    test('an HTTP error before the events maps like postJson', () async {
      for (final (code, body, type) in <(int, String, Type)>[
        (401, '{}', InvalidApiKeyException),
        (403, '{}', InvalidApiKeyException),
        (403, _modelNotFound, ModelNotAvailableException),
        (404, _modelNotFound, ModelNotAvailableException),
        (429, '{}', RateLimitException),
        (503, '{}', ProviderUnavailableException),
        (400, '{}', BadResponseException),
      ]) {
        await expectLater(
          _events(_bytes(body), statusCode: code),
          emitsError(
            isA<AiProviderException>().having(
              (e) => e.runtimeType,
              'type',
              type,
            ),
          ),
          reason: '$code $body',
        );
      }
    });

    test('a wait that is too long is a timeout', () async {
      const timeout = Duration(milliseconds: 20);
      await expectLater(
        postEventStream(
          MockClient.streaming(
            (_, _) => Completer<http.StreamedResponse>().future,
          ),
          Uri.parse('https://example.com'),
          headers: <String, String>{},
          body: <String, Object?>{},
          timeout: timeout,
        ),
        emitsError(isA<ProviderTimeoutException>()),
      );
      // The limit is between two lines, not for the whole reply.
      final slow = StreamController<List<int>>();
      slow.add(utf8.encode('data: {"n":1}\n\n'));
      await expectLater(
        _events(slow.stream, timeout: timeout),
        emitsInOrder(<Object>[
          <String, Object?>{'n': 1},
          emitsError(isA<ProviderTimeoutException>()),
        ]),
      );
    });

    test('connection failures are network errors', () async {
      await expectLater(
        postEventStream(
          MockClient.streaming(
            (_, _) async => throw http.ClientException('offline'),
          ),
          Uri.parse('https://example.com'),
          headers: <String, String>{},
          body: <String, Object?>{},
        ),
        emitsError(isA<NetworkException>()),
      );
      for (final error in <Object>[
        http.ClientException('Connection closed while receiving data'),
        const SocketException('Connection reset by peer'),
      ]) {
        Stream<List<int>> dropped() async* {
          yield utf8.encode('data: {"n":1}\n\n');
          throw error;
        }

        await expectLater(
          _events(dropped()),
          emitsInOrder(<Object>[
            <String, Object?>{'n': 1},
            emitsError(isA<NetworkException>()),
          ]),
          reason: '$error',
        );
      }
    });

    test('data that is not a JSON object is a bad response', () async {
      for (final body in <String>[
        'data: nope\n\n',
        'data: [1]\n\n',
        'data: {"n":\n\n',
      ]) {
        await expectLater(
          _events(_bytes(body)),
          emitsError(isA<BadResponseException>()),
          reason: body,
        );
      }
      // "data:" followed by a byte that can't start a UTF-8 character.
      await expectLater(
        _events(Stream<List<int>>.value(<int>[...utf8.encode('data:'), 0xff])),
        emitsError(isA<BadResponseException>()),
      );
    });
  });

  group('a header value HTTP cannot hold', () {
    // A key pasted with a zero-width space after "FAKE".
    const pasted = 'FAKE\u200b-test-key';

    test('is a key problem, and nothing is sent', () async {
      var sent = 0;
      final client = MockClient((_) async {
        sent++;
        return http.Response('{}', 200);
      });
      final streamingClient = MockClient.streaming((_, _) async {
        sent++;
        return http.StreamedResponse(_bytes('data: [DONE]\n\n'), 200);
      });
      final url = Uri.parse('https://example.com');
      const headers = <String, String>{'Authorization': 'Bearer $pasted'};
      final noKey = isA<InvalidApiKeyException>().having(
        (e) => '$e',
        'toString',
        isNot(contains('FAKE')),
      );

      await expectLater(
        postJson(client, url, headers: headers, body: <String, Object?>{}),
        throwsA(noKey),
      );
      await expectLater(
        postJson(
          client,
          url,
          headers: headers,
          body: <String, Object?>{},
          abortTrigger: Completer<void>().future,
        ),
        throwsA(noKey),
      );
      await expectLater(getJson(client, url, headers: headers), throwsA(noKey));
      await expectLater(
        postEventStream(
          streamingClient,
          url,
          headers: headers,
          body: <String, Object?>{},
        ),
        emitsError(noKey),
      );
      expect(sent, 0);
    });

    test('includes control characters and non-ASCII letters', () async {
      for (final token in <String>['line\nbreak', 'caf\u00e9', 'del\u007f']) {
        await expectLater(
          getJson(
            MockClient((_) async => http.Response('{}', 200)),
            Uri.parse('https://example.com'),
            headers: <String, String>{'Authorization': 'Bearer $token'},
          ),
          throwsA(isA<InvalidApiKeyException>()),
          reason: token,
        );
      }
    });

    test('does not include a tab or printable ASCII', () async {
      final json = await getJson(
        MockClient((_) async => http.Response('{}', 200)),
        Uri.parse('https://example.com'),
        headers: <String, String>{'Authorization': 'Bearer a\tb ~!'},
      );
      expect(json, isEmpty);
    });
  });

  test('TLS and dropped-connection errors are network errors', () async {
    final url = Uri.parse('https://example.com');
    // A captive portal or a self-signed certificate.
    await expectLater(
      getJson(
        MockClient((_) async => throw const HandshakeException('bad cert')),
        url,
        headers: <String, String>{},
      ),
      throwsA(isA<NetworkException>()),
    );
    await expectLater(
      postJson(
        MockClient((_) async => throw const HandshakeException('bad cert')),
        url,
        headers: <String, String>{},
        body: <String, Object?>{},
      ),
      throwsA(isA<NetworkException>()),
    );
    // http passes on a SocketException from a reply that stops halfway.
    Stream<List<int>> dropped() async* {
      yield utf8.encode('{"ok":');
      throw const SocketException('Connection reset by peer');
    }

    for (final abortTrigger in <Future<void>?>[
      null,
      Completer<void>().future,
    ]) {
      await expectLater(
        postJson(
          MockClient.streaming(
            (_, _) async => http.StreamedResponse(dropped(), 200),
          ),
          url,
          headers: <String, String>{},
          body: <String, Object?>{},
          abortTrigger: abortTrigger,
        ),
        throwsA(isA<NetworkException>()),
        reason: 'abortTrigger: $abortTrigger',
      );
    }
  });
}

// What OpenAI sends when a project's model allowlist blocks the model.
const String _modelNotFound = '{"error":{"code":"model_not_found"}}';

// The requests-per-day headers Groq sends with every reply.
const Map<String, String> _quotaHeaders = <String, String>{
  'x-ratelimit-limit-requests': '1000',
  'x-ratelimit-remaining-requests': '999',
};

Stream<List<int>> _bytes(String text) =>
    Stream<List<int>>.value(utf8.encode(text));

Stream<Map<String, dynamic>> _events(
  Stream<List<int>> body, {
  int statusCode = 200,
  Duration timeout = const Duration(seconds: 60),
}) => postEventStream(
  MockClient.streaming((_, _) async => http.StreamedResponse(body, statusCode)),
  Uri.parse('https://example.com'),
  headers: <String, String>{},
  body: <String, Object?>{},
  timeout: timeout,
);

Future<Map<String, dynamic>> _post(int statusCode, String body) => postJson(
  MockClient((_) async => http.Response(body, statusCode)),
  Uri.parse('https://example.com'),
  headers: <String, String>{},
  body: <String, Object?>{},
);
