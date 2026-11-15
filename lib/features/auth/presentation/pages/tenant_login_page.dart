import 'package:flutter/material.dart';

import '../../../../core/auth/app_auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'role_login_page.dart';

class TenantLoginPage extends StatelessWidget {
  const TenantLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleLoginPage(
      expectedRole: AppAccountType.tenant,
      title: 'Tenant Login',
      subtitle: 'Access your rental information and apartment services.',
      icon: Icons.person_outline_rounded,
      accentColor: AppColors.primary,
    );
  }
}
