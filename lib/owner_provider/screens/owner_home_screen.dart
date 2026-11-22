// lib/screens/owner_home_screen.dart
// Owner-side shell. Connected mode listens only to server workspace projections;
// local preview mode retains its existing BookingStore-based navigation.
//
// Round 9 polish (OH1-OH7):
//   OH1 Theme colors (AppColors.primary + sem.*) instead of hardcoded hex
//   OH2 Dynamic user name from UserSession (no hardcoded "Oh Wan Ting")
//   OH3 Time-based greeting (Good morning / afternoon / evening)
//   OH4 _SummaryHeader uses AppTheme.primaryGradient
//   OH5 Search field uses theme tokens
//   OH6 Filter chip dot uses AppColors.primary
//   OH7 _OwnerProfileScreen: section headers use SectionHeader, theme tiles

import 'package:flutter/material.dart';
import 'account_settings_screens.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../services/booking_store.dart';
import '../services/backend/workspace_binding.dart';
import '../widgets/snapshot_refresh_notice.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/message_unread_scope.dart';
import '../services/backend/owner_navigation_repository.dart';
import 'owner_records_view.dart';
import '../widgets/booking_card.dart';
import '../widgets/coach_mark.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/workspace_actions.dart';
import '../widgets/owner_workspace_navigation.dart';
import 'owner_workspace_dashboard.dart';
import 'owner_booking_feed.dart';
import '../services/backend/supabase_booking_repository.dart';
import 'about_screen.dart';
import 'booking_detail_screen.dart';
import 'chat_list_screen.dart';
import 'new_booking_screen.dart';
import 'notifications_screen.dart';
import 'owner_spend_screen.dart';
import 'property_list_screen.dart';
import 'property_form_screen.dart';
import 'provider_browse_screen.dart';
import 'provider_inbox_screen.dart';
import 'provider_profile_screen.dart';
import 'schedule_screen.dart';

class OwnerHomeScreen extends StatefulWidget {
  const OwnerHomeScreen({super.key, this.binding, this.actions});

  /// The caller owns the binding's refresh, activity and disposal lifecycle.
  final WorkspaceBinding? binding;
  final WorkspaceActions? actions;

