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
