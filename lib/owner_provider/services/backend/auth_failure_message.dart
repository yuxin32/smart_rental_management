import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_session_storage.dart';
import 'safe_diagnostics.dart';

class AccountRoleMismatch implements Exception {
  const AccountRoleMismatch();
}

abstract final class AuthFailureMessage {
  static String forOperation(Object error, {required bool registering}) {
    if (SafeDiagnostics.category(error) == SafeFailureCategory.connection ||
        error is AuthRetryableFetchException) {
      return 'Could not connect. Check your internet connection and try again.';
    }
    if (error is AccountRoleMismatch) {
      return 'This account uses the other role. Select Owner or Service Provider to match your account.';
    }
    if (error is AuthStorageException) {
      return 'Secure sign-in storage is unavailable. Unlock your device and try again.';
    }
    if (error is AuthException) {
      return switch (error.code) {
        'invalid_credentials' =>
          'Email or password is incorrect. Check both and try again.',
        'email_not_confirmed' => 'Confirm your email before signing in.',
        'over_request_rate_limit' ||
        'over_email_send_rate_limit' ||
        'over_sms_send_rate_limit' =>
          'Too many attempts. Wait a little before trying again.',
        'weak_password' => 'Choose a stronger password and try again.',
        _ => registering
            ? 'Registration could not be completed. Check your details and try again.'
            : 'Sign-in could not be completed. Check your details and connection, then try again.',
      };
    }
    // No raw StateError, server message, URL, email or exception string reaches UI.
    return registering
        ? 'Registration could not be completed. Please try again.'
        : 'Sign-in could not be completed. Please try again.';
  }
}
