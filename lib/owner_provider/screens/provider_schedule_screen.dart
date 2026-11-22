// lib/screens/provider_schedule_screen.dart
// Provider's own schedule view. Mirrors owner schedule but filtered to
// this provider's bookings, with action availability hints.
//
// Round 11 polish (PS1-PS6):
//   PS1 Theme colors (sem.* + AppColors.*) throughout
//   PS2 Stat tiles use AppColors.primary / secondary / statusCompleted
//   PS3 Dividers use sem.border
//   PS4 Today's list uses sem.surfaceAlt bg
//   PS5 App bar "Block out time" icon uses sem.textSecondary
//   PS6 "Today" icon + label use AppColors.primary + sem.textPrimary

import 'package:flutter/material.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../services/backend/schedule_binding.dart';
import '../theme/app_theme.dart';
import '../widgets/calendar_week_view.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import 'booking_detail_screen.dart';
import 'provider_availability_screen.dart';
import 'schedule_screen.dart'
    show
        ScheduleResponsiveBody,
        ScheduleConnectionStatus,
        ScheduleUnavailableWeek,
        scheduleOverlapsDay,
        scheduleWallTime,
        scheduleRunAction;

class ProviderScheduleScreen extends StatefulWidget {
  const ProviderScheduleScreen(
      {super.key,
      required this.providerName,
      required this.bookings,
      this.binding,
      this.onBooking,
      this.onManageAvailability,
      this.bottomNavigationBar});
  final String providerName;
  final List<DemoBooking> bookings;
  final ScheduleBinding? binding;
  final Future<void> Function(DemoBooking)? onBooking;
  final Future<void> Function()? onManageAvailability;
  final Widget? bottomNavigationBar;

  @override
  State<ProviderScheduleScreen> createState() => _ProviderScheduleScreenState();
}

class _ProviderScheduleScreenState extends State<ProviderScheduleScreen> {
  late DateTime _weekStart;
  late DateTime _selectedDay;

  DateTime get _now =>
      widget.binding == null ? DateTime.now() : ScheduleBinding.malaysiaNow();
  DateTime get _displayWeek => widget.binding?.weekStart ?? _weekStart;
  DateTime get _displayDay =>
      _displayWeek.add(Duration(days: _selectedDay.weekday - 1));
  bool get _ready =>
      widget.binding == null ||
      (widget.binding!.complete && widget.binding!.liveError == null);

  @override
  void initState() {
    super.initState();
    _weekStart = widget.binding?.weekStart ?? mondayOf(_now);
    _selectedDay = _now;
  }

  List<DemoBooking> get _myBookings {
    final binding = widget.binding;
    if (binding != null) {
      if (binding.error != null) return const [];
      // The server scopes participants; display names are not identity.
      return binding.bookings;
    }
    return widget.bookings
        .where((b) => b.providerName == widget.providerName)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    if (binding == null) return _buildScreen(context);
    return AnimatedBuilder(
        animation: binding, builder: (context, _) => _buildScreen(context));
  }

