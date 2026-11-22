import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import 'backend_config.dart';
import 'supabase_auth_repository.dart';
import 'supabase_booking_repository.dart';
import 'supabase_evidence_repository.dart';
import 'supabase_message_repository.dart';
import 'supabase_owner_repository.dart';
import 'supabase_provider_repository.dart';
import 'supabase_review_repository.dart';
import 'authenticated_memory_cache.dart';
import 'auth_session_storage.dart';
import 'auth_storage_factory.dart';
import 'password_recovery_controller.dart';
import 'recovery_link_listener.dart';
import 'session_snapshot_cache.dart';

/// Connected repositories share one authenticated client. This is separate
/// from the in-memory preview stores until the shared schema is deployed.
class SupabaseBackendProvider {
  SupabaseBackendProvider(
    this.client, {
    this.config,
    this.authStorage,
    this.recovery,
  }) {
    cache = AuthenticatedMemoryCache(
      currentUserId: () => client.auth.currentUser?.id,
    );
    snapshots =
        SessionSnapshotCache(currentUserId: () => client.auth.currentUser?.id);
    auth = SupabaseAuthRepository(
      client,
      persistence: authStorage,
      recovery: recovery,
    );
    owner = SupabaseOwnerRepository(client, cache: cache, snapshots: snapshots);
    bookings = SupabaseBookingRepository(client, snapshots: snapshots);
    provider =
        SupabaseProviderRepository(client, cache: cache, snapshots: snapshots);
    evidence = SupabaseEvidenceRepository(client, cache: cache);
    messages = SupabaseMessageRepository(client);
    reviews = SupabaseReviewRepository(client, snapshots: snapshots);
  }

  final SupabaseClient client;
  final BackendConfig? config;
  final AuthSessionStorage? authStorage;
  final PasswordRecoveryController? recovery;
  RecoveryLinkListener? recoveryLinks;
  late final AuthenticatedMemoryCache cache;
  late final SessionSnapshotCache snapshots;
  late final SupabaseAuthRepository auth;
  late final SupabaseOwnerRepository owner;
  late final SupabaseBookingRepository bookings;
  late final SupabaseProviderRepository provider;
  late final SupabaseEvidenceRepository evidence;
  late final SupabaseMessageRepository messages;
  late final SupabaseReviewRepository reviews;

  static Future<SupabaseBackendProvider?> initialize(
    BackendConfig config, {
    Uri? webRecoveryCallback,
  }) async {
    config.validateForBuild(isRelease: kReleaseMode);
    if (!config.isConfigured) return null;
    if (kIsWeb &&
        config.recoveryRedirect != null &&
        (!['http', 'https'].contains(config.recoveryRedirect!.uri.scheme) ||
            config.recoveryRedirect!.uri.origin != Uri.base.origin)) {
      throw const FormatException(
        'Web password recovery must return to this app origin.',
      );
    }
    // No saved login is restored until an anonymous, non-persistent client
    // verifies the administrator-owned environment marker.
    final probe = SupabaseClient(
      config.url,
      config.publishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      final marker = await probe.rpc('get_app_environment').timeout(
            const Duration(seconds: 15),
          );
      config.verifyServerEnvironment(marker);
    } finally {
      await probe.dispose();
    }
    final authStorage = createAuthSessionStorage(
      config,
      hasCurrentSession: () =>
          Supabase.instance.client.auth.currentSession != null,
      isCurrentSession: (raw) {
        final current = Supabase.instance.client.auth.currentSession;
        return current != null &&
            authStorageSessionMatches(raw, current.accessToken);
      },
    );
    await authStorage.initialize();
    final interruptedRecovery = await authStorage.discardInterruptedRecovery();
    try {
      await Supabase.initialize(
        debug: false,
        url: config.url,
        publishableKey: config.publishableKey,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: false,
          localStorage: authStorage,
          pkceAsyncStorage: ProtectedPkceStorage(authStorage),
        ),
      );
    } catch (_) {
      // The SDK sets up its singleton before reading saved Auth. Dispose a
      // partial initialization so Retry cannot reuse its old storage/listeners.
      try {
        await Supabase.instance.dispose();
      } catch (_) {/* No session opened. */}
      rethrow;
    }
    final recovery = PasswordRecoveryController(
      client: Supabase.instance.client,
      storage: authStorage,
      redirect: config.recoveryRedirect,
      interrupted: interruptedRecovery,
    );
    final backend = SupabaseBackendProvider(
      Supabase.instance.client,
      config: config,
      authStorage: authStorage,
      recovery: recovery,
    );
    backend.recoveryLinks = RecoveryLinkListener(recovery);
    await backend.recoveryLinks!.start(webCallback: webRecoveryCallback);
    return backend;
  }
}
