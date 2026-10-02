import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/ai/groq_provider.dart';
import 'package:cozy_sidekick/models/chat_message.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test(
    'secure store trims, separates, replaces, and deletes credentials',
    () async {
      final store = SecureApiKeyStore();
      await store.save(AiProviderType.openRouter, '  router-key\n');
      await store.save(AiProviderType.openAi, 'openai-key');
      await store.save(AiProviderType.groq, '  groq-key\n');
      expect(await store.read(AiProviderType.openRouter), 'router-key');
      expect(await store.read(AiProviderType.openAi), 'openai-key');
      expect(await store.read(AiProviderType.groq), 'groq-key');
      await store.save(AiProviderType.openRouter, 'replacement');
      expect(await store.read(AiProviderType.openRouter), 'replacement');
      await store.delete(AiProviderType.openRouter);
      expect(await store.read(AiProviderType.openRouter), isNull);
      expect(await store.read(AiProviderType.openAi), 'openai-key');
      expect(await store.read(AiProviderType.groq), 'groq-key');
    },
  );

  test('secure and in-memory stores reject empty credentials', () async {
    expect(
      () => SecureApiKeyStore().save(AiProviderType.groq, '  '),
      throwsArgumentError,
    );
    expect(
      () => InMemoryApiKeyStore().save(AiProviderType.groq, '\n'),
      throwsArgumentError,
    );
  });

  test('an unreadable key reads as missing and keeps its slot', () async {
    final storage = _UnreadableSecureStorage();
    final store = SecureApiKeyStore(storage);

    expect(await store.read(AiProviderType.openRouter), isNull);
    expect(await store.has(AiProviderType.openRouter), isFalse);
    expect(storage.deletedKeys, isEmpty);
  });

  test('an unreadable key asks for a key instead of sending', () async {
    var called = false;
    final provider = GroqProvider(
      keyStore: SecureApiKeyStore(_UnreadableSecureStorage()),
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      provider.sendChat(systemPrompt: '', messages: <ChatMessage>[]),
      throwsA(isA<MissingApiKeyException>()),
    );
    expect(called, isFalse);
  });
}

/// Fails every read the way the plugin does when it can't decrypt a value.
class _UnreadableSecureStorage extends FlutterSecureStorage {
  final List<String> deletedKeys = <String>[];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'Exception encountered');

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => deletedKeys.add(key);
}
