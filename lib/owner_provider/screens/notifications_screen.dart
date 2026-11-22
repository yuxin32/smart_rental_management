// lib/screens/notifications_screen.dart
// Activity feed: shows recent events (booking state changes, new requests,
// payment confirmations, etc). Shared between Owner and Provider roles.
//
// Round 11 polish (NS1-NS6):
//   NS1 Theme colors throughout (sem.* + AppColors.*)
//   NS2 Filter chip uses AppColors.primary for active state
//   NS3 Unread tile bg uses sem.primarySurface / primarySurfaceDark
//   NS4 Unread dot uses AppColors.primary
//   NS5 Notification icons use semantic color tokens (statusInProgress, statusCompleted, etc.)
//   NS6 Time-ago uses sem.textTertiary

import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../services/backend/notification_binding.dart';
import '../services/backend/notification_snapshot.dart';
import '../widgets/snapshot_refresh_notice.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.color,
    this.read = false,
    this.actionable = false,
    this.bookingId,
  });
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final Color color;
  final bool read;
  final bool actionable;
  final String? bookingId;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen(
      {super.key, this.role = 'Owner', this.binding, this.onOpenBooking});
  final String role; // 'Owner' or 'Provider'
  final NotificationBinding? binding;
  final Future<void> Function(String)? onOpenBooking;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late List<NotificationItem> _items;
  String _filter = 'all'; // all, unread, action
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _items = widget.binding == null ? _seed() : [];
  }

  List<NotificationItem> _seed() {
    final now = DateTime.now();
    if (widget.role == 'Owner') {
      return [
        NotificationItem(
          id: 'n1',
          icon: Icons.notifications_active,
          title: 'Provider response pending',
          subtitle: 'Unit C-21 · Routine cleaning · 18 Jul 09:00',
          timestamp: now.subtract(const Duration(minutes: 12)),
          color: AppColors.statusRequested,
          read: false,
          actionable: true,
        ),
        NotificationItem(
          id: 'n2',
          icon: Icons.check_circle,
          title: 'Booking completed',
          subtitle: 'Unit D-03 · Move-in cleaning by Provider C',
          timestamp: now.subtract(const Duration(hours: 2)),
          color: AppColors.statusCompleted,
          read: false,
        ),
        NotificationItem(
          id: 'n3',
          icon: Icons.play_circle,
          title: 'Cleaning started',
          subtitle: 'Provider A started Unit A-12 at 10:00',
          timestamp: now.subtract(const Duration(hours: 3)),
          color: AppColors.statusInProgress,
          read: true,
        ),
        NotificationItem(
          id: 'n4',
          icon: Icons.event_available,
          title: 'Booking accepted',
          subtitle: 'Provider B accepted Unit B-08 for 16 Jul 14:00',
          timestamp: now.subtract(const Duration(hours: 5)),
          color: AppColors.statusAccepted,
          read: true,
        ),
        NotificationItem(
          id: 'n5',
          icon: Icons.star,
          title: 'New review from tenant',
          subtitle: 'Unit A-12 rated 4.8 stars after last cleaning',
          timestamp: now.subtract(const Duration(days: 1)),
          color: AppColors.warning,
          read: true,
        ),
        NotificationItem(
          id: 'n6',
          icon: Icons.payment,
          title: 'Payment processed',
          subtitle: 'RM 240 to Provider A for b-001',
          timestamp: now.subtract(const Duration(days: 1, hours: 4)),
          color: AppColors.success,
          read: true,
        ),
        NotificationItem(
          id: 'n7',
          icon: Icons.event,
          title: 'Upcoming cleaning reminder',
          subtitle: 'Provider C is assigned to Unit D-03 at 13:00',
          timestamp: now.subtract(const Duration(days: 2)),
          color: AppColors.statusAccepted,
          read: true,
        ),
      ];
    } else {
      // Provider notifications
      return [
        NotificationItem(
          id: 'n1',
          icon: Icons.notifications_active,
          title: 'New job request from Oh Wan Ting',
          subtitle: 'Unit C-21 · Routine cleaning · 18 Jul 09:00',
          timestamp: now.subtract(const Duration(minutes: 12)),
          color: AppColors.primary,
          read: false,
          actionable: true,
        ),
        NotificationItem(
          id: 'n2',
          icon: Icons.attach_money,
          title: 'Earnings paid out',
          subtitle: 'RM 240 deposited to your account',
          timestamp: now.subtract(const Duration(hours: 6)),
          color: AppColors.success,
          read: false,
        ),
        NotificationItem(
          id: 'n3',
          icon: Icons.star,
          title: 'You got a 5-star review',
          subtitle: '"Excellent work, very thorough." · Unit A-12',
          timestamp: now.subtract(const Duration(days: 1)),
          color: AppColors.warning,
          read: true,
        ),
        NotificationItem(
          id: 'n4',
          icon: Icons.cancel,
          title: 'Booking cancelled by owner',
          subtitle: 'Unit E-15 · 19 Jul 10:00 · refunded in full',
          timestamp: now.subtract(const Duration(days: 2)),
          color: AppColors.error,
          read: true,
        ),
      ];
    }
  }

  List<NotificationItem> get _filtered {
    if (widget.binding != null)
      return widget.binding!.snapshot?.items.map(_project).toList() ?? [];
    switch (_filter) {
      case 'unread':
        return _items.where((n) => !n.read).toList();
      case 'action':
        return _items.where((n) => n.actionable).toList();
      default:
        return _items;
    }
  }

  NotificationItem _project(BookingNotification n) {
    final (icon, color, title) = switch (n.status) {
      'Pending' => (
          Icons.notifications_active,
          AppColors.statusRequested,
          widget.role == 'Provider'
              ? 'New job request'
              : 'Booking request updated'
        ),
      'Accepted' => (
          Icons.event_available,
          AppColors.statusAccepted,
          'Booking accepted'
        ),
      'In Progress' => (
          Icons.play_circle,
          AppColors.statusInProgress,
          'Cleaning started'
        ),
      'Completed' => (
          Icons.check_circle,
          AppColors.statusCompleted,
          'Booking completed'
        ),
      'Declined' => (
          Icons.cancel_outlined,
          AppColors.error,
          'Booking declined'
        ),
      _ => (Icons.cancel, AppColors.error, 'Booking cancelled')
    };
    return NotificationItem(
        id: n.id,
        bookingId: n.bookingId,
        icon: icon,
        color: color,
        title: title,
        subtitle: '${n.unit}, ${n.building} · ${n.service}',
        timestamp: n.timestamp,
        read: n.read,
        actionable: n.actionable);
  }

  Future<void> _markAllRead() async {
    final binding = widget.binding;
    if (binding != null) {
      final saved = await binding.read(all: true);
      if (mounted && saved)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Current notifications marked as read')));
      return;
    }
    setState(() {
      _items = _items
          .map((n) => NotificationItem(
                id: n.id,
                icon: n.icon,
                title: n.title,
                subtitle: n.subtitle,
                timestamp: n.timestamp,
                color: n.color,
                read: true,
                actionable: n.actionable,
              ))
          .toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications marked as read'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleTap(NotificationItem n) async {
    final binding = widget.binding;
    if (binding != null) {
      if (_opening ||
          binding.busy ||
          binding.sessionEnded ||
          widget.onOpenBooking == null) return;
      setState(() => _opening = true);
      try {
        if (!n.read) await binding.read(id: n.id);
        if (mounted && !binding.sessionEnded && binding.error == null)
          await widget.onOpenBooking!(n.bookingId!);
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Could not open booking. Pull down and try again.')));
      } finally {
        if (mounted) setState(() => _opening = false);
      }
      return;
    }
    setState(() {
      _items = _items.map((x) {
        if (x.id != n.id) return x;
        return NotificationItem(
          id: x.id,
          icon: x.icon,
          title: x.title,
          subtitle: x.subtitle,
          timestamp: x.timestamp,
          color: x.color,
          read: true,
          actionable: x.actionable,
        );
      }).toList();
    });
    if (n.actionable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opening: ${n.title}'),
          backgroundColor: n.color,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    return binding == null
        ? _buildScreen(context)
        : AnimatedBuilder(
            animation: binding, builder: (_, __) => _buildScreen(context));
  }

  Widget _buildScreen(BuildContext context) {
    final binding = widget.binding;
    final sem = SemanticColors.of(context);
    final unreadCount = binding?.snapshot?.unread ??
        (binding == null ? _items.where((n) => !n.read).length : 0);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            IconButton(
              tooltip: 'Mark all read',
              onPressed: binding != null &&
                      (binding.loading || binding.busy || binding.loadingMore)
                  ? null
                  : _markAllRead,
              icon: const Icon(Icons.done_all),
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(48 +
              (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) * 24),
          child: Container(
            color: sem.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                        'all',
                        'All',
                        binding?.snapshot?.total ??
                            (binding == null ? _items.length : 0),
                        sem),
                    const SizedBox(width: 8),
                    _filterChip('unread', 'Unread', unreadCount, sem),
                    const SizedBox(width: 8),
                    _filterChip(
                      'action',
                      'Needs action',
                      binding?.snapshot?.actions ??
                          (binding == null
                              ? _items.where((n) => n.actionable).length
                              : 0),
                      sem,
                    ),
                  ],
                )),
          ),
        ),
      ),
      body: binding != null
          ? _connectedBody(binding, isDark)
          : _filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none,
                  title: 'No notifications',
                  subtitle: 'You are all caught up.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 64,
                    color: sem.border,
                  ),
                  itemBuilder: (ctx, i) => _NotificationTile(
                    item: _filtered[i],
                    isDark: isDark,
                    onTap: () => _handleTap(_filtered[i]),
                  ),
                ),
    );
  }

  Widget _connectedBody(NotificationBinding binding, bool isDark) {
    final items = _filtered;
    final unavailable = binding.error != null || binding.sessionEnded;
    final state = unavailable
        ? EmptyState(
            icon: Icons.cloud_off,
            title: binding.sessionEnded
                ? 'Sign in again'
                : 'Could not load notifications',
            subtitle: binding.sessionEnded
                ? 'Your account session changed.'
                : 'Pull down to retry.')
        : binding.snapshot == null && binding.loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()))
            : EmptyState(
                icon: Icons.notifications_none,
                title: 'No notifications',
                subtitle: binding.filter == NotificationFilter.all
                    ? 'Booking updates will appear here.'
                    : binding.filter == NotificationFilter.unread
                        ? 'No unread notifications.'
                        : 'No notifications currently need action.');
    return RefreshIndicator(
        onRefresh: binding.refresh,
        child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                      'Booking updates inside the app. Device push notifications are not enabled.',
                      style: TextStyle(fontSize: 12))),
              SnapshotRefreshNotice(
                  refreshing: binding.loading,
                  failed: binding.refreshError != null,
                  onRetry: binding.refresh),
              if (binding.writeError != null)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Could not confirm read status. Pull down to check saved status before retrying.')),
              if (binding.liveError != null)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Live updates interrupted. Pull down to check current notifications.')),
              if (unavailable || items.isEmpty)
                state
              else
                ...items.map((n) => Column(children: [
                      _NotificationTile(
                          item: n, isDark: isDark, onTap: () => _handleTap(n)),
                      const Divider(height: 1, indent: 64)
                    ])),
              if (binding.moreError != null)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Could not load older notifications.')),
              if (binding.snapshot?.next != null)
                TextButton(
                    onPressed:
                        binding.loadingMore || binding.loading || binding.busy
                            ? null
                            : binding.loadMore,
                    child: Text(binding.loadingMore
                        ? 'Loading older notifications…'
                        : 'Load older notifications')),
            ]));
  }

  // NS2: themed filter chip
  Widget _filterChip(String id, String label, int count, SemanticColors sem) {
    final active = _filter == id;
    return InkWell(
      onTap: widget.binding?.busy == true
          ? null
          : () {
              setState(() => _filter = id);
              widget.binding?.select(NotificationFilter.values.byName(id));
            },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : sem.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : sem.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color:
                    active ? Colors.white.withOpacity(0.2) : sem.borderStrong,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : sem.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.isDark,
    required this.onTap,
  });
  final NotificationItem item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preferences = AppProviders.maybeOf(context)?.devicePreferences;
    return AnimatedBuilder(
        animation: Listenable.merge([if (preferences != null) preferences]),
        builder: (context, _) =>
            _contents(context, preferences?.bookingIndicators != false));
  }

  Widget _contents(BuildContext context, bool enabled) {
    final highlight = enabled && !item.read;
    final sem = SemanticColors.of(context);
    // NS3: themed unread background (primary surface in both modes)
    final unreadBg = isDark
        ? AppColors.primarySurfaceDark
        : AppColors.primarySurface.withOpacity(0.6);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: highlight ? unreadBg : sem.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                highlight ? FontWeight.w700 : FontWeight.w500,
                            color: sem.textPrimary,
                          ),
                        ),
                      ),
                      // NS4: themed unread dot
                      if (highlight)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: sem.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimeAgo(item.timestamp),
                    // NS6: themed time-ago
                    style: TextStyle(fontSize: 11, color: sem.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
