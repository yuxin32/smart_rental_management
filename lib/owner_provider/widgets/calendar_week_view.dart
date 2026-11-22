// lib/widgets/calendar_week_view.dart
// Week timeline: 7-day strip header + time-grid body with booking blocks.
// Each booking renders as a colored block positioned by its start/end time.

import 'package:flutter/material.dart';
import '../models/demo_data.dart';
import '../theme/app_theme.dart';

class CalendarWeekView extends StatelessWidget {
  const CalendarWeekView({
    super.key,
    required this.weekStart,
    required this.bookings,
    required this.onTapBooking,
    this.onChangeWeek,
    this.selectedDay,
    this.onSelectDay,
    this.today = const {},
  });

  /// Monday of the displayed week.
  final DateTime weekStart;

  /// All bookings; we filter to those falling inside the week.
  final List<DemoBooking> bookings;

  /// Fires when a booking block is tapped.
  final void Function(DemoBooking) onTapBooking;

  /// Optional: fires when user taps prev/next/today.
  final void Function(DateTime newWeekStart)? onChangeWeek;

  /// When supplied, narrow layouts show this day in a readable single-day
  /// timeline while retaining the full week selector above it.
  final DateTime? selectedDay;
  final void Function(DateTime day)? onSelectDay;

  /// Set of DateTimes (year, month, day) to highlight as today.
  /// Pass `{DateTime.now()}` to highlight current day.
  final Set<DateTime> today;

  static const double _hourHeight = 56;
  static const double _timeColumnWidth = 60;
  // Keep the original 07–21 default, but never clip real early/late/cross-day
  // appointments out of existence. Inputs use MYT wall-clock display fields.
  int get _startHour {
    var first = 7;
    for (final day in _days) {
      for (final booking in _bookingsForDay(day)) {
        final hour = (_slice(booking, day).$1 / 60).floor();
        if (hour < first) first = hour;
      }
    }
    return first;
  }

  int get _endHour {
    var last = 21;
    for (final day in _days) {
      for (final booking in _bookingsForDay(day)) {
        final hour = (_slice(booking, day).$2 / 60).ceil();
        if (hour > last) last = hour;
      }
    }
    return last;
  }

  int get _hourCount => _endHour - _startHour;
  static DateTime _wall(DateTime value) => DateTime.utc(value.year, value.month,
      value.day, value.hour, value.minute, value.second);
  (double, double) _slice(DemoBooking booking, DateTime day) {
    final midnight = DateTime.utc(day.year, day.month, day.day);
    return (
      (_wall(booking.scheduledStart).difference(midnight).inSeconds / 60)
          .clamp(0, 1440)
          .toDouble(),
      (_wall(booking.scheduledEnd).difference(midnight).inSeconds / 60)
          .clamp(0, 1440)
          .toDouble(),
    );
  }

  List<DateTime> get _days {
    return List.generate(7, (i) => weekStart.add(Duration(days: i)));
  }

  List<DemoBooking> _bookingsForDay(DateTime day) {
    return bookings.where((b) {
      final slice = _slice(b, day);
      return slice.$2 > slice.$1;
    }).toList();
  }

