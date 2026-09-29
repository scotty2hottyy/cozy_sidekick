import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
