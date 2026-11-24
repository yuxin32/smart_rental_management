import 'package:flutter/foundation.dart';
import '../../owner_provider/services/backend/backend_config.dart';
import '../../owner_provider/services/backend/supabase_backend_provider.dart';
import 'supabase_config.dart';
import '../../owner_provider/services/backend/recovery_web_callback_stub.dart'
    if (dart.library.js_interop)
      '../../owner_provider/services/backend/recovery_web_callback.dart';

abstract final class IntegratedBackend {
  static late final SupabaseBackendProvider instance;
  static Uri? _pendingRecoveryCallback;

  static Future<void> initialize() async {
    // The Android app uses its registered custom scheme. A browser must use
    // the current web origin so Supabase can return to localhost during dev.
    _pendingRecoveryCallback ??= takeRecoveryWebCallback();
    final recoveryRedirectUrl = kIsWeb
        ? Uri.base.resolve('/auth/recovery').toString()
        : 'smartrental://auth/recovery';
    instance = (await SupabaseBackendProvider.initialize(BackendConfig(
      url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey,
      environmentName: 'staging', projectRef: 'myetpfavvwuevdcybdes',
      recoveryRedirectUrl: recoveryRedirectUrl,
    ), webRecoveryCallback: _pendingRecoveryCallback))!;
  }
}
