import 'package:flutter/material.dart';

import '../../../../core/auth/app_auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import 'role_login_page.dart';

class AdminLoginPage extends StatelessWidget {
  const AdminLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleLoginPage(
      expectedRole: AppAccountType.admin,
      title: 'Administrator Login',
      subtitle: 'Manage apartment rental operations from your admin workspace.',
      icon: Icons.admin_panel_settings_outlined,
      accentColor: AppColors.primary,
    );
  }
}
