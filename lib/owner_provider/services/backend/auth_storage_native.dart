import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_session_storage.dart';
import 'backend_config.dart';

AuthSessionStorage createPlatformAuthStorage(
  BackendConfig config, {
  required bool Function(String) isCurrentSession,
  required bool Function() hasCurrentSession,
}) =>
    AuthSessionStorage(
      projectRef: config.projectRef,
      environment: config.environmentName,
      isCurrentSession: isCurrentSession,
      hasCurrentSession: hasCurrentSession,
      protectedStore: NativeProtectedStore(
        FlutterSecureStorage(
          aOptions: AndroidOptions(
            resetOnError: false,
            storageNamespace:
                'rental_auth_${config.environmentName}_${config.projectRef}',
          ),
          iOptions: const IOSOptions(
            accountName: 'rental_auth',
            accessibility: KeychainAccessibility.unlocked_this_device,
            synchronizable: false,
          ),
          mOptions: const MacOsOptions(
            accountName: 'rental_auth',
            accessibility: KeychainAccessibility.unlocked_this_device,
            synchronizable: false,
          ),
        ),
      ),
      legacyStore: PreferencesAuthStore(),
    );

class NativeProtectedStore implements AuthKeyValueStore {
  NativeProtectedStore(this.storage);
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class PreferencesAuthStore implements AuthKeyValueStore {
  Future<SharedPreferences> _preferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences;
  }

  @override
  Future<String?> read(String key) async =>
      (await _preferences()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    if (!await (await _preferences()).setString(key, value)) {
      throw const AuthStorageException();
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!await (await _preferences()).remove(key)) {
      throw const AuthStorageException();
    }
  }
}
