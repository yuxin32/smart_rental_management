import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/demo_data.dart';
import '../services/backend/schedule_binding.dart';
import '../services/booking_reminder_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/status_chip.dart';
import 'booking_detail_screen.dart';
import 'provider_availability_screen.dart';
import 'schedule_screen.dart'
    show
        ScheduleConnectionStatus,
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
      this.bottomNavigationBar,
      this.reminders,
      this.onReminderSettings,
      this.initialDay});
  final String providerName;
  final List<DemoBooking> bookings;
  final ScheduleBinding? binding;
  final Future<void> Function(DemoBooking)? onBooking;
  final Future<void> Function()? onManageAvailability, onReminderSettings;
  final Widget? bottomNavigationBar;
  final BookingReminderController? reminders;
  final DateTime? initialDay;
  @override
  State<ProviderScheduleScreen> createState() => _ProviderScheduleState();
}

class _ProviderScheduleState extends State<ProviderScheduleScreen> {
  late DateTime _month, _selected;
  bool _opening = false;
  DateTime get _now =>
      widget.binding == null ? DateTime.now() : ScheduleBinding.malaysiaNow();
  bool get _ready =>
      widget.binding == null ||
      (widget.binding!.complete && widget.binding!.liveError == null);
  @override
  void initState() {
    super.initState();
    final initial = widget.initialDay ?? widget.binding?.weekStart ?? _now;
    _month = DateTime.utc(initial.year, initial.month, 1);
    _selected = widget.initialDay ??
        (_now.year == _month.year && _now.month == _month.month
            ? _now
            : initial);
    widget.binding?.changeMonth(_month);
  }

  List<DemoBooking> get _bookings {
    final binding = widget.binding;
    final values = binding != null
        ? binding.error == null
            ? binding.bookings
            : <DemoBooking>[]
        : widget.bookings.where((b) => b.providerName == widget.providerName);
    return values
        .where((b) =>
            b.status.blocksProviderSlot || b.status == BookingStatus.completed)
        .toList();
  }

  void _select(DateTime date) {
    final month = DateTime.utc(date.year, date.month, 1);
    setState(() {
      _month = month;
      _selected = DateTime.utc(date.year, date.month, date.day);
    });
    widget.binding?.changeMonth(month);
  }