  Widget _buildScreen(BuildContext context) {
    final sem = SemanticColors.of(context);
    final mine = _myBookings;
    final blockingBookings =
        mine.where((booking) => booking.status.blocksProviderSlot).toList();
    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: AppBar(
        title: const Text('My schedule'),
        actions: [
          if (widget.binding != null)
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh schedule',
                onPressed:
                    widget.binding!.loading ? null : widget.binding!.refresh),
          IconButton(
            icon: Icon(Icons.add, color: sem.textSecondary),
            tooltip: 'Block out time',
            onPressed: () {
              if (widget.binding != null) {
                scheduleRunAction(context, widget.onManageAvailability);
                return;
              }
              final store = AppProviders.of(context).providerStore;
              final provider = store.providers
                  .where((item) => item.name == widget.providerName)
                  .firstOrNull;
              if (provider == null) return;
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProviderAvailabilityScreen(
                  store: store,
                  providerId: provider.id,
                ),
              ));
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: ScheduleResponsiveBody(
                reserveStatusSpace: widget.binding?.refreshError != null,
                child: Column(
                  children: [
                    if (widget.binding != null) ...[
                      ScheduleConnectionStatus(binding: widget.binding!),
                      if (!_ready) const SizedBox(height: 8),
                    ],
                    _buildStats(mine, sem),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: sem.surface,
                          border: Border.all(color: sem.border),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: !_ready
                            ? ScheduleUnavailableWeek(
                                weekStart: _displayWeek,
                                onChangeWeek: _changeWeek)
                            : CalendarWeekView(
                                weekStart: _displayWeek,
                                bookings: blockingBookings,
                                onTapBooking: _openDetail,
                                onChangeWeek: _changeWeek,
                                selectedDay: _displayDay,
                                onSelectDay: (day) =>
                                    setState(() => _selectedDay = day),
                                today: {_now},
                              ),
                      ),
                    ),
                    if (_ready) ...[
                      const SizedBox(height: 12),
                      _buildTodayList(blockingBookings, sem),
                    ],
                  ],
                )),
          ),
        ),
      ),
    );
  }

  // PS2: themed stat tiles
  Widget _buildStats(List<DemoBooking> mine, SemanticColors sem) {
    if (widget.binding != null) {
      final start = scheduleWallTime(_displayWeek);
      final end = start.add(const Duration(days: 7));
      final jobs = mine
          .where((b) =>
              b.status.blocksProviderSlot &&
              scheduleWallTime(b.scheduledStart).isBefore(end) &&
              scheduleWallTime(b.scheduledEnd).isAfter(start))
          .toList();
      final hours = jobs.fold<double>(0, (total, b) {
        final jobStart = scheduleWallTime(b.scheduledStart);
        final jobEnd = scheduleWallTime(b.scheduledEnd);
        final clippedStart = jobStart.isBefore(start) ? start : jobStart;
        final clippedEnd = jobEnd.isAfter(end) ? end : jobEnd;
        return total + clippedEnd.difference(clippedStart).inMinutes / 60;
      });
      final now = scheduleWallTime(_now);
      final remaining = jobs
          .where((b) => scheduleWallTime(b.scheduledEnd).isAfter(now))
          .length;
      // Only a fully loaded week can produce a definitive count.
      final color = Theme.of(context).colorScheme.primary;
      return Row(children: [
        _stat('Selected week', _ready ? '${jobs.length}' : '—', color, sem,
            prominent: true),
        const SizedBox(width: 8),
        _stat('Hours booked', _ready ? hours.toStringAsFixed(1) : '—', color,
            sem),
        const SizedBox(width: 8),
        _stat('Remaining', _ready ? '$remaining' : '—', color, sem),
      ]);
    }
    final blockingBookings = mine.where((b) => b.status.blocksProviderSlot);
    final thisWeek = blockingBookings.where((b) {
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));
      return b.scheduledStart.isAfter(startOfWeek) &&
          b.scheduledStart.isBefore(endOfWeek);
    }).length;
    final upcoming = mine.where((b) => b.status.blocksProviderSlot).length;
    final hoursThisWeek = blockingBookings.where((b) {
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));
      return b.scheduledStart.isAfter(startOfWeek) &&
          b.scheduledStart.isBefore(endOfWeek);
    }).fold<double>(
        0,
        (s, b) =>
            s + b.scheduledEnd.difference(b.scheduledStart).inMinutes / 60.0);

    return Row(
      children: [
        _stat('This week', '$thisWeek', Theme.of(context).colorScheme.primary,
            sem,
            prominent: true),
        const SizedBox(width: 8),
        _stat('Hours booked', hoursThisWeek.toStringAsFixed(1),
            Theme.of(context).colorScheme.primary, sem),
        const SizedBox(width: 8),
        _stat('Upcoming', '$upcoming', Theme.of(context).colorScheme.primary,
            sem),
      ],
    );
  }

  Widget _stat(String label, String value, Color color, SemanticColors sem,
      {bool prominent = false}) {
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: prominent ? color : sem.primarySurface,
          border: Border.all(color: prominent ? color : sem.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: prominent ? onAccent.withOpacity(0.82) : color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: prominent ? onAccent : sem.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PS4 + PS6: themed today list
  Widget _buildTodayList(List<DemoBooking> mine, SemanticColors sem) {
    final day = _displayDay;
    final isToday = DateUtils.isSameDay(day, _now);
    final today = mine.where((b) => scheduleOverlapsDay(b, day)).toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: sem.surface,
        border: Border.all(color: sem.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: sem.primarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.today_outlined,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(
                  isToday ? "Today's jobs" : 'Selected day jobs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  ),
                )),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: sem.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${today.length}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: sem.textPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = today.length == 1
                  ? constraints.maxWidth
                  : constraints.maxWidth >= 700
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
              return SizedBox(
                height: 108 +
                    (MediaQuery.textScalerOf(context).scale(1) - 1)
                            .clamp(0, 2) *
                        90,
                child: today.isEmpty
                    ? SingleChildScrollView(
                        child: EmptyState(
                        icon: Icons.beach_access,
                        title:
                            isToday ? 'No jobs today' : 'No jobs on this day',
                        subtitle: widget.binding == null
                            ? 'Enjoy the break!'
                            : 'No accepted or in-progress jobs on this day.',
                      ))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: today.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (ctx, i) => SizedBox(
                          width: cardWidth,
                          child: _todayJobCard(today[i], sem),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _todayJobCard(DemoBooking booking, SemanticColors sem) {
    final start =
        TimeOfDay.fromDateTime(booking.scheduledStart).format(context);
    final end = TimeOfDay.fromDateTime(booking.scheduledEnd).format(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(booking),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      booking.property,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sem.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: sem.textTertiary),
                ],
              ),
              const SizedBox(height: 3),
              Text(booking.serviceType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sem.textSecondary, fontSize: 12)),
              const Spacer(),
              Row(
                children: [
                  StatusChip(status: booking.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$start – $end',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: sem.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeWeek(DateTime week) {
    final wallMonday = mondayOf(DateTime(week.year, week.month, week.day));
    setState(() => _weekStart = wallMonday);
    widget.binding?.changeWeek(wallMonday);
  }

  void _openDetail(DemoBooking booking) {
    if (widget.binding != null) {
      scheduleRunAction(context,
          widget.onBooking == null ? null : () => widget.onBooking!(booking));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookingDetailScreen(booking: booking)));
  }
}
