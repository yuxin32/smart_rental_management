import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// UI-safe guidance only. Raw server/transport exceptions must not be displayed
/// or logged; use SafeDiagnostics' fixed operation/category fields instead.
abstract final class ConnectedFailureMessage {
  static bool isConnectionFailure(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('connection refused') ||
        text.contains('failed host lookup') ||
        text.contains('network request failed') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }

  static String forWrite(Object error, {required String item}) {
    if (error is AuthException) {
      return 'Your session may have expired. Sign in again, then check whether the $item was saved.';
    }
    if (error is PostgrestException && error.code == '42501') {
      return 'Your account cannot make this change. Check that you are using the correct Owner or Provider account.';
    }
    if (isConnectionFailure(error)) {
      return 'Connection lost. The $item may have been saved. Check its current state before trying again.';
    }
    return 'We could not confirm this change. Check the current $item before trying again.';
  }

  static String forBookingReason(String reason) => switch (reason) {
        'price_changed' =>
          'The quoted price changed. Search again to review the new amount.',
        'slot_conflict' ||
        'availability' =>
          'This provider is no longer free for the selected time. Choose another time or provider.',
        'rental_window' =>
          'The selected time is outside this rental unit’s cleaning window.',
        'provider_not_approved' ||
        'service_type' ||
        'rate_unavailable' =>
          'This provider can no longer take this service. Search again.',
        'invalid_interval' ||
        'invalid_duration' =>
          'Choose a future cleaning interval of no more than 8 hours.',
        'property' =>
          'This rental unit is no longer available in your account. Refresh your units.',
        _ => 'The request could not be created. Refresh and search again.',
      };

  static String forAcceptanceReason(String? reason) => switch (reason) {
        'slot_conflict' ||
        'availability' =>
          'This time is no longer available. The request remains Pending; ask the Owner to choose another time.',
        'rental_window' =>
          'The appointment no longer fits the rental unit’s cleaning window. The request remains Pending.',
        'provider_not_approved' ||
        'service_type' =>
          'Your provider account cannot accept this service right now.',
        'not_pending' =>
          'This request is no longer Pending. Refresh bookings to see its current status.',
        _ =>
          'The request was not accepted. Refresh bookings before trying again.',
      };
}
