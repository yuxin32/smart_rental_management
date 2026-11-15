import 'package:flutter/material.dart';

import '../widgets/admin_navigation_bar.dart';
import 'admin_billing_page.dart';
import 'admin_communication_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_maintenance_page.dart';
import 'admin_tenants_page.dart';

class AdminModuleShell extends StatefulWidget {
  const AdminModuleShell({super.key});

  @override
  State<AdminModuleShell> createState() => _AdminModuleShellState();
}

class _AdminModuleShellState extends State<AdminModuleShell> {
  late final List<Widget> _pages;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pages = [
      AdminDashboardPage(onNavigateToTab: _selectTab),
      const AdminTenantsPage(),
      const AdminBillingPage(),
      const AdminMaintenancePage(),
      const AdminCommunicationPage(),
    ];
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: AdminNavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
      ),
    );
  }
}
