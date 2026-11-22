import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

bool authStorageSessionMatches(String serialized, String currentAccessToken) {
  try {
    return (jsonDecode(serialized) as Map)['access_token'] ==
        currentAccessToken;
  } catch (_) {
    return false;
  }
}

/// Never includes token bytes, plugin errors, paths or account data.
class AuthStorageException implements Exception {
  const AuthStorageException();
  @override
  String toString() => 'Secure sign-in storage is unavailable. Please retry.';
}

abstract interface class AuthKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// One queue owns session, PKCE and migration writes. No plaintext fallback.
/// Platform protection is provided by the factory, not this coordinator.
class AuthSessionStorage extends LocalStorage {
  AuthSessionStorage({
    required this.protectedStore,
    required this.legacyStore,
    required this.projectRef,
    required this.environment,
    this.isCurrentSession,
    this.hasCurrentSession,
  }) {
    if (!RegExp(r'^[a-z]{20}$').hasMatch(projectRef) ||
        !['staging', 'production'].contains(environment)) {
      throw const AuthStorageException();
    }
  }
  final AuthKeyValueStore protectedStore;
  final AuthKeyValueStore legacyStore;
  final String projectRef;
  final String environment;
  final bool Function(String serialized)? isCurrentSession;
  final bool Function()? hasCurrentSession;
  static const legacyPkceKey = 'supabase.auth.token-code-verifier';
  String get namespace => 'rental.auth.v1.$environment.$projectRef';
  String get sessionKey => '$namespace.session';
  String get pkceKey => '$namespace.pkce';
  String get migrationKey => '$namespace.migrated';
  String get installationKey => '$namespace.installation';
  String get logoutKey => '$namespace.signed-out';
  String get recoveryKey => '$namespace.recovery-in-progress';
  String get legacySessionKey => 'sb-$projectRef-auth-token';
  Future<void> _tail = Future<void>.value();
  Future<void>? _initializing;
  bool _initialized = false;
  bool _writesAllowed = true;
  int _generation = 0;

  Future<T> _serial<T>(Future<T> Function() action) {
    final task = _tail.then((_) => action()).catchError(
          (Object _, StackTrace __) => throw const AuthStorageException(),
        );
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return task;
  }

  Future<void> _writeChecked(
    AuthKeyValueStore store,
    String key,
    String value,
  ) async {
    await store.write(key, value);
    if (await store.read(key) != value) throw const AuthStorageException();
  }

  Future<void> _deleteChecked(AuthKeyValueStore store, String key) async {
    await store.delete(key);
    if (await store.read(key) != null) throw const AuthStorageException();
  }