  bool _isToday(DateTime day) {
    return today.any(
        (t) => t.year == day.year && t.month == day.month && t.day == day.day);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = selectedDay != null && constraints.maxWidth < 600;
        return Column(
          children: [
            _buildToolbar(context),
            const SizedBox(height: 8),
            _buildDayHeader(context, compact: compact),
            if (compact) _buildSelectedDayLabel(context),
            Divider(
                height: 1,
                thickness: 1,
                color: SemanticColors.of(context).border),
            Expanded(child: _buildGrid(context, compact ? selectedDay : null)),
          ],
        );
      },
    );
  }

  Widget _buildSelectedDayLabel(BuildContext context) {
    final day = selectedDay!;
    final count = _bookingsForDay(day).length;
    final sem = SemanticColors.of(context);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      width: double.infinity,
      color: sem.primarySurface.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '${weekdays[day.weekday - 1]} ${day.day} ${_monthName(day.month)}  ·  '
        '$count ${count == 1 ? 'job' : 'jobs'}',
        key: const ValueKey('schedule-selected-day-label'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: sem.textPrimary,
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final first = _days.first;
    final last = _days.last;
    final monthLabel = _monthName(first.month);
    final sem = SemanticColors.of(context);
    return Container(
      color: selectedDay == null ? sem.surface : sem.primarySurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                onChangeWeek?.call(weekStart.subtract(const Duration(days: 7))),
            tooltip: 'Previous week',
          ),
          Expanded(
            child: Center(
              child: Text(
                '$monthLabel ${first.day} - ${_monthName(last.month)} ${last.day}, ${last.year}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: sem.textPrimary),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                onChangeWeek?.call(weekStart.add(const Duration(days: 7))),
            tooltip: 'Next week',
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeader(BuildContext context, {required bool compact}) {
    final sem = SemanticColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      color: sem.surfaceAlt,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: _timeColumnWidth),
          ..._days.asMap().entries.map((e) {
            final day = e.value;
            final isToday = _isToday(day);
            final isSelected = compact &&
                selectedDay!.year == day.year &&
                selectedDay!.month == day.month &&
                selectedDay!.day == day.day;
            final highlighted = compact ? isSelected : isToday;
            return Expanded(
              child: InkWell(
                onTap: compact ? () => onSelectDay?.call(day) : null,
                child: Column(
                  children: [
                    Text(
                      weekdays[e.key],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: highlighted ? scheme.primary : sem.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                            highlighted ? scheme.primary : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              highlighted ? scheme.onPrimary : sem.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, DateTime? focusedDay) {
    final sem = SemanticColors.of(context);
    final visibleDays = focusedDay == null ? _days : [focusedDay];
    return SingleChildScrollView(
      child: SizedBox(
        height: _hourHeight * _hourCount,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hour labels
            SizedBox(
              width: _timeColumnWidth,
              child: Column(
                children: List.generate(_hourCount, (i) {
                  final hour = _startHour + i;
                  return SizedBox(
                    height: _hourHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, right: 8, top: 3),
                      child: Text(
                        _formatHour(hour),
                        textAlign: TextAlign.right,
                        style:
                            TextStyle(fontSize: 11, color: sem.textSecondary),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // 7 day columns
            ...visibleDays.map((day) => Expanded(
                  child: _buildDayColumn(context, day,
                      focused: focusedDay != null),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildDayColumn(BuildContext context, DateTime day,
      {required bool focused}) {
    final sem = SemanticColors.of(context);
    final dayBookings = _bookingsForDay(day)
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    final laneEnds = <double>[];
    final lanes = <String, int>{};
    for (final booking in dayBookings) {
      final slice = _slice(booking, day);
      var lane = laneEnds.indexWhere((end) => end <= slice.$1);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(slice.$2);
      } else {
        laneEnds[lane] = slice.$2;
      }
      lanes[booking.id] = lane;
    }
    return Container(
      decoration: BoxDecoration(
        color:
            _isToday(day) ? sem.primarySurface.withOpacity(0.32) : sem.surface,
        border: Border(left: BorderSide(color: sem.border, width: 0.5)),
      ),
      child: LayoutBuilder(
          builder: (context, constraints) => Stack(
                children: [
                  // Hour grid lines
                  Column(
                    children: List.generate(_hourCount, (i) {
                      return Container(
                        height: _hourHeight,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: sem.border.withOpacity(0.55),
                                width: i == _hourCount - 1 ? 0 : 1),
                          ),
                        ),
                      );
                    }),
                  ),
                  // Booking blocks
                  ...dayBookings.map((b) => _buildBookingBlock(context, b, day,
                      focused: focused,
                      lane: lanes[b.id]!,
                      laneCount: laneEnds.length,
                      columnWidth: constraints.maxWidth)),
                ],
              )),
    );
  }

  Widget _buildBookingBlock(BuildContext context, DemoBooking b, DateTime day,
      {required bool focused,
      required int lane,
      required int laneCount,
      required double columnWidth}) {
    final sem = SemanticColors.of(context);
    final slice = _slice(b, day);
    final startHour = slice.$1 / 60;
    final endHour = slice.$2 / 60;
    final clampedStart =
        startHour.clamp(_startHour.toDouble(), _endHour.toDouble());
    final clampedEnd =
        endHour.clamp(_startHour.toDouble(), _endHour.toDouble());
    final top = (clampedStart - _startHour) * _hourHeight;
    final height = ((clampedEnd - clampedStart) * _hourHeight)
        .clamp(24.0, double.infinity);
    final color = b.status.color;
    // Strip down the property name so it fits the narrow cell:
    //   "Unit C-21, Menara Suria" -> "C-21"
    final unitMatch = RegExp(r'Unit\s+([A-Z]-\d{2})').firstMatch(b.property);
    final shortLabel = unitMatch?.group(1) ?? b.property.split(',').first;
    return Positioned(
      top: top,
      left: columnWidth * lane / laneCount + 2,
      width: (columnWidth / laneCount - 4).clamp(1.0, double.infinity),
      child: GestureDetector(
        onTap: () => onTapBooking(b),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(
              horizontal: focused ? 6 : 2,
              vertical: height < 48
                  ? 2
                  : focused
                      ? 8
                      : 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                  child: Text(
                focused ? b.property : shortLabel,
                style: TextStyle(
                    fontSize: focused ? 13 : 10,
                    fontWeight: FontWeight.w700,
                    color: color),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              )),
              if (height >= (focused ? 60 : 40)) ...[
                SizedBox(height: focused ? 4 : 1),
                Flexible(
                    child: Text(
                  b.serviceType,
                  style: TextStyle(
                      fontSize: focused ? 12 : 9, color: sem.textPrimary),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatHour(int h) {
    if (h == 0) return '12 AM';
    if (h < 12) return '$h AM';
    if (h == 12) return '12 PM';
    return '${h - 12} PM';
  }

  String _monthName(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return names[m - 1];
  }
}

/// Returns the Monday of the week containing [date] (00:00 local).
DateTime mondayOf(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - 1));
}
