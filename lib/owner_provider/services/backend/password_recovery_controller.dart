import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_recovery_redirect.dart';
import 'auth_session_storage.dart';
import 'safe_diagnostics.dart';

enum RecoveryPhase {
  idle,
  checking,
  ready,
  saving,
  complete,
  invalid,
  uncertain,
  cleanupRequired
}

/// Owns the recovery session, not a role/account identity. The UI gate is not
/// server authorization: Supabase still validates every Auth/API request.
class PasswordRecoveryController extends ChangeNotifier {
  PasswordRecoveryController(
      {required this.client,
      required this.storage,
      required this.redirect,
      bool interrupted = false,})
      : _phase = interrupted ? RecoveryPhase.invalid : RecoveryPhase.idle;
  final SupabaseClient client;
  final AuthSessionStorage storage;
  final AuthRecoveryRedirect? redirect;
  RecoveryPhase _phase;
  RecoveryPhase get phase => _phase;
  bool get blocksWorkspace => phase != RecoveryPhase.idle;
  bool get busy =>
      phase == RecoveryPhase.checking || phase == RecoveryPhase.saving;
  String? message;
  String? _userId;
  String? _lastCode;
  bool _passwordChanged = false;
  Completer<void>? _regularAuth;

  /// Serialize login/register/email initiation against a recovery callback.
  /// An already-running login finishes before a code exchange can start.
  Future<T> regularAuthentication<T>(Future<T> Function() action) async {
    if (blocksWorkspace || _regularAuth != null) {
      throw const AuthException('Another authentication operation is active.');
    }
    final completion = Completer<void>();
    _regularAuth = completion;
    try {
      return await action();
    } finally {
      _regularAuth = null;
      completion.complete();
    }
  }

  void _set(RecoveryPhase value, [String? text]) {
    _phase = value;
    message = text;
    notifyListeners();
  }

  Future<void> requestEmail(String email) => regularAuthentication(() async {
        if (blocksWorkspace ||
            redirect == null ||
            client.auth.currentSession != null) {
          throw const AuthException('Password recovery is unavailable.');
        }
        await storage.prepareForAuthentication();
        _passwordChanged = false;
        await client.auth.resetPasswordForEmail(email.trim(),
            redirectTo: redirect!.uri.toString(),);
      });

  /// Unrelated links are ignored; exact trusted recovery links fail closed.
  /// No implicit token URL, arbitrary redirect or query-supplied type is trusted.
  Future<void> handleLink(Uri uri) async {
    // Forgot-password requests originate while signed out. Unsolicited reset
    // callbacks must not log out a normally signed-in user (logout CSRF).
    if (phase == RecoveryPhase.idle && client.auth.currentSession != null) return;
    if (redirect == null ||
        !redirect!.matches(uri) ||
        busy ||
        phase == RecoveryPhase.ready) return;
    final code = redirect!.code(uri);
    if (code != null && code == _lastCode) return;
    _set(RecoveryPhase
        .checking,); // Gate and unmount private routes synchronously.
    try {
      await storage.markRecoveryIntent();
      await _regularAuth?.future;
      final verifier = await storage.readPkce();
      if (code == null ||
          verifier == null ||
          !RegExp(r'^[A-Za-z0-9._~-]{43,128}/passwordRecovery$')
              .hasMatch(verifier)) {
        throw const AuthException('A new recovery link is required.');
      }
      _lastCode = code;
      final result = await client.auth.exchangeCodeForSession(code);
      if (result.redirectType != AuthChangeEvent.passwordRecovery.name ||
          result.session.user.id != client.auth.currentUser?.id) {
        throw const AuthException('Recovery could not be verified.');
      }
      _userId = result.session.user.id;
      _set(RecoveryPhase.ready);
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.recoveryLink, error);
      await _endSession(RecoveryPhase.invalid);
    }
  }

  Future<void> updatePassword(String password) async {
    if (phase != RecoveryPhase.ready || password.length < 8) return;
    if (_userId == null ||
        client.auth.currentUser?.id != _userId ||
        client.auth.currentSession == null ||
        client.auth.currentSession!.isExpired) {
      _set(RecoveryPhase.checking);
      await _endSession(RecoveryPhase.invalid);
      return;
    }
    _set(RecoveryPhase.saving);
    try {
      final response =
          await client.auth.updateUser(UserAttributes(password: password));
      if (response.user?.id != _userId ||
          client.auth.currentUser?.id != _userId) {
        throw const AuthException('Recovery session changed.');
      }
      _passwordChanged = true;
    } on AuthException catch (error) {
      SafeDiagnostics.app.record(SafeOperation.recoveryUpdate, error);
      if (['weak_password', 'same_password'].contains(error.code)) {
        _set(
            RecoveryPhase.ready,
            error.code == 'same_password'
                ? 'Choose a password different from your current password.'
                : 'This password does not meet the account security requirements. Choose a stronger password.',);
        return;
      }
      await _endSession(['401', '403'].contains(error.statusCode)
          ? RecoveryPhase.invalid
          : RecoveryPhase.uncertain,);
      return;
    } catch (error) {
      // A lost response does not prove that the server rejected the update.
      SafeDiagnostics.app.record(SafeOperation.recoveryUpdate, error);
      await _endSession(RecoveryPhase.uncertain);
      return;
    }
    await _endSession(RecoveryPhase.complete);
  }

  Future<void> _endSession(RecoveryPhase next) async {
    var cleared = false;
    try {
      await storage.clearForSignOut();
      cleared = true;
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.recoveryCleanup, error);
    }
    // SDK removes memory before making its logout HTTP request. A server outage
    // does not reverse local cleanup or prove global revocation succeeded.
    try {
      await client.auth.signOut();
    } catch (error) {
      SafeDiagnostics.app.record(SafeOperation.recoveryCleanup, error);
    }
    if (cleared && client.auth.currentSession == null) {
      try {
        await storage.clearRecoveryIntent();
        _userId = null;
        _set(next);
        return;
      } catch (error) {
        SafeDiagnostics.app.record(SafeOperation.recoveryCleanup, error);
      }
    }
    _set(RecoveryPhase.cleanupRequired);
  }

  Future<void> leave() async {
    if (busy) return;
    _set(RecoveryPhase.checking);
    await _endSession(RecoveryPhase.idle);
  }

  Future<void> retryCleanup() async {
    if (phase != RecoveryPhase.cleanupRequired) return;
    _set(RecoveryPhase.checking);
    await _endSession(
        _passwordChanged ? RecoveryPhase.complete : RecoveryPhase.invalid,);
  }
}