  // Shape/project checks are NOT signature verification or authorization.
  // Expired JWTs are retained so the SDK can refresh them with the server.
  bool _validSession(String? value) {
    if (value == null || value.length > 512 * 1024) return false;
    try {
      final json = jsonDecode(value);
      if (json is! Map ||
          json['user'] is! Map ||
          json['token_type'] != 'bearer' ||
          json['access_token'] is! String ||
          json['refresh_token'] is! String ||
          (json['refresh_token'] as String).isEmpty) return false;
      final id = json['user']['id'];
      if (id is! String || !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) {
        return false;
      }
      final segments = (json['access_token'] as String).split('.');
      if (segments.length != 3 || segments.any((part) => part.isEmpty)) {
        return false;
      }
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      return claims is Map &&
          claims['sub'] == id &&
          claims['iss'] == 'https://$projectRef.supabase.co/auth/v1' &&
          claims['exp'] is num &&
          (claims['exp'] as num).isFinite &&
          claims['exp'] > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearLegacy() async {
    await _deleteChecked(legacyStore, legacySessionKey);
    // Old PKCE is global: its project cannot be established. Discard rather
    // than migrate; request a fresh link for an interrupted old auth flow.
    await _deleteChecked(legacyStore, legacyPkceKey);
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing != null) return _initializing;
    final work = _serial<void>(() async {
      final installed = await legacyStore.read(installationKey);
      final migrated = await protectedStore.read(migrationKey);
      if (migrated != null && migrated != '1') {
        throw const AuthStorageException();
      }
      // Keychain may survive uninstall. Do not restore a previous installation.
      if (installed != '1' && migrated == '1') {
        await _deleteChecked(protectedStore, sessionKey);
        await _deleteChecked(protectedStore, pkceKey);
        await _deleteChecked(protectedStore, recoveryKey);
      }
      await _writeChecked(legacyStore, installationKey, '1');
      if (await legacyStore.read(logoutKey) == '1') {
        _writesAllowed = false;
        await _deleteChecked(protectedStore, sessionKey);
        await _deleteChecked(protectedStore, pkceKey);
        await _writeChecked(protectedStore, migrationKey, '1');
        await _clearLegacy();
      } else {
        final current = await protectedStore.read(sessionKey);
        // A completed migration must never resurrect an old plaintext copy.
        final candidate = current ??
            (migrated == null
                ? await legacyStore.read(legacySessionKey)
                : null);
        if (_validSession(candidate)) {
          await _writeChecked(protectedStore, sessionKey, candidate!);
        } else {
          await _deleteChecked(protectedStore, sessionKey);
        }
        await _writeChecked(protectedStore, migrationKey, '1');
        await _clearLegacy();
      }
      _initialized = true;
    });
    _initializing = work;
    try {
      await work;
    } finally {
      _initializing = null;
    }
  }

  Future<void> prepareForAuthentication() async {
    await initialize();
    await _serial<void>(() async {
      if (await legacyStore.read(logoutKey) == '1') {
        await _deleteChecked(protectedStore, sessionKey);
        await _deleteChecked(protectedStore, pkceKey);
        await _clearLegacy();
        await _deleteChecked(legacyStore, logoutKey);
      }
      _generation++;
      _writesAllowed = true;
    });
  }

  /// Synchronous invalidation rejects queued/in-flight old auth events.
  void blockWrites() {
    _generation++;
    _writesAllowed = false;
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() async {
    await initialize();
    return _serial<String?>(() async {
      if (!_writesAllowed) return null;
      if (await protectedStore.read(recoveryKey) != null) return null;
      final value = await protectedStore.read(sessionKey);
      if (value != null && !_validSession(value)) {
        await _deleteChecked(protectedStore, sessionKey);
        return null;
      }
      return value;
    });
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final generation = _generation;
    await initialize();
    await _serial<void>(() async {
      if (!_writesAllowed ||
          generation != _generation ||
          (isCurrentSession != null &&
              !isCurrentSession!(persistSessionString))) return;
      if (!_validSession(persistSessionString)) {
        throw const AuthStorageException();
      }
      await _writeChecked(protectedStore, sessionKey, persistSessionString);
      await _clearLegacy();
    });
  }

  @override
  Future<void> removePersistedSession() async {
    if (hasCurrentSession?.call() == true) return;
    await clearForSignOut();
  }

  Future<void> clearForSignOut() async {
    blockWrites();
    await _serial<void>(() => _writeChecked(legacyStore, logoutKey, '1'));
    await initialize();
    await _serial<void>(() async {
      // Intent precedes encrypted-byte deletion. Interrupted logout must be
      // completed at next startup instead of restoring a surviving old token.
      await _writeChecked(legacyStore, logoutKey, '1');
      await _deleteChecked(protectedStore, sessionKey);
      await _deleteChecked(protectedStore, pkceKey);
      await _writeChecked(protectedStore, migrationKey, '1');
      await _clearLegacy();
    });
  }

  /// Durable intent is written BEFORE exchanging a recovery code. An interrupted
  /// recovery must never be restored as a normal workspace login.
  Future<bool> hasRecoveryIntent() async {
    await initialize();
    return _serial<bool>(
        () async => await protectedStore.read(recoveryKey) != null,);
  }

  Future<void> markRecoveryIntent() async {
    await initialize();
    await _serial<void>(() => _writeChecked(protectedStore, recoveryKey, '1'));
  }

  /// Only clear after local sign-out has completed. Keep the marker on failure.
  Future<void> clearRecoveryIntent() async {
    await initialize();
    await _serial<void>(() async {
      if (_writesAllowed ||
          await legacyStore.read(logoutKey) != '1' ||
          await protectedStore.read(sessionKey) != null ||
          await protectedStore.read(pkceKey) != null) {
        throw const AuthStorageException();
      }
      await _deleteChecked(protectedStore, recoveryKey);
    });
  }

  Future<bool> discardInterruptedRecovery() async {
    final interrupted = await hasRecoveryIntent();
    if (interrupted) await clearForSignOut();
    return interrupted;
  }

  Future<String?> readPkce() async {
    await initialize();
    return _serial<String?>(
      () async => _writesAllowed ? protectedStore.read(pkceKey) : null,
    );
  }

  Future<void> writePkce(String value) async {
    final generation = _generation;
    await initialize();
    await _serial<void>(() async {
      if (!_writesAllowed ||
          generation != _generation ||
          value.isEmpty ||
          value.length > 1024) throw const AuthStorageException();
      await _writeChecked(protectedStore, pkceKey, value);
    });
  }

  Future<void> removePkce() async {
    // Logout owns namespace cleanup; a locked vault must not prevent the SDK
    // from clearing its memory and emitting the signedOut event.
    if (!_writesAllowed) return;
    await initialize();
    await _serial<void>(() => _deleteChecked(protectedStore, pkceKey));
  }
}

class ProtectedPkceStorage extends GotrueAsyncStorage {
  ProtectedPkceStorage(this.sessionStorage);
  final AuthSessionStorage sessionStorage;
  void _checkKey(String key) {
    if (key != AuthSessionStorage.legacyPkceKey) {
      throw const AuthStorageException();
    }
  }

  @override
  Future<String?> getItem({required String key}) {
    _checkKey(key);
    return sessionStorage.readPkce();
  }

  @override
  Future<void> setItem({required String key, required String value}) {
    _checkKey(key);
    return sessionStorage.writePkce(value);
  }

  @override
  Future<void> removeItem({required String key}) {
    _checkKey(key);
    return sessionStorage.removePkce();
  }
}