  Future<void> _open(DemoBooking booking) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (widget.binding != null) {
        await scheduleRunAction(context,
            widget.onBooking == null ? null : () => widget.onBooking!(booking));
      } else {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => BookingDetailScreen(booking: booking)));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _availability() {
    if (widget.binding != null) {
      scheduleRunAction(context, widget.onManageAvailability);
      return;
    }
    final store = AppProviders.of(context).providerStore;
    final provider =
        store.providers.where((p) => p.name == widget.providerName).firstOrNull;
    if (provider != null)
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ProviderAvailabilityScreen(
              store: store, providerId: provider.id)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([
        if (widget.binding != null) widget.binding!,
        if (widget.reminders != null) widget.reminders!
      ]),
      builder: (context, _) => _screen(context));
  Widget _screen(BuildContext context) {
    final colors = SemanticColors.of(context), all = _bookings;
    final jobs = all.where((b) => scheduleOverlapsDay(b, _selected)).toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    final day = DateTime(_selected.year, _selected.month, _selected.day),
        next = DateTime(_selected.year, _selected.month, _selected.day + 1);
    final hours = jobs.fold<double>(0, (sum, b) {
      final start = scheduleWallTime(b.scheduledStart),
          end = scheduleWallTime(b.scheduledEnd);
      return sum +
          (end.isBefore(next) ? end : next)
                  .difference(start.isAfter(day) ? start : day)
                  .inMinutes /
              60;
    });
    final reminders = widget.reminders;
    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: AppBar(title: const Text('My schedule'), actions: [
        TextButton(onPressed: () => _select(_now), child: const Text('Today')),
        if (widget.onReminderSettings != null)
          IconButton(
              tooltip: 'Booking reminders',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () =>
                  scheduleRunAction(context, widget.onReminderSettings)),
        IconButton(
            tooltip: 'Manage availability',
            icon: const Icon(Icons.tune),
            onPressed: _availability),
      ]),
      body: RefreshIndicator(
          onRefresh: widget.binding?.refresh ?? () async {},
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        if (widget.binding != null)
                          ScheduleConnectionStatus(binding: widget.binding!),
                        ProviderMonthCalendar(
                            month: _month,
                            selectedDay: _selected,
                            today: _now,
                            bookings: all,
                            complete: _ready,
                            onSelect: _select),
                        const SizedBox(height: 18),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        DateFormat('EEEE, d MMM')
                                            .format(_selected),
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: colors.textPrimary)),
                                    const SizedBox(height: 5),
                                    Text(
                                        _ready
                                            ? '${jobs.length} ${jobs.length == 1 ? 'job' : 'jobs'}${jobs.isEmpty ? '' : ' · ${hours.toStringAsFixed(hours % 1 == 0 ? 0 : 1)} hours booked'}'
                                            : 'Finish loading this month to see the day’s jobs.',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: colors.textSecondary)),
                                  ])),
                              const SizedBox(width: 8),
                              Text('MYT',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary)),
                            ]),
                        const SizedBox(height: 16),
                        if (_ready && jobs.isEmpty)
                          Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                  color: colors.surface,
                                  border: Border.all(color: colors.border),
                                  borderRadius: BorderRadius.circular(16)),
                              child: Column(children: [
                                Icon(Icons.event_available_outlined,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    size: 30),
                                const SizedBox(height: 12),
                                const Text('No jobs scheduled',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 7),
                                Text(
                                    'Your working hours are managed separately.',
                                    textAlign: TextAlign.center,
                                    style:
                                        TextStyle(color: colors.textSecondary))
                              ])),
                        if (_ready)
                          for (final booking in jobs)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _job(booking, colors)),
                        if (reminders != null && reminders.accountBound)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.notifications_outlined,
                                  size: 20),
                              title: Text(
                                  !reminders.supported
                                      ? 'Phone reminders need Android'
                                      : !reminders.permissionGranted
                                          ? 'Allow phone reminders'
                                          : !reminders.enabled
                                              ? 'Booking reminders are off'
                                              : reminders.failed
                                                  ? 'Reminders need a sync'
                                                  : reminders.dayBefore
                                                      ? 'Reminders · 1 hour and 1 day before'
                                                      : 'Reminders · 1 hour before',
                                  style: const TextStyle(fontSize: 13)),
                              onTap: widget.onReminderSettings == null
                                  ? null
                                  : () => scheduleRunAction(
                                      context, widget.onReminderSettings)),
                        const SizedBox(height: 12),
                        Text(
                            'Showing booked jobs. Empty days do not confirm availability.',
                            style: TextStyle(
                                fontSize: 12, color: colors.textSecondary)),
                      ])))),
    );
  }

  Widget _job(DemoBooking booking, SemanticColors colors) {
    final start = scheduleWallTime(booking.scheduledStart),
        end = scheduleWallTime(booking.scheduledEnd);
    final times =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(DateFormat('h:mm a').format(start),
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 5),
      Text(DateFormat('h:mm a').format(end),
          style: TextStyle(fontSize: 12, color: colors.textSecondary))
    ]);
    final details =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(booking.property,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary)),
      const SizedBox(height: 5),
      Text(booking.serviceType,
          style: TextStyle(fontSize: 13, color: colors.textSecondary)),
      const SizedBox(height: 10),
      StatusChip(status: booking.status)
    ]);
    return Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.border)),
        child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _opening ? null : () => _open(booking),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [times, const SizedBox(height: 12), details])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            SizedBox(width: 78, child: times),
                            const SizedBox(width: 12),
                            Expanded(child: details)
                          ]))));
  }
}

