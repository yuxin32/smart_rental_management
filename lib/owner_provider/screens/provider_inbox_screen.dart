// lib/screens/provider_inbox_screen.dart
// Original provider workspace with an optional authenticated server binding.
// The caller owns the binding's refresh, active state and disposal lifecycle.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../services/backend/workspace_binding.dart';
import '../widgets/snapshot_refresh_notice.dart';
import '../services/booking_store.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/provider_workspace_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/coach_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/status_chip.dart';
import '../widgets/workspace_actions.dart';
import 'about_screen.dart';
import 'earnings_history_screen.dart';
import 'chat_list_screen.dart';
import 'notifications_screen.dart';
import 'provider_edit_profile_screen.dart';
import 'provider_job_detail_screen.dart';
import 'provider_profile_screen.dart';
import 'provider_schedule_screen.dart';
import 'provider_stats_screen.dart';

class ProviderInboxScreen extends StatefulWidget {
  const ProviderInboxScreen({
    super.key,
    this.provider,
    this.showShell = true,
    this.binding,
    this.actions,
  });
  // Preview identity only; connected bookings are already scoped by server RLS.
  final DemoProvider? provider;
  final bool showShell;
  final WorkspaceBinding? binding;
  final WorkspaceActions? actions;

  @override
  State<ProviderInboxScreen> createState() => _ProviderInboxScreenState();
}

