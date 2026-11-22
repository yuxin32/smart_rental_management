// lib/widgets/app_drawer.dart
// App-wide drawer with profile header, primary nav, theme switch, and footer for sign-out.

import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../services/user_session.dart';
import 'message_unread_scope.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.role, required this.onNavigate});
  final String role; // 'Owner' or 'Provider'
  final void Function(String routeId) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, thickness: 1),
            Expanded(child: _buildNavList(context)),
            const Divider(height: 1, thickness: 1),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isOwner = role == 'Owner';
    final connected = AppProviders.of(context).backend != null;
    final session = connected ? UserSessionAccess.of(context) : null;
    final name = connected
        ? session!.displayName
        : isOwner
            ? 'Oh Wan Ting'
            : 'Provider A';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(gradient: AppTheme.heroGradient(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(
                    connected
                        ? (name.isEmpty
                            ? '?'
                            : name.substring(0, 1).toUpperCase())
                        : isOwner
                            ? 'OW'
                            : 'PA',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connected
                          ? (isOwner ? 'Property Owner' : 'Service Provider')
                          : isOwner
                              ? 'Owner - Menara Suria'
                              : 'Cleaning Service Provider',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Color(0xFF10B981), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(
                  connected
                      ? 'Signed-in account'
                      : isOwner
                          ? '5 properties managed'
                          : 'Online - accepting jobs',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavList(BuildContext context) {
    final ownerItems = [
      ('home', Icons.dashboard, 'Dashboard'),
      ('schedule', Icons.calendar_today, 'Schedule'),
      ('properties', Icons.apartment, 'Properties'),
      ('browse', Icons.person_search, 'Browse providers'),
      ('spend', Icons.payments, 'Spending'),
      ('messages', Icons.chat_bubble_outline, 'Messages'),
      ('notifications', Icons.notifications, 'Notifications'),
      ('profile', Icons.person, 'Profile & settings'),
      ('about', Icons.info_outline, 'About & help'),
    ];
    final providerItems = [
      ('inbox', Icons.inbox, 'Job inbox'),
      ('schedule', Icons.calendar_today, 'My schedule'),
      ('earnings', Icons.account_balance_wallet, 'Earnings'),
      ('profile', Icons.person_outline, 'View profile'),
      ('edit_profile', Icons.edit, 'Edit profile'),
      ('messages', Icons.chat_bubble_outline, 'Messages'),
      ('stats', Icons.insights, 'My stats'),
      ('notifications', Icons.notifications, 'Notifications'),
      ('about', Icons.info_outline, 'About & help'),
    ];
    final items = role == 'Owner' ? ownerItems : providerItems;
    final sem = SemanticColors.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: items.map((it) {
        return ListTile(
          leading: it.$1 == 'messages'
              ? MessageUnreadBadge(
                  child: Icon(it.$2, size: 20, color: sem.textPrimary))
              : Icon(it.$2, size: 20, color: sem.textPrimary),
          title: Text(it.$3,
              style: TextStyle(fontSize: 14, color: sem.textPrimary)),
          onTap: () {
            Navigator.of(context).pop();
            onNavigate(it.$1);
          },
        );
      }).toList(),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final sem = SemanticColors.of(context);
    final backend = AppProviders.of(context).backend;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Builder(builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return ListTile(
              leading: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 20,
                color: sem.textSecondary,
              ),
              title: Text(
                isDark ? 'Light mode' : 'Dark mode',
                style: TextStyle(fontSize: 14, color: sem.textPrimary),
              ),
              trailing: Switch(
                value: isDark,
                onChanged: (_) => AppProviders.of(ctx).onToggleTheme(),
                activeColor: Theme.of(context).colorScheme.secondary,
              ),
              onTap: () => AppProviders.of(ctx).onToggleTheme(),
              dense: true,
            );
          }),
          if (backend == null)
            ListTile(
              leading:
                  Icon(Icons.swap_horiz, size: 20, color: sem.textSecondary),
              title: Text('Switch role',
                  style: TextStyle(fontSize: 14, color: sem.textPrimary)),
              onTap: () {
                Navigator.of(context).pop();
                onNavigate('switch-role');
              },
              dense: true,
            ),
          ListTile(
            leading: Icon(Icons.logout,
                size: 20, color: Theme.of(context).colorScheme.error),
            title: Text('Sign out',
                style: TextStyle(
                    fontSize: 14, color: Theme.of(context).colorScheme.error)),
            onTap: () {
              Navigator.of(context).pop();
              if (backend != null) {
                onNavigate('sign-out');
                return;
              }
              UserSessionAccess.of(context).signOut();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            dense: true,
          ),
          const SizedBox(height: 8),
          Text(
            backend != null
                ? 'Smart Rental'
                : 'Smart Rental',
            style: TextStyle(fontSize: 11, color: sem.textTertiary),
          ),
        ],
      ),
    );
  }
}