  @override
  State<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends State<OwnerHomeScreen> {
  String _tab = 'home';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  FilterResult _filter = FilterResult.empty;
  final _navigationKey = GlobalKey();
  final _followKey = GlobalKey<OwnerBookingFeedState>();
  final _pendingKey = GlobalKey<OwnerBookingFeedState>();
  OwnerBookingGroup? _statusGroup;
  BuildContext get _navigationContext =>
      _navigationKey.currentContext ?? context;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _switchTab(String id) {
    if (widget.binding != null && id != 'home' && id != 'bookings') {
      _onDrawerNav(id);
      return;
    }
    Haptics.selection();
    setState(() => _tab = id);
  }

  void _onDrawerNav(String routeId) {
    final statusGroup = switch (routeId) {
      'bookings-pending' => OwnerBookingGroup.pending,
      'bookings-ongoing' => OwnerBookingGroup.active,
      'bookings-completed' => OwnerBookingGroup.completed,
      _ => null,
    };
    if (statusGroup != null) {
      if (widget.binding != null) {
        _connectedAction(
            (actions) =>
                actions.bookingsByStatus(_navigationContext, statusGroup),
            refresh: false);
      } else {
        setState(() {
          _statusGroup = statusGroup;
          _filter = FilterResult.empty;
          _searchQuery = '';
          _searchCtrl.clear();
          _tab = 'bookings';
        });
      }
      return;
    }
    if (routeId == 'bookings') _statusGroup = null;
    if (widget.binding != null) {
      switch (routeId) {
        case 'home':
        case 'bookings':
          _switchTab(routeId);
          return;
        case 'properties':
          _connectedAction((actions) => actions.properties(_navigationContext));
          return;
        case 'add-property':
          _connectedAction((actions) => actions.addProperty(context));
          return;
        case 'profile':
          _connectedAction((actions) => actions.profile(_navigationContext));
          return;
        case 'spend':
          _connectedAction((actions) => actions.spending(context),
              refresh: false);
          return;
        case 'schedule':
          _connectedAction((actions) => actions.schedule(context));
          return;
        case 'browse':
          _connectedAction((actions) => actions.browse(_navigationContext));
          return;
        case 'theme':
          context
              .getInheritedWidgetOfExactType<AppProviders>()
              ?.onToggleTheme();
          return;
        case 'notifications':
          _connectedAction((actions) => actions.notifications(context),
              refresh: false);
          return;
        case 'messages':
          _connectedAction((actions) => actions.messages(context),
              refresh: false);
          return;
        case 'about':
          _connectedAction((actions) => actions.about(context), refresh: false);
          return;
        case 'sign-out':
          _connectedAction((actions) => actions.signOut(context),
              refresh: false);
          return;
        default:
          _unavailable({
                'schedule': 'Schedule',
                'notifications': 'Notifications',
                'profile': 'Profile',
                'messages': 'Messages',
                'spend': 'Spending',
                'about': 'About',
                'switch-role': 'Role switching',
              }[routeId] ??
              routeId);
          return;
      }
    }
    switch (routeId) {
      case 'home':
        _switchTab('home');
        break;
      case 'schedule':
        _switchTab('schedule');
        break;
      case 'properties':
        _switchTab('properties');
        break;
      case 'browse':
        _switchTab('browse');
        break;
      case 'bookings':
        _switchTab('bookings');
        break;
      case 'notifications':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const NotificationsScreen(role: 'Owner'),
        ));
        break;
      case 'profile':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OwnerDestinationFrame(
              activeId: 'profile',
              onChange: (id) async {
                Navigator.of(context).popUntil((route) => route.isFirst);
                if (mounted) _switchTab(id);
              },
              child: OwnerProfileScreen(
                  onOpenBookings: () => _switchTab('home'),
                  onAction: _localProfileAction)),
        ));
        break;
      case 'messages':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ChatListScreen()));
        break;
      case 'spend':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OwnerSpendScreen(
            bookings: AppProviders.of(context).bookingStore.bookings,
            providers: AppProviders.of(context).providerStore.providers,
          ),
        ));
        break;
      case 'about':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AboutScreen(
                prototypeSupport: AppProviders.of(context).prototypeSupport)));
        break;
      case 'switch-role':
        _openProviderView();
        break;
    }
  }

  void _openNewBooking() async {
    if (widget.binding != null) {
      await _connectedAction((actions) => actions.request(context));
      return;
    }
    Haptics.light();
    final created = await Navigator.of(context).push<DemoBooking>(
      MaterialPageRoute(builder: (_) => const NewBookingScreen()),
    );
    if (created != null && mounted) {
      Haptics.medium();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pending request sent to ${created.providerName}'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(booking: created),
        ),
      );
    }
  }

  void _localProfileAction(String title) {
    switch (title) {
      case 'Appearance':
        AppProviders.of(context).onToggleTheme();
      case 'Schedule':
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ScheduleScreen(
                bookings: AppProviders.of(context).bookingStore.bookings)));
      case 'Spending':
        _onDrawerNav('spend');
      case 'Notifications':
        _onDrawerNav('notifications');
      case 'About & help':
        _onDrawerNav('about');
      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$title is available in the connected workspace.')));
    }
  }

  void _openProviderView() {
    if (widget.binding != null) {
      _unavailable('Role switching');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderInboxScreen(
          provider: DemoProvider.seeded().first,
        ),
      ),
    );
  }

  void _openFilter() async {
    Haptics.light();
    final binding = widget.binding;
    final all = binding == null
        ? AppProviders.of(context).bookingStore.bookings
        : _serverBookings(binding);
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

  void _unavailable(String label) {
    final actions = widget.actions;
    if (actions != null) {
      actions.unavailable(context, label);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label is not connected yet.'),
    ));
  }

  Future<void> _connectedAction(
    Future<void> Function(WorkspaceActions) action, {
    bool refresh = true,
  }) async {
    final actions = widget.actions;
    if (actions == null) {
      _unavailable('This action');
      return;
    }
    final binding = widget.binding;
    try {
      await action(actions);
      if (refresh && mounted && identical(binding, widget.binding)) {
        await binding?.refresh();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not complete this action. Please try again.'),
        ));
      }
    }
  }

  // Projection failures must be checked before accessing the display models.
  List<DemoBooking> _serverBookings(WorkspaceBinding binding) =>
      binding.error != null ? const [] : binding.bookings;

  void _openBooking(DemoBooking booking) {
    if (widget.binding != null) {
      _connectedAction((actions) => actions.booking(context, booking.id));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookingDetailScreen(booking: booking),
    ));
  }

  Widget _connectionStatus(WorkspaceBinding binding) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (binding.loading) const LinearProgressIndicator(),
          SnapshotRefreshNotice(
              refreshing: binding.refreshing,
              failed: binding.refreshError != null,
              onRetry: binding.refresh),
          if (binding.error != null)
            _retryNotice(
                'Could not refresh your workspace. Displayed data may be out of date.',
                () => binding.refresh()),
          if (binding.liveError != null)
            _retryNotice('Live updates are interrupted. Pull down to refresh.',
                binding.retryLive),
        ],
      );

  Widget _retryNotice(String message, VoidCallback onRetry) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );

  Widget _pagination(WorkspaceBinding binding, int loadedCount) =>
      Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '$loadedCount booking${loadedCount == 1 ? '' : 's'} shown'
            '${binding.hasMore ? ' · More available' : ''}.',
            style: TextStyle(color: SemanticColors.of(context).textSecondary),
          ),
        ),
        if (binding.moreError != null)
          _retryNotice(
              'Could not load more bookings.', () => binding.loadMore()),
        if (binding.hasMore || binding.loadingMore)
          TextButton.icon(
            onPressed: binding.loadingMore || binding.loading
                ? null
                : () => binding.loadMore(),
            icon: binding.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: Text(binding.loadingMore ? 'Loading more…' : 'Load more'),
          ),
      ]);

  Widget _dashboard(List<DemoBooking> bookings, int? propertyCount) {
    final binding = widget.binding;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text('Owner Dashboard',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Messages',
            icon: MessageUnreadBadge(
                child: const Icon(Icons.chat_bubble_outline)),
            onPressed: () => _onDrawerNav('messages'),
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: Icon(Icons.notifications_none,
                color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => _onDrawerNav('notifications'),
          ),
        ],
      ),
      body: OwnerWorkspaceDashboard(
        bookings: bookings,
        propertyCount: propertyCount,
        connected: binding != null,
        ownerSummary: binding?.ownerSummary,
        loading: binding?.loading ?? false,
        bookingsUnavailable: binding?.error != null,
        bookingsPartial: binding?.hasMore ?? false,
        connectionStatus: binding == null ? null : _connectionStatus(binding),
        pagination: binding != null && binding.backend == null
            ? _pagination(binding, bookings.length)
            : null,
        bookingFollow: binding?.backend == null
            ? null
            : OwnerBookingFeed(
                key: _followKey,
                backend: binding!.backend!,
                group: OwnerBookingGroup.upcoming,
                inline: true,
                onBooking: _openBooking),
        pendingBookings: binding?.backend == null
            ? null
            : OwnerBookingFeed(
                key: _pendingKey,
                backend: binding!.backend!,
                group: OwnerBookingGroup.pending,
                inline: true,
                onBooking: _openBooking),
        onRefresh: binding == null
            ? null
            : () async {
                await Future.wait([
                  binding.refresh(),
                  if (_followKey.currentState != null)
                    _followKey.currentState!.refresh(),
                  if (_pendingKey.currentState != null)
                    _pendingKey.currentState!.refresh(),
                ]);
              },
        onRequest: _openNewBooking,
        onNavigate: _onDrawerNav,
        onBooking: _openBooking,
      ),
      bottomNavigationBar:
          OwnerWorkspaceNav(activeId: _tab, onChange: _onDrawerNav),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OwnerRootNavigation(
        select: (id) {
          if (mounted) _switchTab(id);
        },
        child: PopScope(
            canPop: _tab == 'home',
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && mounted) _switchTab('home');
            },
            child: Builder(key: _navigationKey, builder: _buildWorkspace)));
  }

  Widget _buildWorkspace(BuildContext context) {
    final binding = widget.binding;
    if (binding != null) {
      return AnimatedBuilder(
        animation: binding,
        builder: (ctx, _) {
          final bookings = _serverBookings(binding);
          return _tab == 'home'
              ? _dashboard(bookings, binding.ownerSummary?.propertyCount)
              : Scaffold(
                  appBar: AppBar(
                      leading: BackButton(onPressed: () => _switchTab('home')),
                      title: const Text('Bookings')),
                  body: _buildHomeTab(ctx, bookings),
                  bottomNavigationBar:
                      OwnerWorkspaceNav(activeId: _tab, onChange: _onDrawerNav),
                );
        },
      );
    }
    final store = AppProviders.of(context).bookingStore;
    final propertyStore = AppProviders.of(context).propertyStore;
    return AnimatedBuilder(
      animation: Listenable.merge([store, propertyStore]),
      builder: (ctx, _) {
        if (_tab == 'home') {
          return _dashboard(store.bookings, propertyStore.properties.length);
        }
        final body = _buildBody(ctx, store);
        final withCoach = _tab == 'home'
            ? CoachMarkOverlay(
                setId: 'owner_home_v1',
                marks: const [
                  CoachMark(
                    id: 'hero',
                    icon: Icons.dashboard,
                    title: 'Your dashboard',
                    body:
                        'At-a-glance stats: total bookings, accepted, in progress, and completed.',
                    accent: AppColors.primary,
                    alignment: CoachMarkAlignment.topLeft,
                  ),
                  CoachMark(
                    id: 'tabs',
                    icon: Icons.tab,
                    title: '5 quick tabs',
                    body:
                        'Home / Schedule / Properties / Browse / Spend. Switch anytime.',
                    accent: AppColors.primary,
                    alignment: CoachMarkAlignment.bottomCenter,
                  ),
                  CoachMark(
                    id: 'fab',
                    icon: Icons.add_circle,
                    title: 'New request',
                    body: 'The big + button creates a new cleaning request.',
                    accent: AppColors.primary,
                    alignment: CoachMarkAlignment.bottomRight,
                  ),
                ],
                child: body,
              )
            : body;
        return Scaffold(
          appBar: _buildAppBar(ctx),
          body: withCoach,
          floatingActionButton: _tab == 'home'
              ? FloatingActionButton.extended(
                  heroTag: 'new-request',
                  onPressed: _openNewBooking,
                  icon: const Icon(Icons.add),
                  label: const Text('New request'),
                )
              : null,
          bottomNavigationBar:
              OwnerWorkspaceNav(activeId: _tab, onChange: _onDrawerNav),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    String title;
    switch (_tab) {
      case 'home':
        title = 'Owner Dashboard';
        break;
      case 'schedule':
        title = 'Schedule';
        break;
      case 'properties':
        title = 'My properties';
        break;
      case 'browse':
        title = 'Browse providers';
        break;
      case 'spend':
        title = 'Spending';
        break;
      case 'bookings':
        title = 'Bookings';
        break;
      default:
        title = 'Owner';
    }
    return AppBar(
      leading: _tab == 'home'
          ? null
          : BackButton(onPressed: () => _switchTab('home')),
      title: Text(title),
      actions: [
        if (_tab == 'properties')
          IconButton(
            tooltip: 'Add property',
            icon: const Icon(Icons.add),
            onPressed: () {
              final app = AppProviders.of(context);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PropertyFormScreen(
                      store: app.propertyStore,
                      bookings: app.bookingStore.bookings)));
            },
          ),
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined),
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const NotificationsScreen(role: 'Owner')),
          ),
          tooltip: 'Notifications',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBody(BuildContext context, BookingStore store) {
    switch (_tab) {
      case 'home':
        return _buildHomeTab(context, store.bookings);
      case 'schedule':
        return _embeddedSchedule(store);
      case 'properties':
        return PropertyListScreen(bookings: store.bookings, embedded: true);
      case 'browse':
        return _embeddedBrowse();
      case 'spend':
        return OwnerSpendScreen(
          bookings: store.bookings,
          providers: AppProviders.of(context).providerStore.providers,
        );
      case 'bookings':
        return _buildHomeTab(context, store.bookings);
      default:
        return _buildHomeTab(context, store.bookings);
    }
  }

  Widget _embeddedSchedule(BookingStore store) {
    return ScheduleScreen(bookings: store.bookings, embedded: true);
  }

  Widget _embeddedBrowse() {
    return ProviderBrowseScreen(
      onViewProfile: (p) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProviderProfileScreen(provider: p)),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context, List<DemoBooking> allBookings) {
    final backend = widget.binding?.backend;
    if (backend != null)
      return OwnerRecordsView(
          providers: false,
          openFeed: OwnerNavigationRepository(backend).open,
          onBooking: (id) => _connectedAction(
              (actions) => actions.booking(_navigationContext, id)));
    final sem = SemanticColors.of(context);
    final binding = widget.binding;
    final hasActiveFilter =
        _filter.statusFilter != null || _filter.propertyFilter != null;
    final filtered = applyFilter(
      allBookings
          .where((b) =>
              _statusGroup == null ||
              _statusGroup!.statuses.contains(b.status.label))
          .where((b) =>
              _searchQuery.isEmpty ||
              b.property.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              b.serviceType
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              (b.providerName
                      ?.toLowerCase()
                      .contains(_searchQuery.toLowerCase()) ??
                  false) ||
              b.status.label.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList(),
      _filter,
    );
    return RefreshIndicator(
      onRefresh: () async {
        if (binding != null) {
          await binding.refresh();
          return;
        }
        Haptics.light();
        await Future.delayed(const Duration(milliseconds: 600));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refreshed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (binding == null)
            _SummaryHeader(bookings: allBookings)
          else ...[
            _connectionStatus(binding),
            const Text(
                'Search and filters apply to bookings shown below. Show more to include older bookings.'),
          ],
          const SizedBox(height: 16),
          // OH5: search + filter with theme tokens
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search bookings...',
                    hintStyle: TextStyle(fontSize: 13, color: sem.textTertiary),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 10, right: 6),
                      child: Icon(Icons.search,
                          size: 18, color: sem.textSecondary),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close,
                                size: 16, color: sem.textSecondary),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: sem.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
              const SizedBox(width: 8),
              // OH6: theme-tinted filter button
              Material(
                color: hasActiveFilter ? sem.primarySurface : sem.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: hasActiveFilter ? sem.primaryBorder : sem.border,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _openFilter,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.tune,
                            size: 20,
                            color: hasActiveFilter
                                ? Theme.of(context).colorScheme.primary
                                : sem.textSecondary),
                        if (hasActiveFilter)
                          const Positioned(
                            top: -2,
                            right: -2,
                            child: _FilterDot(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  binding != null
                      ? '${filtered.length} result${filtered.length == 1 ? '' : 's'} shown'
                      : _searchQuery.isEmpty
                          ? '${filtered.length} booking${filtered.length == 1 ? '' : 's'}'
                          : '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 48, color: sem.textTertiary),
                  const SizedBox(height: 8),
                  Text(
                      binding != null && binding.loading
                          ? 'Loading bookings…'
                          : binding != null &&
                                  binding.error != null &&
                                  allBookings.isEmpty
                              ? 'Bookings unavailable. Retry above.'
                              : 'No matches',
                      style: TextStyle(fontSize: 14, color: sem.textSecondary)),
                ],
              ),
            )
          else
            ...filtered.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BookingCard(
                    booking: b,
                    onTap: () => _openBooking(b),
                  ),
                )),
          if (binding != null) _pagination(binding, allBookings.length),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// Small filled dot used to indicate an active filter is set.