class _ProviderInboxScreenState extends State<ProviderInboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _navTab = 'inbox';
  FilterResult _filter = FilterResult.empty;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  bool get _connected => widget.binding != null;

  List<DemoBooking> get _bookings {
    final binding = widget.binding;
    if (binding == null) return AppProviders.of(context).bookingStore.bookings;
    // error checks projection validity. Do not evaluate a malformed card again.
    if (binding.error != null) return const [];
    return binding.bookings;
  }

  bool get _partial =>
      _connected &&
      (widget.binding!.hasMore ||
          widget.binding!.loading ||
          widget.binding!.error != null);
  bool get _countsKnown =>
      !_connected ||
      (widget.binding!.error == null &&
          (_bookings.isNotEmpty || !widget.binding!.loading));

  String _count(int count) =>
      !_countsKnown ? '—' : '$count${_partial ? '+' : ''}';

  String get _approval {
    switch (widget.binding?.providerProfile?['approval_status']) {
      case 'approved':
        return 'Approved';
      case 'pending':
        return 'Approval pending';
      case 'rejected':
        return 'Not approved';
      case 'suspended':
        return 'Suspended';
      default:
        return 'Approval unavailable';
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DemoBooking> _filterBookings(List<DemoBooking> source, _InboxTab tab) {
    // Display-name ownership exists only in the local preview.
    var out = _connected
        ? source.toList()
        : source
            .where(
              (b) => b.providerName == (widget.provider?.name ?? 'Provider A'),
            )
            .toList();
    if (tab == _InboxTab.newRequests) {
      out = out.where((b) => b.status == BookingStatus.pending).toList();
    } else if (tab == _InboxTab.active) {
      out = out
          .where(
            (b) =>
                b.status == BookingStatus.accepted ||
                b.status == BookingStatus.inProgress,
          )
          .toList();
    } else if (tab == _InboxTab.completed) {
      out = out.where((b) => b.status == BookingStatus.completed).toList();
    }
    out = applyFilter(out, _filter);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      out = out
          .where(
            (b) =>
                b.property.toLowerCase().contains(q) ||
                b.serviceType.toLowerCase().contains(q),
          )
          .toList();
    }
    return out;
  }

  void _unavailable(String label) {
    final actions = widget.actions;
    if (actions != null) {
      actions.unavailable(context, label);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label is not connected yet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDetail(DemoBooking b) async {
    if (!_connected) {
      final current = AppProviders.of(context).bookingStore.byId(b.id) ?? b;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProviderJobDetailScreen(
            booking: current,
            provider: widget.provider,
          ),
        ),
      );
      return;
    }
    Haptics.light();
    final actions = widget.actions;
    if (widget.binding == null || actions == null) {
      _unavailable('Booking details');
      return;
    }
    try {
      await actions.booking(context, b.id);
      if (mounted) await widget.binding?.refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open this booking. Please try again.'),
        ));
      }
    }
  }

  Future<void> _onDrawerNav(String id) async {
    if (!_connected) {
      await _onPreviewNav(id);
      return;
    }
    switch (id) {
      case 'inbox':
        setState(() => _navTab = 'inbox');
        break;
      case 'schedule':
        final actions = widget.actions;
        if (actions != null) {
          try {
            await actions.schedule(context);
          } catch (_) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Could not open schedule. Please try again.')));
          }
        } else {
          _unavailable('Schedule');
        }
        break;
      case 'profile':
      case 'edit_profile':
        final actions = widget.actions;
        if (widget.binding != null && actions != null) {
          try {
            await actions.profile(context, edit: id == 'edit_profile');
            if (mounted) await widget.binding?.refresh();
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Could not open profile. Please try again.'),
              ));
            }
          }
        } else {
          _unavailable('Provider profile');
        }
        break;
      case 'earnings':
        final actions = widget.actions;
        if (actions != null) {
          try {
            await actions.earnings(context);
          } catch (_) {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Could not open earnings. Please try again.')));
          }
        } else {
          _unavailable('Earnings');
        }
        break;
      case 'sign-out':
      case 'signout':
        final actions = widget.actions;
        if (actions != null) {
          await actions.signOut(context);
        } else {
          _unavailable('Sign out');
        }
        break;
      case 'notifications':
      case 'messages':
      case 'stats':
      case 'about':
        final actions = widget.actions;
        if (actions == null) {
          _unavailable(id == 'about'
              ? 'About & help'
              : id == 'messages'
                  ? 'Messages'
                  : 'Notifications');
          break;
        }
        try {
          if (id == 'about') {
            await actions.about(context);
          } else if (id == 'messages') {
            await actions.messages(context);
          } else if (id == 'stats') {
            await actions.statistics(context);
          } else {
            await actions.notifications(context);
          }
        } catch (_) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Could not open this page. Please try again.')));
        }
        break;
      default:
        _unavailable(
          switch (id) {
            'schedule' => 'Schedule',
            'earnings' => 'Earnings',
            'messages' => 'Messages',
            'stats' => 'Provider statistics',
            'notifications' => 'Notifications',
            'about' => 'About & help',
            'switch-role' => 'Switch role',
            _ => id,
          },
        );
        break;
    }
  }

  // Preview actions remain isolated from the connected workspace.
  void _accept(DemoBooking b, BookingStore store) {
    Haptics.medium();
    final result = store.acceptPending(b.id);
    if (result.accepted) {
      final acceptedBooking = store.byId(b.id) ?? b;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Accepted ${b.property}'),
          backgroundColor: AppColors.positive,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () => _openDetail(acceptedBooking),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.negative,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _decline(DemoBooking b, BookingStore store) {
    Haptics.heavy();
    if (store.declineBooking(b.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Declined ${b.property}'),
          backgroundColor: AppColors.negative,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onPreviewNav(String id, {bool bottomNav = false}) async {
    final app = AppProviders.of(context);
    switch (id) {
      case 'inbox':
        setState(() => _navTab = 'inbox');
        break;
      case 'schedule':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProviderScheduleScreen(
              providerName: widget.provider?.name ?? 'Provider A',
              bookings: app.bookingStore.bookings,
            ),
          ),
        );
        break;
      case 'earnings':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EarningsHistoryScreen(
              providerName: widget.provider?.name ?? 'Provider A',
              bookings: app.bookingStore.bookings,
              providers: app.providerStore.providers,
            ),
          ),
        );
        break;
      case 'profile':
        if (!bottomNav) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderProfileScreen(
                provider: widget.provider ?? DemoProvider.seeded().first,
              ),
            ),
          );
          break;
        }
        await _onPreviewNav('edit_profile');
        break;
      case 'edit_profile':
        final current =
            app.providerStore.currentProvider ?? DemoProvider.seeded().first;
        final updated = await Navigator.of(context).push<DemoProvider>(
          MaterialPageRoute(
            builder: (_) => ProviderEditProfileScreen(provider: current),
          ),
        );
        if (updated != null && mounted) setState(() {});
        break;
      case 'messages':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ChatListScreen()));
        break;
      case 'stats':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProviderStatsScreen()),
        );
        break;
      case 'about':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                AboutScreen(prototypeSupport: app.prototypeSupport)));
        break;
      case 'notifications':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const NotificationsScreen(role: 'Provider'),
          ),
        );
        break;
    }
    if (bottomNav && mounted) setState(() => _navTab = 'inbox');
  }

  void _openFilter() async {
    Haptics.light();
    final all = _connected
        ? _bookings
        : _bookings.where(
            (b) => b.providerName == (widget.provider?.name ?? 'Provider A'),
          );
    final properties = all.map((b) => b.property).toSet().toList()..sort();
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FilterSheet(initial: _filter, properties: properties),
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    return AnimatedBuilder(
      animation: binding ?? AppProviders.of(context).bookingStore,
      builder: (ctx, _) {
        return _buildWorkspace(ctx);
      },
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    if (!widget.showShell) return _buildContent(context);
    return Scaffold(
      drawer: AppDrawer(role: 'Provider', onNavigate: _onDrawerNav),
      appBar: _buildAppBar(context),
      body: CoachMarkOverlay(
        setId: 'provider_inbox_v1',
        marks: [
          CoachMark(
            id: 'earnings',
            icon: Icons.account_balance_wallet,
            title: 'Your work at a glance',
            body: _connected
                ? 'Review loaded jobs below. Open Earnings for your completed-job value and history.'
                : "See this week's earnings, upcoming jobs, and incoming requests below your workspace card.",
            accent: AppColors.primary,
            alignment: CoachMarkAlignment.topLeft,
          ),
          CoachMark(
            id: 'tabs',
            icon: Icons.tab,
            title: '4 quick tabs',
            body: _connected
                ? 'Inbox / Schedule / Earnings / Profile. Unavailable sections are marked as not connected.'
                : 'Inbox / Schedule / Earnings / Profile. Tap a tab to navigate.',
            accent: AppColors.primary,
            alignment: CoachMarkAlignment.bottomCenter,
          ),
          CoachMark(
            id: 'accept',
            icon: Icons.check_circle,
            title:
                _connected ? 'Review incoming requests' : 'Accept in one tap',
            body: _connected
                ? 'Tap Review request to open booking details and respond securely.'
                : 'New job requests show here. Tap Accept to confirm, or Decline to pass.',
            accent: AppColors.primary,
            alignment: CoachMarkAlignment.topRight,
          ),
        ],
        child: _buildContent(context),
      ),
      bottomNavigationBar: ProviderBottomNav(
        activeId: _navTab,
        onChange: (id) async {
          Haptics.selection();
          if (_connected) {
            await _onDrawerNav(id);
          } else {
            await _onPreviewNav(id, bottomNav: true);
          }
        },
      ),
    );
  }

  // Original app bar and tabs, with counts qualified for partial feeds.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('Provider Inbox'),
      actions: [
        Builder(
          builder: (ctx) {
            final isDark2 = Theme.of(ctx).brightness == Brightness.dark;
            return IconButton(
              icon: Icon(
                isDark2 ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
              onPressed: () => AppProviders.of(ctx).onToggleTheme(),
              tooltip: isDark2 ? 'Switch to light mode' : 'Switch to dark mode',
            );
          },
        ),
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined),
              if (!_connected)
                const Positioned(top: -2, right: -2, child: _NotificationDot()),
            ],
          ),
          onPressed: () => _onDrawerNav('notifications'),
          tooltip: 'Notifications',
        ),
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: _openFilter,
          tooltip: 'Filter & sort',
        ),
        const SizedBox(width: 8),
      ],
      bottom: _buildTabs(context),
    );
  }

  TabBar _buildTabs(BuildContext context) => TabBar(
        controller: _tab,
        isScrollable: false,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: SemanticColors.of(context).textSecondary,
        indicatorColor: Theme.of(context).colorScheme.primary,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
            fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600),
        tabs: [
          Tab(
            text:
                'New (${_count(_filterBookings(_bookings, _InboxTab.newRequests).length)})',
          ),
          Tab(
            text:
                'Active (${_count(_filterBookings(_bookings, _InboxTab.active).length)})',
          ),
          Tab(
            text:
                'Done (${_count(_filterBookings(_bookings, _InboxTab.completed).length)})',
          ),
          const Tab(text: 'All'),
        ],
      );

  List<DemoBooking> storeForCount(BuildContext context) =>
      _connected ? _bookings : AppProviders.of(context).bookingStore.bookings;

  Widget _buildContent(BuildContext context) {
    final sem = SemanticColors.of(context);
    final content = NestedScrollView(
      physics: _connected ? const AlwaysScrollableScrollPhysics() : null,
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverToBoxAdapter(child: _buildEarningsSummary(context)),
        if (_connected) SliverToBoxAdapter(child: _buildFeedStatus(context)),
        if (_connected && !widget.showShell)
          SliverToBoxAdapter(child: _buildTabs(context)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            // PI2: themed search field
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search by property or service...',
                hintStyle: TextStyle(fontSize: 13, color: sem.textTertiary),
                prefixIcon:
                    Icon(Icons.search, size: 20, color: sem.textSecondary),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close,
                            size: 18, color: sem.textSecondary),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: sem.surface,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: sem.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: sem.border),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: AnimatedBuilder(
            animation: _tab,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 19, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  switch (_tab.index) {
                    0 => 'New requests',
                    1 => 'Active jobs',
                    2 => 'Completed jobs',
                    _ => 'All jobs',
                  },
                  style: TextStyle(
                    color: sem.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tab,
        children: [
          _buildList(context, _InboxTab.newRequests),
          _buildList(context, _InboxTab.active),
          _buildList(context, _InboxTab.completed),
          _buildList(context, _InboxTab.all),
        ],
      ),
    );
    final binding = widget.binding;
    if (binding == null) return content;
    // One refresh surface covers both the overview header and every job tab.
    // Nested scroll notifications include inner lists; ignore horizontal swipes.
    return RefreshIndicator(
      key: const ValueKey('provider-inbox-refresh'),
      onRefresh: binding.refresh,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      child: content,
    );
  }

  // Match the Owner home hierarchy: navy workspace hero, then quiet white
  // overview cards. Payment aggregates are not available from this feed.
  Widget _buildEarningsSummary(BuildContext context) {
    final providerName = widget.provider?.name ?? 'Provider A';
    final all = _connected
        ? _bookings
        : _bookings.where((b) => b.providerName == providerName).toList();
    final weeklyNet = _connected
        ? null
        : earningsFor(
            providerName,
            _bookings,
            providers: AppProviders.of(context).providerStore.providers,
          ).weeklyNet;
    final profile = widget.binding?.providerProfile;
    final rating = profile?['rating_average'];
    final completed = _connected
        ? (profile?['completed_job_count'])
        : all.where((b) => b.status == BookingStatus.completed).length;
    final upcoming = all
        .where(
          (b) =>
              b.status == BookingStatus.accepted ||
              b.status == BookingStatus.inProgress,
        )
        .length;
    final newReq = all.where((b) => b.status == BookingStatus.pending).length;
    final sem = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -54,
                  right: -48,
                  child: SizedBox(
                    width: 190,
                    height: 190,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0x3359C5C7)
                            : const Color(0xFF254684),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.work_outline,
                            color: AppColors.primaryLighter,
                            size: 27,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: !_connected ||
                                          profile?['approval_status'] ==
                                              'approved'
                                      ? AppColors.onlineDot
                                      : Colors.white70,
                                  size: 7,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _connected ? _approval : 'Online',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Your cleaning work, in one place.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _connected
                            ? 'Review requests and upcoming jobs.'
                            : '$providerName · Review requests and upcoming jobs.',
                        style: const TextStyle(
                          color: Color(0xFFD9E8FF),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      if (_connected) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Rating ${rating ?? '—'} · ${completed ?? '—'} completed jobs',
                          style: const TextStyle(
                            color: Color(0xFFD9E8FF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'At a glance',
            style: TextStyle(
              color: sem.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final earnings = _EarningsStat(
                label: _connected ? 'Earnings' : 'This week',
                value: _connected ? '—' : 'RM ${weeklyNet!.toStringAsFixed(0)}',
                sub: _connected ? 'Open Earnings' : '$completed done',
              );
              final upcomingStat = _EarningsStat(
                label: 'Active',
                value: _count(upcoming),
                sub: _connected ? 'loaded jobs' : 'jobs',
              );
              final newStat = _EarningsStat(
                label: 'New',
                value: _count(newReq),
                sub: _connected ? 'loaded requests' : 'requests',
              );
              if (constraints.maxWidth < 350) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: earnings),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: upcomingStat),
                        const SizedBox(width: 10),
                        Expanded(child: newStat),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 14, child: earnings),
                  const SizedBox(width: 10),
                  Expanded(flex: 10, child: upcomingStat),
                  const SizedBox(width: 10),
                  Expanded(flex: 10, child: newStat),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeedStatus(BuildContext context) {
    final binding = widget.binding;
    final sem = SemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            binding == null
                ? 'Inbox is not connected.'
                : 'Counts, search and filters cover loaded jobs only.${_partial ? ' + means more may be available.' : ''}',
            style: TextStyle(color: sem.textSecondary, fontSize: 12),
          ),
          if (binding != null) ...[
            SnapshotRefreshNotice(
                refreshing: binding.refreshing,
                failed: binding.refreshError != null,
                onRetry: binding.refresh),
            if (binding.loading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(semanticsLabel: 'Loading inbox'),
            ],
            if (binding.error != null)
              Text(
                'Could not load inbox. Pull down to try again.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (binding.liveError != null)
              TextButton.icon(
                onPressed: binding.retryLive,
                icon: const Icon(Icons.sync_problem, size: 18),
                label: const Text('Retry live updates'),
              ),
            if (binding.liveError != null)
              Text(
                'Live updates are interrupted. Refresh to check current job status.',
                style: TextStyle(color: sem.textSecondary, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaging(BuildContext context) {
    final binding = widget.binding;
    if (binding == null) return const SizedBox.shrink();
    if (binding.loadingMore) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(semanticsLabel: 'Loading more jobs'),
        ),
      );
    }
    if (!binding.hasMore && binding.moreError == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (binding.moreError != null)
          const Text(
            'Could not load more jobs. Loaded jobs are still available.',
            textAlign: TextAlign.center,
          ),
        TextButton.icon(
          onPressed: binding.loading ? null : binding.loadMore,
          icon: const Icon(Icons.expand_more),
          label: Text(
            binding.moreError != null ? 'Retry load more' : 'Load more jobs',
          ),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context, _InboxTab tab) {
    final binding = widget.binding;
    if (binding == null) return _buildPreviewList(context, tab);
    final items = _filterBookings(_bookings, tab);
    Widget? state;
    if (binding.error != null) {
      state = EmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load inbox',
        subtitle: 'Check your connection and try again.',
        action: TextButton(
          onPressed: binding.loading ? null : binding.refresh,
          child: const Text('Retry inbox'),
        ),
      );
    } else if (_bookings.isEmpty && binding.loading) {
      state = const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading job requests…'),
          ],
        ),
      );
    } else if (items.isEmpty) {
      final filtered = _searchQuery.isNotEmpty ||
          _filter.statusFilter != null ||
          _filter.propertyFilter != null;
      state = EmptyState(
        icon: tab == _InboxTab.newRequests
            ? Icons.inbox
            : tab == _InboxTab.completed
                ? Icons.task_alt
                : Icons.work_outline,
        title:
            _partial || filtered ? 'No matching loaded jobs' : _emptyTitle(tab),
        subtitle: _partial
            ? 'Load more jobs to check for other matches.'
            : filtered
                ? 'Try a different search or filter.'
                : _emptySubtitle(tab),
      );
    }
    final list = ListView.separated(
      key: PageStorageKey('provider-inbox-${tab.name}'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: (state != null ? 1 : items.length) + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final count = state != null ? 1 : items.length;
        if (i == count) return _buildPaging(ctx);
        if (state != null) return state;
        final b = items[i];
        return _ProviderJobCard(
          booking: b,
          onTap: () => _openDetail(b),
        );
      },
    );
    return list;
  }

  Widget _buildPreviewList(BuildContext context, _InboxTab tab) {
    final store = AppProviders.of(context).bookingStore;
    final items = _filterBookings(store.bookings, tab);
    if (items.isEmpty) {
      return EmptyState(
        icon: tab == _InboxTab.newRequests
            ? Icons.inbox
            : tab == _InboxTab.completed
                ? Icons.task_alt
                : Icons.work_outline,
        title: _emptyTitle(tab),
        subtitle: _emptySubtitle(tab),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final b = items[i];
        return _ProviderJobCard(
          booking: b,
          onTap: () => _openDetail(b),
          onAccept: () => _accept(b, store),
          onDecline: () => _decline(b, store),
        );
      },
    );
  }

  String _emptyTitle(_InboxTab tab) {
    switch (tab) {
      case _InboxTab.newRequests:
        return 'No new requests';
      case _InboxTab.active:
        return 'No active jobs';
      case _InboxTab.completed:
        return 'No completed jobs yet';
      case _InboxTab.all:
        return 'No jobs at all';
    }
  }

  String _emptySubtitle(_InboxTab tab) {
    switch (tab) {
      case _InboxTab.newRequests:
        return _connected
            ? 'New requests assigned to your account will appear here.'
            : "We'll ping you when an owner routes a request to you.";
      case _InboxTab.active:
        return _connected
            ? 'Review incoming requests in booking details.'
            : 'Accept a request or wait for one to be assigned.';
      case _InboxTab.completed:
        return 'Completed jobs will appear here for your records.';
      case _InboxTab.all:
        return _connected
            ? 'Pull to refresh to check for requests.'
            : 'Pull to refresh or check your notifications.';
    }
  }
}