/// Visible dates remain usable during loading; job dots require complete data.
class ProviderMonthCalendar extends StatelessWidget {
  const ProviderMonthCalendar(
      {super.key,
      required this.month,
      required this.selectedDay,
      required this.today,
      required this.bookings,
      required this.complete,
      required this.onSelect});
  final DateTime month, selectedDay, today;
  final List<DemoBooking> bookings;
  final bool complete;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) {
    final colors = SemanticColors.of(context),
        scheme = Theme.of(context).colorScheme;
    final first = DateTime.utc(month.year, month.month, 1),
        last = DateTime.utc(month.year, month.month + 1, 0);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final cells = ((first.weekday - 1 + last.day) / 7).ceil() * 7;
    final scale = MediaQuery.textScalerOf(context).scale(1),
        localizations = MaterialLocalizations.of(context);
    return _MonthSwipe(
        onChange: (offset) =>
            onSelect(DateTime.utc(month.year, month.month + offset, 1)),
        child: Column(children: [
          Row(children: [
            IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () =>
                    onSelect(DateTime.utc(month.year, month.month - 1, 1))),
            Expanded(
                child: Text(DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary))),
            IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: () =>
                    onSelect(DateTime.utc(month.year, month.month + 1, 1))),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth / 7,
                narrow = width < 45 || scale > 1.3;
            return Column(children: [
              Row(
                  children: List.generate(
                      7,
                      (i) => Expanded(
                          child: Semantics(
                              label: DateFormat('EEEE')
                                  .format(DateTime.utc(2026, 10, 26 + i)),
                              child: ExcludeSemantics(
                                  child: Text(
                                      narrow
                                          ? localizations
                                              .narrowWeekdays[(i + 1) % 7]
                                          : const [
                                              'Mon',
                                              'Tue',
                                              'Wed',
                                              'Thu',
                                              'Fri',
                                              'Sat',
                                              'Sun'
                                            ][i],
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: colors.textSecondary))))))),
              const SizedBox(height: 8),
              Wrap(
                  children: List.generate(cells, (i) {
                final date = start.add(Duration(days: i)),
                    inMonth = date.month == month.month;
                final selected = DateUtils.isSameDay(date, selectedDay),
                    isToday = DateUtils.isSameDay(date, today);
                final hasJob = complete &&
                    inMonth &&
                    bookings.any((b) => scheduleOverlapsDay(b, date));
                return SizedBox(
                    width: width,
                    height: 48 * (scale < 1 ? 1 : scale),
                    child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Semantics(
                            button: true,
                            selected: selected,
                            label:
                                '${DateFormat('EEEE, d MMMM yyyy').format(date)}${isToday ? ', today' : ''}${hasJob ? ', booked jobs' : ''}',
                            child: ExcludeSemantics(
                                child: Material(
                                    color: selected
                                        ? scheme.primary
                                        : Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(11),
                                        side: BorderSide(
                                            color: selected
                                                ? scheme.primary
                                                : isToday
                                                    ? colors.border
                                                    : Colors.transparent)),
                                    child: InkWell(
                                        key: ValueKey(
                                            'provider-calendar-${DateFormat('yyyy-MM-dd').format(date)}'),
                                        borderRadius: BorderRadius.circular(11),
                                        onTap: () => onSelect(date),
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text('${date.day}',
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: selected
                                                          ? scheme.onPrimary
                                                          : inMonth
                                                              ? colors
                                                                  .textPrimary
                                                              : colors
                                                                  .textTertiary)),
                                              const SizedBox(height: 4),
                                              SizedBox(
                                                  height: 4,
                                                  width: 4,
                                                  child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: hasJob
                                                              ? selected
                                                                  ? scheme
                                                                      .onPrimary
                                                                  : scheme
                                                                      .primary
                                                              : Colors
                                                                  .transparent))),
                                            ])))))));
              })),
            ]);
          }),
          const SizedBox(height: 9),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  complete
                      ? '•  Has bookings'
                      : 'Booked days appear after this month is fully loaded.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary))),
          const SizedBox(height: 14),
          Divider(color: colors.border, height: 1)
        ]));
  }
}

/// Recognise horizontal drags only, so date taps and the page's vertical
/// scrolling/pull-to-refresh retain their own gestures. Commit once per drag.
class _MonthSwipe extends StatefulWidget {
  const _MonthSwipe({required this.onChange, required this.child});
  final ValueChanged<int> onChange;
  final Widget child;
  @override
  State<_MonthSwipe> createState() => _MonthSwipeState();
}

class _MonthSwipeState extends State<_MonthSwipe> {
  double _distance = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('provider-calendar-month-swipe'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => _distance = 0,
        onHorizontalDragUpdate: (details) =>
            _distance += details.primaryDelta ?? 0,
        onHorizontalDragCancel: () => _distance = 0,
        onHorizontalDragEnd: (_) {
          final distance = _distance;
          _distance = 0;
          if (distance.abs() >= 48) {
            widget.onChange(distance < 0 ? 1 : -1);
          }
        },
        child: widget.child,
      );
}
