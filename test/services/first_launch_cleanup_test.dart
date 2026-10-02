import 'package:cozy_sidekick/ai/ai_provider.dart';
import 'package:cozy_sidekick/services/api_key_store.dart';
import 'package:cozy_sidekick/services/first_launch_cleanup.dart';
import 'package:cozy_sidekick/services/personality_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<InMemoryApiKeyStore> storeWithEveryKey() async {
    final keys = InMemoryApiKeyStore();
    for (final provider in AiProviderType.values) {
      await keys.save(provider, '${provider.name}-key');
    }
    return keys;
  }

  test('a first launch deletes keys an earlier install left', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final keys = await storeWithEveryKey();

    await clearKeysLeftFromPreviousInstall(
      await SharedPreferences.getInstance(),
      keys,
    );

    for (final provider in AiProviderType.values) {
      expect(await keys.read(provider), isNull, reason: provider.name);
    }
  });

  test('a later launch keeps saved keys', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      firstLaunchMarkerKey: '[]',
    });
    final keys = await storeWithEveryKey();

    await clearKeysLeftFromPreviousInstall(
      await SharedPreferences.getInstance(),
      keys,
    );

    for (final provider in AiProviderType.values) {
      expect(await keys.read(provider), '${provider.name}-key');
    }
  });

  test('a storage error does not stop the cleanup or startup', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final keys = _FailingDeleteKeyStore(failOn: AiProviderType.openRouter);

    await expectLater(
      clearKeysLeftFromPreviousInstall(
        await SharedPreferences.getInstance(),
        keys,
      ),
      completes,
    );

    expect(keys.deleted, AiProviderType.values);
  });

  test('the personality store writes the first-launch marker', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await PersonalityService().initialize();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(firstLaunchMarkerKey), isTrue);
  });
}

class _FailingDeleteKeyStore extends InMemoryApiKeyStore {
  _FailingDeleteKeyStore({required this.failOn});

  final AiProviderType failOn;
  final List<AiProviderType> deleted = <AiProviderType>[];

  @override
  Future<void> delete(AiProviderType provider) async {
    deleted.add(provider);
    if (provider == failOn) throw StateError('storage unavailable');
    await super.delete(provider);
  }
}
