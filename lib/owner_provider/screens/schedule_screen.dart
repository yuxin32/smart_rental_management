// lib/screens/schedule_screen.dart
// Owner-side schedule view. Week timeline + legend + list-of-today fallback.
//
// Round 10 polish (SC1-SC5):
//   SC1 Theme colors (sem.* + AppColors.*) for dividers and icon
//   SC2 Legend pill style improved (sem.surfaceAlt bg, sem.textPrimary text)
//   SC3 "Today's bookings" header uses sem tokens
//   SC4 Container background uses sem.surfaceAlt
//   SC5 App bar "Jump to today" button gets themed icon

import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../services/backend/schedule_binding.dart';
import '../theme/app_theme.dart';
import '../widgets/booking_card.dart';
import '../widgets/calendar_week_view.dart';
import '../widgets/empty_state.dart';
import 'booking_detail_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.bookings,
    this.embedded = false,
    this.binding,
    this.onBooking,
    this.onManageAvailability,
  });
  final List<DemoBooking> bookings;
  final ScheduleBinding? binding;
  final Future<void> Function(DemoBooking)? onBooking;
  final Future<void> Function()? onManageAvailability;

  /// When true, skip the inner Scaffold/AppBar so the parent (e.g. owner shell)
  /// can own the AppBar and avoid a duplicate title.
  final bool embedded;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
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

  List<DemoBooking> get _bookings {
    final source = widget.binding?.bookings ?? widget.bookings;
    if (widget.binding == null) return source;
    return source
        .where(
          (b) =>
              b.status != BookingStatus.cancelled &&
              b.status != BookingStatus.declined,
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _weekStart = widget.binding?.weekStart ?? mondayOf(_now);
    _selectedDay = _now;
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    if (binding == null) return _buildScreen(context);
    return AnimatedBuilder(
      animation: binding,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final sem = SemanticColors.of(context);
    final body = Column(
      children: [
        if (widget.binding != null)
          ScheduleConnectionStatus(binding: widget.binding!),
        _buildLegend(sem),
        Divider(height: 1, thickness: 1, color: sem.border),
        Expanded(
          child: !_ready
              ? ScheduleUnavailableWeek(
                  weekStart: _displayWeek,
                  onChangeWeek: _changeWeek,
                )
              : CalendarWeekView(
                  weekStart: _displayWeek,
                  bookings: _bookings,
                  onTapBooking: _openDetail,
                  onChangeWeek: _changeWeek,
                  selectedDay: _displayDay,
                  onSelectDay: (day) => setState(() => _selectedDay = day),
                  today: {_now},
                ),
        ),
        if (_ready) ...[
          Divider(height: 1, thickness: 1, color: sem.border),
          _buildTodayList(sem),
        ],
      ],
    );
    final savedStatus = widget.binding?.refreshError != null;
    if (widget.embedded)
      return ScheduleResponsiveBody(
          reserveStatusSpace: savedStatus, child: body);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          if (widget.binding != null)
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh schedule',
                onPressed:
                    widget.binding!.loading ? null : widget.binding!.refresh),
          IconButton(
            // SC5: themed icon
            icon: Icon(Icons.today, color: sem.textSecondary),
            onPressed: () {
              _selectedDay = _now;
              _changeWeek(mondayOf(_now));
            },
            tooltip: 'Jump to this week',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body:
          ScheduleResponsiveBody(reserveStatusSpace: savedStatus, child: body),
    );
  }

  // SC2: themed legend
  Widget _buildLegend(SemanticColors sem) {
    final items = [
      BookingStatus.pending,
      BookingStatus.accepted,
      BookingStatus.inProgress,
      BookingStatus.completed,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 5,
        runSpacing: 6,
        children: [
          for (final s in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: s.color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: s.color.withOpacity(0.30),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.binding != null && s == BookingStatus.pending
                          ? 'Pending (not reserved)'
                          : s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: sem.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // SC3 + SC4: themed today list
  Widget _buildTodayList(SemanticColors sem) {
    final day = _displayDay;
    final isToday = DateUtils.isSameDay(day, _now);
    final todayBookings = _bookings
        .where((b) => scheduleOverlapsDay(b, day))
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    return Container(
      color: sem.surfaceAlt,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  "${isToday ? "Today's bookings" : 'Selected day bookings'}  ·  ${todayBookings.length}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sem.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 168 +
                (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) *
                    100,
            child: todayBookings.isEmpty
                ? SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.event_available,
                      title: isToday
                          ? 'No bookings today'
                          : 'No bookings on this day',
                      subtitle: widget.binding == null
                          ? 'A quiet day. Use the form to schedule a cleaning.'
                          : 'No bookings for the selected day.',
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: todayBookings.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (ctx, i) {
                      final b = todayBookings[i];
                      return SizedBox(
                        width: 280,
                        child: BookingCard(
                          booking: b,
                          onTap: () => _openDetail(b),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetail(DemoBooking b) {
    if (widget.binding != null) {
      scheduleRunAction(
        context,
        widget.onBooking == null ? null : () => widget.onBooking!(b),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: b)),
    );
  }

  void _changeWeek(DateTime week) {
    final wallMonday = mondayOf(DateTime(week.year, week.month, week.day));
    setState(() => _weekStart = wallMonday);
    widget.binding?.changeWeek(wallMonday);
  }
}

// Compare wall fields: server projections already contain Malaysia wall time.
DateTime scheduleWallTime(DateTime value) => DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );

bool scheduleOverlapsDay(DemoBooking booking, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  return scheduleWallTime(booking.scheduledStart)
          .isBefore(start.add(const Duration(days: 1))) &&
      scheduleWallTime(booking.scheduledEnd).isAfter(start);
}

Future<void> scheduleRunAction(
  BuildContext context,
  Future<void> Function()? action,
) async {
  if (action == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This action is currently unavailable.')),
    );
    return;
  }
  try {
    await action();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open this action. Please try again.'),
      ),
    );
  }
}

/// Preserve the same calendar/cards, but let short or large-text screens scroll
/// rather than squeezing fixed calendar headers into an unusable viewport.
class ScheduleResponsiveBody extends StatelessWidget {
  const ScheduleResponsiveBody(
      {super.key, required this.child, this.reserveStatusSpace = false});
  final Widget child;
  final bool reserveStatusSpace;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        // A retained calendar must not be squeezed by a wrapping status/retry
        // banner. Scroll the whole page when enlarged text needs more room.
        final minimum = 620.0 +
            (scale - 1).clamp(0, 2) * 300 +
            (reserveStatusSpace ? 120 * scale : 0);
        if (constraints.maxHeight >= minimum) return child;
        return SingleChildScrollView(
            child: SizedBox(height: minimum, child: child));
      });
}

/// Read-only presentation; the route wrapper owns binding activity and disposal.
class ScheduleConnectionStatus extends StatelessWidget {
  const ScheduleConnectionStatus({super.key, required this.binding});
  final ScheduleBinding binding;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (binding.refreshing) {
      // Keep normal navigation silent, but never hide an incomplete calendar.
      if (!binding.hasMore) return const SizedBox.shrink();
      message = 'Selected week is incomplete. Load more to view the schedule.';
    } else if (binding.refreshError != null) {
      message =
          'Could not refresh. Saved schedule may be out of date; do not assume free slots.';
    } else if (binding.loading) {
      message = 'Loading selected week…';
    } else if (binding.error != null) {
      message = 'Could not load selected week. Schedule unavailable.';
    } else if (binding.loadingMore) {
      message = 'Loading remaining bookings for selected week…';
    } else if (binding.moreError != null) {
      message = 'Some bookings could not load. Selected week is incomplete.';
    } else if (binding.hasMore) {
      message = 'Selected week is incomplete. Load more to view the schedule.';
    } else if (binding.liveError != null) {
      message = 'Live updates interrupted. Reconnect to check this week.';
    } else {
      return const SizedBox.shrink();
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: SemanticColors.of(context).primarySurface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (binding.loading || binding.loadingMore)
              const LinearProgressIndicator(minHeight: 2),
            Text(
              message,
              style: TextStyle(
                color: SemanticColors.of(context).textPrimary,
                fontSize: 12,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                if ((binding.error != null || binding.refreshError != null) &&
                    !binding.loading)
                  TextButton(
                    onPressed: binding.refresh,
                    child: const Text('Retry'),
                  ),
                if (!binding.loading &&
                    !binding.loadingMore &&
                    (binding.hasMore || binding.moreError != null))
                  TextButton(
                    onPressed: binding.loadMore,
                    child: Text(
                      binding.moreError == null
                          ? 'Load more'
                          : 'Retry load more',
                    ),
                  ),
                if (binding.liveError != null && !binding.loading)
                  TextButton(
                    onPressed: binding.retryLive,
                    child: const Text('Retry live updates'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Retains week navigation without drawing an empty availability grid.
class ScheduleUnavailableWeek extends StatelessWidget {
  const ScheduleUnavailableWeek({
    super.key,
    required this.weekStart,
    required this.onChangeWeek,
  });
  final DateTime weekStart;
  final ValueChanged<DateTime> onChangeWeek;

  @override
  Widget build(BuildContext context) {
    final last = weekStart.add(const Duration(days: 6));
    final localizations = MaterialLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous week',
              onPressed: () =>
                  onChangeWeek(weekStart.subtract(const Duration(days: 7))),
            ),
            Expanded(
              child: Text(
                '${localizations.formatShortDate(weekStart)} – ${localizations.formatShortDate(last)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next week',
              onPressed: () =>
                  onChangeWeek(weekStart.add(const Duration(days: 7))),
            ),
          ],
        ),
        const Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'The calendar will appear when this week is fully loaded.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
