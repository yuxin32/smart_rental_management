import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/demo_data.dart';
import '../services/backend/supabase_owner_repository.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// Owner home: a rental-operations visual language, scoped to cleaning only.
/// Keeps the same presentation for local previews and server projections.
class OwnerWorkspaceDashboard extends StatelessWidget {
  const OwnerWorkspaceDashboard({
    super.key,
    required this.bookings,
    required this.propertyCount,
    required this.onRequest,
    required this.onNavigate,
    required this.onBooking,
    this.connected = false,
    this.ownerSummary,
    this.loading = false,
    this.bookingsUnavailable = false,
    this.bookingsPartial = false,
    this.connectionStatus,
    this.pagination,
    this.onRefresh,
    this.bookingFollow,
    this.pendingBookings,
  });

  final List<DemoBooking> bookings;
  final int? propertyCount;
  final VoidCallback onRequest;
  final ValueChanged<String> onNavigate;
  final ValueChanged<DemoBooking> onBooking;
  final bool connected;
  final OwnerDashboardSnapshot? ownerSummary;
  final bool loading;
  final bool bookingsUnavailable;
  final bool bookingsPartial;
  final Widget? connectionStatus;
  final Widget? pagination;
  final Future<void> Function()? onRefresh;
  final Widget? bookingFollow;
  final Widget? pendingBookings;

  static const navy = Color(0xFF172F67);
  static const sky = Color(0xFFB5DDF7);

  @override
  Widget build(BuildContext context) {
    final sem = SemanticColors.of(context);
    final session = UserSessionAccess.of(context);
    final name = session.displayName.trim();
    final hasName = name.isNotEmpty && !name.contains('@');
    // A page of bookings cannot establish account-wide totals. Unknown server
    // summaries remain unknown rather than looking like a zero or partial total.
    final pending = connected
        ? ownerSummary?.pendingCount
        : bookings.where((b) => b.status == BookingStatus.pending).length;
    final ongoing = connected
        ? ownerSummary?.activeCount
        : bookings
            .where((b) =>
                b.status == BookingStatus.accepted ||
                b.status == BookingStatus.inProgress)
            .length;
    final completed = connected
        ? ownerSummary?.completedCount
        : bookings.where((b) => b.status == BookingStatus.completed).length;
    final open = bookings
        .where((b) =>
            b.status == BookingStatus.accepted ||
            b.status == BookingStatus.inProgress)
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    final awaiting = bookings
        .where((b) => b.status == BookingStatus.pending)
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
      children: [
        Text(hasName ? 'Good ${_timeOfDay()}, $name' : 'Welcome back',
            style: TextStyle(
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: sem.textPrimary)),
        const SizedBox(height: 6),
        Text('Your cleaning services, all in one place.',
            style: TextStyle(fontSize: 13, color: sem.textSecondary)),
        if (connectionStatus != null) connectionStatus!,
        const SizedBox(height: 22),
        _hero(context),
        const SizedBox(height: 25),
        _sectionTitle(context, 'Booking overview'),
        const SizedBox(height: 12),
        _cards(context, [
          _stat(context, 'Pending', pending, Icons.hourglass_top),
          _stat(context, 'Ongoing', ongoing, Icons.autorenew),
          _stat(context, 'Completed', completed, Icons.task_alt),
        ]),
        const SizedBox(height: 25),
        _sectionTitle(context, 'Pending requests'),
        Text('Awaiting a provider response',
            style: TextStyle(fontSize: 12, color: sem.textSecondary)),
        const SizedBox(height: 7),
        pendingBookings ??
            _LocalBookingFollow(
                bookings: awaiting,
                emptyMessage: 'No pending requests.',
                card: (booking) => _bookingCard(context, booking)),
        const SizedBox(height: 25),
        _sectionTitle(context, 'Upcoming bookings'),
        Text('Accepted and in progress · Earliest appointment first',
            style: TextStyle(fontSize: 12, color: sem.textSecondary)),
        const SizedBox(height: 7),
        bookingFollow ??
            _LocalBookingFollow(
                bookings: open,
                emptyMessage: 'No upcoming bookings.',
                card: (booking) => _bookingCard(context, booking)),
        if (bookingFollow == null && pagination != null) pagination!,
      ],
    );
    return ColoredBox(
      color: sem.background,
      child: SafeArea(
        top: false,
        child: onRefresh == null
            ? list
            : RefreshIndicator(onRefresh: onRefresh!, child: list),
      ),
    );
  }

  String _timeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 18) return 'afternoon';
    return 'evening';
  }

  Widget _hero(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient(context),
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
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
                const Icon(Icons.cleaning_services_outlined,
                    size: 28, color: sky),
                const SizedBox(height: 14),
                const Text('Ready for your next cleaning?',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        height: 1.2,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                const Text('Choose a service, time and suitable provider.',
                    style: TextStyle(
                        color: Color(0xFFD9E8FF), fontSize: 12, height: 1.35)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRequest,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: navy,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Request cleaning',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ]),
      );

  Widget _sectionTitle(BuildContext context, String text) => Text(text,
      style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: SemanticColors.of(context).textPrimary));

  Widget _cards(BuildContext context, List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          // Preserve the compact original grid at normal text size. Large text
          // needs real layout space, not scaled-down numbers or clipped labels.
          final stacked = MediaQuery.textScalerOf(context).scale(14) > 19 &&
              constraints.maxWidth < 500;
          final columns = stacked ? 1 : children.length;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final child in children) SizedBox(width: width, child: child),
          ]);
        },
      );

  Widget _stat(BuildContext context, String label, int? value, IconData icon) =>
      Semantics(
          button: true,
          label: '$label bookings, ${value ?? 'unavailable'}',
          child: Material(
              color: SemanticColors.of(context).surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                  key: ValueKey('owner-stat-${label.toLowerCase()}'),
                  onTap: () => onNavigate('bookings-${label.toLowerCase()}'),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 92),
                    padding: const EdgeInsets.all(12),
                    decoration: _cardDecoration(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(value?.toString() ?? '—',
                                style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                    color: SemanticColors.of(context)
                                        .textPrimary)),
                          ),
                          Icon(icon,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary),
                        ]),
                        const SizedBox(height: 10),
                        Text(label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    SemanticColors.of(context).textSecondary)),
                      ],
                    ),
                  ))));

  Widget _bookingCard(BuildContext context, DemoBooking? booking) => Material(
        color: SemanticColors.of(context).surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: SemanticColors.of(context).border),
        ),
        child: InkWell(
          onTap: booking == null ? onRequest : () => onBooking(booking),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: booking == null
                ? Row(children: [
                    Icon(Icons.event_available_outlined,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          connected && loading
                              ? 'Loading your bookings…'
                              : connected && bookingsUnavailable
                                  ? 'Bookings unavailable. Pull down to retry.'
                                  : connected && bookingsPartial
                                      ? 'No open booking among the bookings shown. Show more to check other appointments.'
                                      : 'No open booking yet. Start a cleaning request.',
                          style: TextStyle(
                              fontSize: 12,
                              color: SemanticColors.of(context).textSecondary)),
                    ),
                    Icon(Icons.chevron_right,
                        color: Theme.of(context).colorScheme.primary),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(booking.serviceType,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      SemanticColors.of(context).textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color:
                                (Theme.of(context).brightness == Brightness.dark
                                        ? Color.lerp(booking.status.color,
                                            Colors.white, 0.36)!
                                        : booking.status.color)
                                    .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(booking.status.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Color.lerp(booking.status.color,
                                          Colors.white, 0.36)!
                                      : booking.status.color)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(booking.property,
                          style: TextStyle(
                              fontSize: 12,
                              color: SemanticColors.of(context).textSecondary)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Icon(Icons.event_outlined,
                            size: 15,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${DateFormat('d MMM yyyy · h:mm a').format(booking.scheduledStart)} – ${DateFormat('h:mm a').format(booking.scheduledEnd)}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: SemanticColors.of(context).textPrimary),
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Theme.of(context).colorScheme.primary),
                      ]),
                    ],
                  ),
          ),
        ),
      );

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
        color: SemanticColors.of(context).surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SemanticColors.of(context).border),
      );
}

