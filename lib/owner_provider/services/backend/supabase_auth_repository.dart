import 'package:supabase_flutter/supabase_flutter.dart';

import '../user_session.dart';
import 'dart:convert';
import 'auth_session_storage.dart';
import 'password_recovery_controller.dart';

class AuthIdentity {
  const AuthIdentity({
    required this.userId,
    required this.email,
    required this.role,
    this.displayName,
  });

  final String userId;
  final String email;
  final UserRole role;
  final String? displayName;
}

class RegistrationOutcome {
  const RegistrationOutcome({required this.requiresEmailConfirmation});
  final bool requiresEmailConfirmation;
}

class ProviderRegistrationDetails {
  const ProviderRegistrationDetails({
    required this.serviceArea,
    required this.serviceOriginAddress,
    this.hourlyRate,
    this.dailyRate,
  });

  final String serviceArea;
  final String serviceOriginAddress;
  final double? hourlyRate;
  final double? dailyRate;
}

/// Auth is authoritative: the selected UI role never overrides user_account.
class SupabaseAuthRepository {
  const SupabaseAuthRepository(this.client, {this.persistence, this.recovery});
  final SupabaseClient client;
  final AuthSessionStorage? persistence;
  final PasswordRecoveryController? recovery;

  Future<AuthIdentity> signIn(String email, String password) => recovery == null
      ? _signIn(email, password)
      : recovery!.regularAuthentication(() => _signIn(email, password));

  Future<AuthIdentity> _signIn(String email, String password) async {
    _checkRecoveryGate();
    await persistence?.prepareForAuthentication();
    await persistence?.removePkce();
    final result = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (result.user == null || result.session == null) {
      throw StateError('Sign-in did not create an authenticated session.');
    }
    _checkRecoveryGate();
    final identity = await _loadOrCreateAccount(result.user!);
    if (client.auth.currentUser?.id != identity.userId) {
      throw StateError('The sign-in session changed. Please sign in again.');
    }
    await _confirmPersistence();
    _checkRecoveryGate();
    if (client.auth.currentUser?.id != identity.userId) {
      throw StateError('The sign-in session changed. Please sign in again.');
    }
    return identity;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (recovery == null) {
      throw const AuthException('Password recovery is not configured.');
    }
    await recovery!.requestEmail(email);
  }

  Future<RegistrationOutcome> register({
    required String email,
    required String password,
    required UserRole role,
    required String contactNumber,
    required String displayName,
    ProviderRegistrationDetails? providerDetails,
  }) {
    Future<RegistrationOutcome> action() => _register(
          email: email,
          password: password,
          role: role,
          contactNumber: contactNumber,
          displayName: displayName,
          providerDetails: providerDetails,
        );
    return recovery == null
        ? action()
        : recovery!.regularAuthentication(action);
  }

