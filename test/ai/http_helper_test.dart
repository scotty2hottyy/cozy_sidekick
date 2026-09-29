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

  group('postEventStream', () {
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
}

// What OpenAI sends when a project's model allowlist blocks the model.
const String _modelNotFound = '{"error":{"code":"model_not_found"}}';

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