enum _InboxTab { newRequests, active, completed, all }

class _NotificationDot extends StatelessWidget {
  const _NotificationDot();
  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration:
            const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
      );
}

// Light overview cards use the same surfaces and typography as Owner home.
class _EarningsStat extends StatelessWidget {
  const _EarningsStat({
    required this.label,
    required this.value,
    required this.sub,
  });
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: sem.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sem.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: sem.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: sem.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              color: sem.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ProviderJobCard extends StatelessWidget {
  const _ProviderJobCard({
    required this.booking,
    required this.onTap,
    this.onAccept,
    this.onDecline,
  });
  final DemoBooking booking;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final canRespond = booking.status == BookingStatus.pending;
    return Material(
      color: sem.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: sem.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: sem.primarySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.cleaning_services,
                      size: 17,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      booking.serviceType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  StatusChip(status: booking.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                booking.property,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: sem.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 15,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      DateFormat('d MMM yyyy · h:mm a')
                          .format(booking.scheduledStart),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sem.textSecondary,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: sem.textTertiary),
                ],
              ),
              if (booking.specialInstructions != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: sem.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notes, size: 14, color: sem.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          booking.specialInstructions!,
                          style: TextStyle(
                            fontSize: 12,
                            color: sem.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (canRespond) ...[
                const SizedBox(height: 16),
                if (onAccept != null && onDecline != null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onDecline,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Decline'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onAccept,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Accept'),
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: const Text('Review request'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