  Future<RegistrationOutcome> _register({
    required String email,
    required String password,
    required UserRole role,
    required String contactNumber,
    required String displayName,
    ProviderRegistrationDetails? providerDetails,
  }) async {
    _checkRecoveryGate();
    if (displayName.trim().runes.length < 2 ||
        displayName.trim().runes.length > 60) {
      throw ArgumentError('Enter a name of 2–60 characters.');
    }
    if (contactNumber.trim().isEmpty) {
      throw ArgumentError('A contact number is required.');
    }
    if (role == UserRole.provider &&
        (providerDetails == null ||
            providerDetails.serviceArea.trim().isEmpty ||
            providerDetails.serviceOriginAddress.trim().isEmpty ||
            (providerDetails.hourlyRate == null &&
                providerDetails.dailyRate == null) ||
            (providerDetails.hourlyRate != null &&
                (!providerDetails.hourlyRate!.isFinite ||
                    providerDetails.hourlyRate! <= 0)) ||
            (providerDetails.dailyRate != null &&
                (!providerDetails.dailyRate!.isFinite ||
                    providerDetails.dailyRate! <= 0)))) {
      throw ArgumentError(
        'Provider area, origin and a positive hourly or daily rate are required.',
      );
    }
    await persistence?.prepareForAuthentication();
    await persistence?.removePkce();
    final result = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'requested_role': role.name,
        'requested_contact_number': contactNumber.trim(),
        'requested_full_name': displayName.trim(),
        if (providerDetails != null) ...{
          'requested_service_area': providerDetails.serviceArea.trim(),
          'requested_service_origin':
              providerDetails.serviceOriginAddress.trim(),
          if (providerDetails.hourlyRate != null)
            'requested_hourly_rate': providerDetails.hourlyRate,
          if (providerDetails.dailyRate != null)
            'requested_daily_rate': providerDetails.dailyRate,
        },
      },
    );
    if (result.user == null) {
      throw StateError('Registration did not create an account.');
    }
    _checkRecoveryGate();
    if (result.session != null) {
      await _loadOrCreateAccount(result.user!);
      await _confirmPersistence();
      _checkRecoveryGate();
    }
    return RegistrationOutcome(
      requiresEmailConfirmation: result.session == null,
    );
  }

  Future<AuthIdentity?> currentIdentity() async {
    if (recovery?.blocksWorkspace == true) return null;
    final user = client.auth.currentUser;
    if (user == null || client.auth.currentSession == null) return null;
    final identity = await _loadOrCreateAccount(user);
    if (client.auth.currentUser?.id != user.id ||
        recovery?.blocksWorkspace == true) return null;
    return identity;
  }

  Future<void> signOut() async {
    persistence?.blockWrites();
    // Local intent and cleanup precede remote revocation. No claim that an
    // offline operation immediately invalidates issued JWTs at the server.
    try {
      await persistence?.clearForSignOut();
    } finally {
      await client.auth.signOut();
    }
  }

  void _checkRecoveryGate() {
    if (recovery?.blocksWorkspace == true) {
      throw const AuthException('Finish password recovery before signing in.');
    }
  }

  Future<void> _confirmPersistence() async {
    if (persistence == null) return;
    final expected = client.auth.currentSession;
    try {
      if (expected == null) throw const AuthStorageException();
      final serialized = jsonEncode(expected.toJson());
      await persistence!.persistSession(serialized);
      if (client.auth.currentSession?.accessToken != expected.accessToken) {
        throw StateError('The sign-in session changed. Please sign in again.');
      }
      if (await persistence!.accessToken() != serialized) {
        throw const AuthStorageException();
      }
    } on AuthStorageException {
      if (client.auth.currentUser?.id == expected?.user.id) {
        try {
          await signOut();
        } catch (_) {/* Sanitized error wins. */}
      }
      rethrow;
    }
  }

  Future<AuthIdentity> _loadOrCreateAccount(User user) async {
    final existing = await client
        .from('user_account')
        .select('user_id,email,role,full_name')
        .eq('user_id', user.id)
        .maybeSingle();
    if (existing != null) {
      final identity = _decode(existing);
      await _ensureProviderProfile(user, identity.role);
      return identity;
    }

    final requestedRole = user.userMetadata?['requested_role'];
    if (requestedRole != 'owner' && requestedRole != 'provider') {
      throw StateError('The account has no Owner/Provider role.');
    }
    final email = user.email;
    if (email == null) throw StateError('The account has no email address.');
    final created = await client
        .from('user_account')
        .insert({
          'user_id': user.id,
          'email': email,
          'role': requestedRole,
          'contact_number': user.userMetadata?['requested_contact_number'],
        })
        .select('user_id,email,role,full_name')
        .single();
    final identity = _decode(created);
    await _ensureProviderProfile(user, identity.role);
    return identity;
  }

  Future<void> _ensureProviderProfile(User user, UserRole role) async {
    if (role != UserRole.provider) return;
    final existing = await client
        .from('provider_profile')
        .select('provider_id')
        .eq('provider_id', user.id)
        .maybeSingle();
    if (existing != null) return;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final area = metadata['requested_service_area'];
    final origin = metadata['requested_service_origin'];
    final hourlyRate = metadata['requested_hourly_rate'];
    final dailyRate = metadata['requested_daily_rate'];
    if (area is! String ||
        area.trim().isEmpty ||
        origin is! String ||
        origin.trim().isEmpty ||
        (hourlyRate is! num && dailyRate is! num) ||
        (hourlyRate is num && hourlyRate <= 0) ||
        (dailyRate is num && dailyRate <= 0)) {
      throw StateError('Provider registration details are incomplete.');
    }
    await client.from('provider_profile').insert({
      'provider_id': user.id,
      'service_area': area.trim(),
      'service_origin_address': origin.trim(),
      'hourly_rate': (hourlyRate as num?)?.toDouble(),
      'daily_rate': (dailyRate as num?)?.toDouble(),
    });
  }

  AuthIdentity _decode(Map<String, dynamic> row) {
    final role = switch (row['role']) {
      'owner' => UserRole.owner,
      'provider' => UserRole.provider,
      _ => throw StateError('Unsupported account role.'),
    };
    return AuthIdentity(
      userId: row['user_id'] as String,
      email: row['email'] as String,
      role: role,
      displayName: row['full_name'] as String?,
    );
  }
}
