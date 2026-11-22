import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admin/presentation/pages/admin_module_shell.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/tenant_set_password_page.dart';
import '../../features/auth/presentation/pages/tenant_verification_page.dart';
import '../../features/tenant/presentation/pages/tenant_module_shell.dart';
import 'app_auth_service.dart';
import '../config/integrated_backend.dart';
import '../../owner_provider/main.dart' as cleaning;

class AppAuthGate extends StatefulWidget {
  const AppAuthGate({super.key});

  @override
  State<AppAuthGate> createState() => _AppAuthGateState();
}

class _AppAuthGateState extends State<AppAuthGate> {
  late Future<AppAuthProfile?> _profile;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _profile = _resolveProfile();
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) {
            if (!mounted) return;
            setState(() {
              _profile = _resolveProfile();
            });
          });
    } catch (_) {
      // Widget tests can render the auth gate without initializing Supabase.
      _authSubscription = const Stream<AuthState>.empty().listen((_) {});
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<AppAuthProfile?> _resolveProfile() async {
    try {
      var profile = await AppAuthService.loadCurrentProfile();
      final user = IntegratedBackend.instance.client.auth.currentUser;
      if (profile == null && ['owner', 'provider'].contains(user?.userMetadata?['requested_role'])) {
        await IntegratedBackend.instance.auth.currentIdentity();
        profile = await AppAuthService.loadCurrentProfile();
      }
      final isPendingTenantAccount =
          profile?.accountType == AppAccountType.tenant &&
          profile?.accountStatus == 'pending' &&
          (profile?.invitationStatus == 'invited' ||
              profile?.invitationStatus == 'accepted');

      if (isPendingTenantAccount) {
        return profile;
      }

      if (profile == null || !profile.isActive) {
        if (Supabase.instance.client.auth.currentSession != null) {
          await Supabase.instance.client.auth.signOut();
        }
        return null;
      }

      return profile;
    } catch (_) {
      // If the app profile cannot be read, do not grant access to either
      // module. The user can sign in again after the connection is restored.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppAuthProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;
        if (profile?.accountType == AppAccountType.owner ||
            profile?.accountType == AppAccountType.provider) {
          return cleaning.RentalAppDemo(backend: IntegratedBackend.instance);
        }
        if (profile?.accountType == AppAccountType.admin) {
          return const AdminModuleShell();
        }
        if (profile?.accountType == AppAccountType.tenant &&
            profile?.accountStatus == 'pending' &&
            profile?.invitationStatus == 'invited') {
          return const TenantSetPasswordPage();
        }
        if (profile?.accountType == AppAccountType.tenant &&
            profile?.accountStatus == 'pending' &&
            profile?.invitationStatus == 'accepted') {
          return const TenantVerificationPage();
        }
        if (profile?.accountType == AppAccountType.tenant) {
          return const TenantModuleShell();
        }
        return const LoginPage();
      },
    );
  }
}
