import 'auth_session_storage.dart';
import 'backend_config.dart';
import 'auth_storage_native.dart'
    if (dart.library.js_interop) 'auth_storage_web.dart' as platform;

AuthSessionStorage createAuthSessionStorage(
  BackendConfig config, {
  required bool Function(String) isCurrentSession,
  required bool Function() hasCurrentSession,
}) =>
    platform.createPlatformAuthStorage(
      config,
      isCurrentSession: isCurrentSession,
      hasCurrentSession: hasCurrentSession,
    );
