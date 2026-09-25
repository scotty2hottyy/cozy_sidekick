import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/http_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
}

Future<Map<String, dynamic>> _post(int statusCode, String body) => postJson(
  MockClient((_) async => http.Response(body, statusCode)),
  Uri.parse('https://example.com'),
  headers: <String, String>{},
  body: <String, Object?>{},
);