class _LocalBookingFollow extends StatefulWidget {
  const _LocalBookingFollow(
      {required this.bookings, required this.card, required this.emptyMessage});
  final List<DemoBooking> bookings;
  final Widget Function(DemoBooking?) card;
  final String emptyMessage;
  @override
  State<_LocalBookingFollow> createState() => _LocalBookingFollowState();
}

class _LocalBookingFollowState extends State<_LocalBookingFollow> {
  int visible = 3;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.bookings.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(widget.emptyMessage)),
        for (final booking in widget.bookings.take(visible))
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: widget.card(booking)),
        if (visible < widget.bookings.length)
          OutlinedButton.icon(
              onPressed: () => setState(() => visible += 3),
              icon: const Icon(Icons.expand_more),
              label: const Text('Show more bookings')),
      ]);
}

class OwnerWorkspaceNav extends StatelessWidget {
  const OwnerWorkspaceNav({
    super.key,
    required this.activeId,
    required this.onChange,
  });

  final String activeId;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: SemanticColors.of(context).surface,
          border:
              Border(top: BorderSide(color: SemanticColors.of(context).border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64 +
                (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 3) *
                    24,
            child: Row(children: [
              _item(context, 'home', 'Home', Icons.home_rounded),
              _item(context, 'properties', 'Properties',
                  Icons.apartment_outlined),
              _item(context, 'browse', 'Providers', Icons.people_outline),
              _item(
                  context, 'bookings', 'Bookings', Icons.receipt_long_outlined),
              _item(context, 'profile', 'Profile', Icons.person_outline),
            ]),
          ),
        ),
      );

  Widget _item(BuildContext context, String id, String label, IconData icon) =>
      Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: () => onChange(id),
          selected: activeId == id,
          child: InkWell(
            onTap: () => onChange(id),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 22,
                    color: activeId == id
                        ? Theme.of(context).colorScheme.primary
                        : SemanticColors.of(context).textSecondary),
                const SizedBox(height: 5),
                Flexible(
                    child: Text(label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: activeId == id
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: activeId == id
                              ? Theme.of(context).colorScheme.primary
                              : SemanticColors.of(context).textSecondary,
                        ))),
              ],
            ),
          ),
        ),
      );
}
