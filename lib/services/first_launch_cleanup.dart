import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_provider.dart';
import 'api_key_store.dart';

/// A preference `PersonalityService` writes on every launch, and has since
/// before v1.0.0, so it is missing only on the first launch of an install.
const String firstLaunchMarkerKey = 'personality.items';

/// Deletes saved keys an earlier install left behind.
///
/// iOS keeps Keychain items after the app is deleted but wipes its
/// preferences, so a reinstall would otherwise find the old keys. Run this
/// before `PersonalityService.initialize`, which writes the marker. A storage
/// error is logged and skipped so it never stops startup.
Future<void> clearKeysLeftFromPreviousInstall(
  SharedPreferences prefs,
  ApiKeyStore keyStore,
) async {
  if (prefs.containsKey(firstLaunchMarkerKey)) return;
  for (final provider in AiProviderType.values) {
    try {
      await keyStore.delete(provider);
    } on Object catch (error) {
      debugPrint('Old key cleanup failed: ${error.runtimeType}');
    }
  }
}
