import 'package:flutter/material.dart';

import '../../../../core/auth/app_logout_button.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/admin_preview_data.dart';
import '../widgets/admin_ui.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({this.onNavigateToTab, super.key});

  final ValueChanged<int>? onNavigateToTab;

  void _openTab(BuildContext context, int index, String label) {
    if (onNavigateToTab != null) {
      onNavigateToTab!(index);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label will be connected soon.')));
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _AdminHeader()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overview',
                  style: TextStyle(
                    color: AppColors.heading,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 13),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.22,
                  children: const [
                    AdminMetricCard(
                      label: 'Occupied units',
                      value: '86 / 100',
                      icon: Icons.home_work_outlined,
                      color: Color(0xFF5D75E4),
                    ),
                    AdminMetricCard(
                      label: 'Outstanding bills',
                      value: '12',
                      icon: Icons.receipt_long_outlined,
                      color: Color(0xFFEF9B58),
                    ),
                    AdminMetricCard(
                      label: 'Open requests',
                      value: '5',
                      icon: Icons.build_outlined,
                      color: Color(0xFF4EA98A),
                    ),
                    AdminMetricCard(
                      label: 'Unread messages',
                      value: '3',
                      icon: Icons.mark_unread_chat_alt_outlined,
                      color: Color(0xFF7C68D8),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Needs attention',
                        style: TextStyle(
                          color: AppColors.heading,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openTab(context, 3, 'Requests'),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AdminCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AdminIconBox(
                        icon: Icons.warning_amber_rounded,
                        color: Color(0xFFE8953E),
                        backgroundColor: Color(0xFFFFF0D7),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '1 electricity reading needs review',
                              style: TextStyle(
                                color: AppColors.heading,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'DDSU666 meter · Block A-12-08 · 19 Mar 2026',
                              style: TextStyle(
                                color: AppColors.body,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9CA4B3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 25),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.headerStart, AppColors.headerEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good morning,',
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.82),
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  AdminPreviewData.administratorName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  AdminPreviewData.propertyName,
                  style: TextStyle(
                    color: Color.fromRGBO(255, 255, 255, 0.84),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const AppLogoutButton(
            foregroundColor: Colors.white,
            backgroundColor: Color.fromRGBO(255, 255, 255, 0.18),
          ),
        ],
      ),
    );
  }
}