class _FilterDot extends StatelessWidget {
  const _FilterDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ====================================================================
// Gradient hero summary header
// ====================================================================

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.bookings});
  final List<DemoBooking> bookings;

  @override
  Widget build(BuildContext context) {
    // OH2: dynamic user name
    final session = UserSessionAccess.of(context);
    final name = session.displayName.isEmpty ? 'Owner' : session.displayName;
    // OH3: greeting is local to widget (parent already builds greeting string)
    final greeting = _greetingFor(DateTime.now().hour);
    final total = bookings.length;
    final inProgress =
        bookings.where((b) => b.status == BookingStatus.inProgress).length;
    final accepted =
        bookings.where((b) => b.status == BookingStatus.accepted).length;
    final completed =
        bookings.where((b) => b.status == BookingStatus.completed).length;
    final pending =
        bookings.where((b) => b.status == BookingStatus.pending).length;
    return Container(
      decoration: BoxDecoration(
        // OH4: use AppTheme gradient
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SemanticColors.of(context).shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.apartment,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Owner Module',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _StatCard(label: 'Total', value: '$total'),
                const SizedBox(width: 8),
                _StatCard(label: 'Active', value: '$inProgress'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _StatCard(label: 'Accepted', value: '$accepted'),
                const SizedBox(width: 8),
                _StatCard(label: 'Done', value: '$completed'),
              ],
            ),
            const SizedBox(height: 12),
            if (pending > 0)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {},
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$pending pending request${pending == 1 ? '' : 's'} awaiting provider response',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _greetingFor(int h) {
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// Owner Profile mini-screen (drawer destination)
// ====================================================================

class OwnerProfileScreen extends StatelessWidget {
  const OwnerProfileScreen(
      {super.key,
      required this.onOpenBookings,
      this.snapshot,
      this.onAction,
      this.onRefresh,
      this.notice});
  final VoidCallback onOpenBookings;
  final Map<String, dynamic>? snapshot;
  final ValueChanged<String>? onAction;
  final Future<void> Function()? onRefresh;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    // OH2: dynamic name
    final session = snapshot == null ? UserSessionAccess.of(context) : null;
    final name = snapshot != null
        ? (snapshot!['full_name'] as String? ?? 'Property Owner')
        : session!.displayName.isEmpty
            ? 'Owner'
            : session.displayName;
    final initials = _initialsOf(name);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: RefreshIndicator(
          onRefresh: onRefresh ?? () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (notice != null) notice!,
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 2),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            snapshot == null
                                ? 'Owner · 5 properties'
                                : 'Owner · ${snapshot!['property_count']} properties',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SettingsSection(title: 'Personal details', children: [
                _tile(context, Icons.person_outline, 'Edit profile',
                    'Name, contact and account details'),
              ]),
              SettingsSection(title: 'Preferences', children: [
                _tile(context, Icons.notifications_outlined, 'Notifications',
                    'Unread indicators on this device'),
                const Divider(height: 1),
                _tile(context, Icons.brightness_auto_outlined, 'Appearance',
                    'System, Light or Dark'),
              ]),
              SettingsSection(title: 'Activity & reports', children: [
                _tile(context, Icons.calendar_month_outlined, 'Schedule',
                    'Your cleaning appointments'),
                const Divider(height: 1),
                _tile(context, Icons.payments_outlined, 'Spending',
                    'Completed booking costs'),
              ]),
              SettingsSection(title: 'Account & help', children: [
                _tile(context, Icons.shield_outlined, 'Privacy & security',
                    'Sign-in, recovery and account information'),
                const Divider(height: 1),
                _tile(context, Icons.info_outline, 'About & help',
                    'Guides, support, terms and privacy'),
                if (snapshot != null) ...[
                  const Divider(height: 1),
                  _tile(context, Icons.logout, 'Sign out', null),
                ],
              ]),
              const SizedBox(height: 32),
            ],
          )),
    );
  }

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'O';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _tile(
    BuildContext ctx,
    IconData icon,
    String title,
    String? subtitle, {
    VoidCallback? onTap,
  }) {
    final sem = SemanticColors.of(ctx);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: sem.primarySurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: Theme.of(ctx).colorScheme.primary),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: sem.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(fontSize: 12, color: sem.textSecondary))
          : null,
      trailing:
          Icon(Icons.arrow_forward_ios, size: 12, color: sem.textTertiary),
      onTap: onTap ??
          () {
            if (onAction != null) {
              onAction!(title);
              return;
            }
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text('$title is unavailable here.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
    );
  }
}
