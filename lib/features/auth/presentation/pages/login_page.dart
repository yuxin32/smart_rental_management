import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'admin_login_page.dart';
import 'tenant_login_page.dart';

/// Entry screen for choosing the correct role-specific login interface.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.headerStart, AppColors.headerEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 40, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.18),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(
                    Icons.home_work_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  'Welcome to',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.82),
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Smart Rental Management',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Choose the sign-in area that matches your role.',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.82),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sign in as',
                        style: TextStyle(
                          color: AppColors.heading,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Your account is managed by Supabase Authentication. Select the workspace you need to access.',
                        style: TextStyle(
                          color: AppColors.body,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _RoleLoginCard(
                        icon: Icons.person_outline_rounded,
                        title: 'Tenant Login',
                        description:
                            'View bills, electricity consumption, payment records, maintenance requests, and communication.',
                        accentColor: AppColors.primary,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TenantLoginPage(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RoleLoginCard(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Administrator Login',
                        description:
                            'Manage tenant accounts, unit assignments, readings, billing, maintenance, announcements, and communication.',
                        accentColor: const Color(0xFF7D55C7),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminLoginPage(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Row(
                          children: [
                            _InfoIcon(),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Use the login area assigned to your account. Tenant and administrator access are checked separately after sign-in.',
                                style: TextStyle(
                                  color: AppColors.body,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleLoginCard extends StatelessWidget {
  const _RoleLoginCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFF),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.heading,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.body,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.arrow_forward_ios_rounded, color: accentColor, size: 17),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoIcon extends StatelessWidget {
  const _InfoIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFFDCE8FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Icon(
        Icons.manage_accounts_outlined,
        color: AppColors.primary,
        size: 24,
      ),
    );
  }
}
