import 'package:flutter/material.dart';

import '../widgets/tenant_navigation_bar.dart';
import 'tenant_communication_page.dart';
import 'tenant_devices_page.dart';
import 'tenant_home_page.dart';
import 'tenant_maintenance_page.dart';
import 'tenant_payments_page.dart';

class TenantModuleShell extends StatefulWidget {
  const TenantModuleShell({super.key});

  @override
  State<TenantModuleShell> createState() => _TenantModuleShellState();
}

class _TenantModuleShellState extends State<TenantModuleShell> {
  late final List<Widget> _pages;
  final _homeKey = GlobalKey<TenantHomePageState>();
  final _maintenanceKey = GlobalKey<TenantMaintenancePageState>();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pages = [
      TenantHomePage(key: _homeKey, onNavigateToTab: _selectTab),
      const TenantPaymentsPage(),
      const TenantDevicesPage(),
      TenantMaintenancePage(key: _maintenanceKey),
      const TenantCommunicationPage(),
    ];
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) _homeKey.currentState?.refresh();
    if (index == 3) _maintenanceKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: _pages),
      ),
      bottomNavigationBar: TenantNavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
      ),
    );
  }
}
