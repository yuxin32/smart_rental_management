// lib/services/user_session.dart
// In-memory user session. Tracks:
//   - isLoggedIn (mock; true after login screen submit)
//   - hasSeenOnboarding (true after first-launch onboarding completes)
//   - email, role
//
// Sprint 0: pure in-memory (resets on app restart).
// Sprint 1: backed by Supabase Auth + SharedPreferences.

import 'package:flutter/material.dart';

enum UserRole { owner, provider }

class UserSession extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool _hasSeenOnboarding = false;
  String _email = '';
  String _displayName = '';
  UserRole _role = UserRole.owner;
  String? _providerId;

  bool get isLoggedIn => _isLoggedIn;
  bool get hasSeenOnboarding => _hasSeenOnboarding;
  String get email => _email;
  String get displayName => _displayName;
  UserRole get role => _role;
  String? get providerId => _providerId;

  void signIn({
    required String email,
    required String displayName,
    required UserRole role,
    String? providerId,
  }) {
    _isLoggedIn = true;
    _email = email;
    _displayName = displayName;
    _role = role;
    _providerId = providerId ?? (role == UserRole.provider ? 'p-a' : null);
    notifyListeners();
  }

  void signOut() {
    _isLoggedIn = false;
    _email = '';
    _displayName = '';
    _providerId = null;
    _role = UserRole.owner;
    _hasSeenOnboarding = false;
    notifyListeners();
  }

  void updateDisplayName(String value) {
    if (!_isLoggedIn || value == _displayName) return;
    _displayName = value;
    notifyListeners();
  }

  void markOnboardingSeen() {
    _hasSeenOnboarding = true;
    notifyListeners();
  }
}

/// InheritedWidget exposing UserSession to descendants.
class UserSessionAccess extends InheritedWidget {
  const UserSessionAccess({
    super.key,
    required UserSession session,
    required super.child,
  }) : _session = session;

  final UserSession _session;

  static UserSession of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<UserSessionAccess>();
    assert(result != null, 'No UserSessionAccess found in context');
    return result!._session;
  }

  @override
  bool updateShouldNotify(UserSessionAccess oldWidget) => false;
}
