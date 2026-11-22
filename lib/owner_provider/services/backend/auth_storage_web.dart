import 'package:web/web.dart' as web;
import 'auth_session_storage.dart';
import 'backend_config.dart';

/// Browser JavaScript storage is NOT an OS vault or same-origin XSS protection.
AuthSessionStorage createPlatformAuthStorage(
  BackendConfig config, {
  required bool Function(String) isCurrentSession,
  required bool Function() hasCurrentSession,
}) {
  final uri = Uri.base;
  if (uri.scheme != 'https' &&
      !['localhost', '127.0.0.1', '::1'].contains(uri.host)) {
    throw const AuthStorageException();
  }
  return AuthSessionStorage(
    projectRef: config.projectRef,
    environment: config.environmentName,
    isCurrentSession: isCurrentSession,
    hasCurrentSession: hasCurrentSession,
    protectedStore: BrowserAuthStore(sessionOnly: true),
    legacyStore: BrowserAuthStore(sessionOnly: false),
  );
}

class BrowserAuthStore implements AuthKeyValueStore {
  BrowserAuthStore({required this.sessionOnly});
  final bool sessionOnly;
  web.Storage get _storage =>
      sessionOnly ? web.window.sessionStorage : web.window.localStorage;
  @override
  Future<String?> read(String key) async =>
      _storage.getItem(key) ??
      (!sessionOnly ? _storage.getItem('flutter.$key') : null);
  @override
  Future<void> write(String key, String value) async =>
      _storage.setItem(key, value);
  @override
  Future<void> delete(String key) async {
    _storage.removeItem(key);
    if (!sessionOnly) _storage.removeItem('flutter.$key');
  }
}
