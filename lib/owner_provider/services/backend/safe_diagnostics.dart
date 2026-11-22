import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_session_storage.dart';
import 'booking_rate_limit.dart';

enum SafeOperation {
  signIn,
  register,
  signOut,
  recoveryLink,
  recoveryUpdate,
  recoveryCleanup,
  evidenceLoad,
  evidenceUpload,
  evidenceVerify,
  evidenceRemove,
  evidenceRemoveVerify,
  completion,
  completionVerify,
  reviewSave,
  reviewVerify,
  providerSearch,
  requestCreate,
  requestVerify,
  providerSetupSave,
  providerSetupLoad,
  bookingUpdate,
  bookingVerify,
  propertySave,
  messageSend,
  messageVerify,
  frameworkFailure,
  unhandledAsyncFailure,
}

enum SafeFailureCategory {
  connection,
  authentication,
  permission,
  conflict,
  secureStorage,
  rateLimited,
  unknown
}

/// Allow-list diagnostics: no message, stack, URL, ID, payload or arbitrary
/// runtimeType is accepted as an output field. Never call error.toString().
class SafeDiagnostics {
  SafeDiagnostics({this.enabled = kDebugMode, void Function(String)? sink})
      : _sink = sink;
  static final app = SafeDiagnostics();
  final bool enabled;
  final void Function(String)? _sink;
  int _sequence = 0;

  static SafeFailureCategory category(Object error) {
    if (error is ServerActionLimit) return SafeFailureCategory.rateLimited;
    if (error is AuthStorageException) return SafeFailureCategory.secureStorage;
    if (error is SocketException || error is TimeoutException) {
      return SafeFailureCategory.connection;
    }
    if (error is AuthException) return SafeFailureCategory.authentication;
    if (error is PostgrestException) {
      if (error.code == '42501') return SafeFailureCategory.permission;
      if (['23505', '23514', '23P01', '40001'].contains(error.code)) {
        return SafeFailureCategory.conflict;
      }
    }
    return SafeFailureCategory.unknown;
  }

  void record(SafeOperation operation, Object error) {
    if (!enabled) return;
    final reference = (++_sequence).toString().padLeft(6, '0');
    try {
      (_sink ?? debugPrint)(
        '[app] ref=$reference operation=${operation.name} category=${category(error).name}',
      );
    } catch (_) {
      /* Logging must not break an operation or fall back to raw errors. */
    }
  }
}
