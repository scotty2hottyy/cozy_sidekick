import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ai/ai_provider.dart';

abstract interface class ApiKeyStore {
  Future<String?> read(AiProviderType provider);
  Future<void> save(AiProviderType provider, String secret);
  Future<void> delete(AiProviderType provider);

  Future<bool> has(AiProviderType provider) async {
    final value = await read(provider);
    return value != null && value.trim().isNotEmpty;
  }
}

class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _slot(AiProviderType provider) => 'api_key.${provider.name}';

  @override
  Future<String?> read(AiProviderType provider) =>
      _storage.read(key: _slot(provider));

  @override
  Future<void> save(AiProviderType provider, String secret) {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) throw ArgumentError('Credential cannot be empty');
    return _storage.write(key: _slot(provider), value: trimmed);
  }

  @override
  Future<void> delete(AiProviderType provider) =>
      _storage.delete(key: _slot(provider));

  @override
  Future<bool> has(AiProviderType provider) async {
    final value = await read(provider);
    return value != null && value.trim().isNotEmpty;
  }
}

class InMemoryApiKeyStore implements ApiKeyStore {
  final Map<AiProviderType, String> _values = <AiProviderType, String>{};

  @override
  Future<String?> read(AiProviderType provider) async => _values[provider];

  @override
  Future<void> save(AiProviderType provider, String secret) async {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) throw ArgumentError('Credential cannot be empty');
    _values[provider] = trimmed;
  }

  @override
  Future<void> delete(AiProviderType provider) async =>
      _values.remove(provider);

  @override
  Future<bool> has(AiProviderType provider) async =>
      _values[provider]?.isNotEmpty ?? false;
}
