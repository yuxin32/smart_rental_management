import 'package:supabase_flutter/supabase_flutter.dart';

enum AppAccountType { tenant, admin, owner, provider, unknown }

class AppAuthProfile {
  const AppAuthProfile({
    required this.accountType,
    required this.accountStatus,
    required this.invitationStatus,
    required this.adminIsActive,
    required this.tenantVerificationStatus,
  });

  final AppAccountType accountType;
  final String accountStatus;
  final String invitationStatus;
  final bool adminIsActive;
  final String tenantVerificationStatus;

  bool get isActive {
    return accountStatus == 'active' &&
        (accountType != AppAccountType.admin || adminIsActive);
  }
}

abstract final class AppAuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<AppAuthProfile?> loadCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final record = await _client
        .from('user_account')
        .select('role, account_status, invitation_status')
        .eq('user_id', user.id)
        .maybeSingle();

    if (record == null) return null;

    final accountType = switch (record['role'] as String?) {
      'tenant' => AppAccountType.tenant,
      'admin' => AppAccountType.admin,
      'owner' => AppAccountType.owner,
      'provider' => AppAccountType.provider,
      _ => AppAccountType.unknown,
    };

    var adminIsActive = true;
    var tenantVerificationStatus = 'pending';
    if (accountType == AppAccountType.admin) {
      final adminRecord = await _client
          .from('admin')
          .select('is_active')
          .eq('admin_id', user.id)
          .maybeSingle();
      adminIsActive = adminRecord?['is_active'] == true;
    } else if (accountType == AppAccountType.tenant) {
      final tenantRecord = await _client
          .from('tenant')
          .select('verification_status')
          .eq('tenant_id', user.id)
          .maybeSingle();
      tenantVerificationStatus =
          tenantRecord?['verification_status'] as String? ?? 'pending';
    }

    return AppAuthProfile(
      accountType: accountType,
      accountStatus: record['account_status'] as String? ?? 'unknown',
      invitationStatus:
          record['invitation_status'] as String? ?? 'not_invited',
      adminIsActive: adminIsActive,
      tenantVerificationStatus: tenantVerificationStatus,
    );
  }
}
